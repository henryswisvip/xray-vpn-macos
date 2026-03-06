import Foundation

enum SubscriptionParserError: LocalizedError {
    case invalidText
    case noSupportedServers

    var errorDescription: String? {
        switch self {
        case .invalidText:
            return "Subscription response is not valid text."
        case .noSupportedServers:
            return "No supported VMess/VLESS WebSocket servers found in subscription."
        }
    }
}

enum SubscriptionParser {
    static func parseServers(from data: Data, defaultSocksPort: Int) throws -> [ManagedServer] {
        guard let utf8 = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw SubscriptionParserError.invalidText
        }

        let responseText = decodedSubscriptionTextIfNeeded(utf8)
        let lines = responseText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        var servers: [ManagedServer] = []

        for (index, line) in lines.enumerated() {
            if let vmess = parseVMess(line: line, index: index, defaultSocksPort: defaultSocksPort) {
                servers.append(vmess)
                continue
            }

            if let vless = parseVLESS(line: line, index: index, defaultSocksPort: defaultSocksPort) {
                servers.append(vless)
            }
        }

        guard !servers.isEmpty else {
            throw SubscriptionParserError.noSupportedServers
        }

        var seenIDs = Set<String>()
        return servers.filter { seenIDs.insert($0.id).inserted }
    }

    private static func decodedSubscriptionTextIfNeeded(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("vmess://") || trimmed.contains("vless://") {
            return trimmed
        }

        let compact = trimmed.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        guard let decoded = decodeBase64String(compact) else {
            return trimmed
        }

        if decoded.contains("vmess://") || decoded.contains("vless://") {
            return decoded
        }

        return trimmed
    }

    private static func decodeBase64String(_ value: String) -> String? {
        let normalized = normalizedBase64(value)
        guard let data = Data(base64Encoded: normalized) else {
            return nil
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
    }

    private static func normalizedBase64(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let basic = trimmed
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = basic.count % 4
        guard remainder != 0 else { return basic }
        return basic + String(repeating: "=", count: 4 - remainder)
    }

    private static func parseVMess(line: String, index: Int, defaultSocksPort: Int) -> ManagedServer? {
        guard line.hasPrefix("vmess://") else { return nil }
        let base64Payload = String(line.dropFirst("vmess://".count))
        guard let json = decodeBase64String(base64Payload),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }

        let address = stringValue(dictionary, keys: ["add", "address"])
        let userID = stringValue(dictionary, keys: ["id", "uuid"])
        let port = intValue(dictionary, keys: ["port"]) ?? 443
        let network = stringValue(dictionary, keys: ["net"]).lowercased()

        guard !address.isEmpty, !userID.isEmpty else { return nil }
        if !network.isEmpty && network != "ws" { return nil }

        let displayName = preferredDisplayName(
            primary: stringValue(dictionary, keys: ["ps", "remark"]),
            fallbackAddress: address,
            fallbackPort: port,
            index: index
        )

        let wsPath = sanitizePath(stringValue(dictionary, keys: ["path"]))
        let wsHost = stringValue(dictionary, keys: ["host"])

        let tlsMode = stringValue(dictionary, keys: ["tls", "security"]).lowercased()
        let useTLS = tlsMode == "tls" || tlsMode == "xtls" || tlsMode == "reality"
        let sni = stringValue(dictionary, keys: ["sni"])

        return ManagedServer(
            id: stableID(prefix: "vmess", address: address, port: port, userID: userID, index: index),
            name: displayName,
            region: "Subscription",
            endpoint: TunnelEndpoint(
                remark: displayName,
                address: address,
                port: port,
                userID: userID,
                useTLS: useTLS,
                sni: sni,
                wsPath: wsPath,
                wsHost: wsHost,
                allowInsecure: false,
                socksPort: defaultSocksPort
            )
        )
    }

    private static func parseVLESS(line: String, index: Int, defaultSocksPort: Int) -> ManagedServer? {
        guard line.hasPrefix("vless://"),
              let components = URLComponents(string: line),
              let address = components.host
        else {
            return nil
        }

        let userID = components.user ?? ""
        let port = components.port ?? 443
        guard !userID.isEmpty else { return nil }

        let queryItems = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { item in
                (item.name.lowercased(), item.value ?? "")
            }
        )

        let network = queryItems["type", default: ""].lowercased()
        if !network.isEmpty && network != "ws" { return nil }

        let useTLSMode = queryItems["security", default: ""].lowercased()
        let useTLS = useTLSMode == "tls" || useTLSMode == "reality"
        let wsPath = sanitizePath(queryItems["path", default: ""])
        let wsHost = queryItems["host", default: ""]
        let sni = queryItems["sni", default: ""]

        let fragmentName = components.fragment?.removingPercentEncoding ?? ""
        let displayName = preferredDisplayName(
            primary: fragmentName,
            fallbackAddress: address,
            fallbackPort: port,
            index: index
        )

        return ManagedServer(
            id: stableID(prefix: "vless", address: address, port: port, userID: userID, index: index),
            name: displayName,
            region: "Subscription",
            endpoint: TunnelEndpoint(
                remark: displayName,
                address: address,
                port: port,
                userID: userID,
                useTLS: useTLS,
                sni: sni,
                wsPath: wsPath,
                wsHost: wsHost,
                allowInsecure: false,
                socksPort: defaultSocksPort
            )
        )
    }

    private static func stringValue(_ dictionary: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = dictionary[key] as? NSNumber {
                return value.stringValue
            }
        }
        return ""
    }

    private static func intValue(_ dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? String, let int = Int(value) {
                return int
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
        }
        return nil
    }

    private static func sanitizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private static func preferredDisplayName(primary: String, fallbackAddress: String, fallbackPort: Int, index: Int) -> String {
        let cleaned = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            return cleaned
        }
        return "Server \(index + 1) (\(fallbackAddress):\(fallbackPort))"
    }

    private static func stableID(prefix: String, address: String, port: Int, userID: String, index: Int) -> String {
        let suffix = String(userID.prefix(8))
        return "\(prefix)-\(address)-\(port)-\(suffix)-\(index)"
    }
}
