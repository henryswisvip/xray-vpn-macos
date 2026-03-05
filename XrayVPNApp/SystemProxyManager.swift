import Foundation
import os.log

enum SystemProxyError: LocalizedError {
    case noNetworkServices
    case commandFailed(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .noNetworkServices:
            return "No configurable network services were found."
        case .commandFailed(let command, let output):
            return "Command failed: \(command)\n\(output)"
        }
    }
}

final class SystemProxyManager {
    private struct SocksSnapshot {
        let enabled: Bool
        let host: String
        let port: Int
    }

    private let logger = Logger(subsystem: "com.henryswisvip.xrayvpn", category: "SystemProxy")
    private var snapshotsByService: [String: SocksSnapshot] = [:]

    func enableSocksProxy(host: String, port: Int) throws {
        let services = try listNetworkServices()
        guard !services.isEmpty else {
            throw SystemProxyError.noNetworkServices
        }

        if snapshotsByService.isEmpty {
            snapshotsByService = try readSnapshots(for: services)
        }

        var appliedCount = 0
        var errors: [String] = []

        for service in services {
            do {
                try runNetworksetup(["-setsocksfirewallproxy", service, host, String(port)])
                try runNetworksetup(["-setsocksfirewallproxystate", service, "on"])
                appliedCount += 1
            } catch {
                errors.append("\(service): \(error.localizedDescription)")
            }
        }

        guard appliedCount > 0 else {
            throw SystemProxyError.commandFailed(
                command: "networksetup -setsocksfirewallproxy/-setsocksfirewallproxystate",
                output: errors.joined(separator: "\n")
            )
        }

        logger.log("Enabled SOCKS proxy on \(appliedCount) network service(s)")
    }

    func restoreSocksProxyIfNeeded() throws {
        guard !snapshotsByService.isEmpty else { return }

        var errors: [String] = []

        for (service, snapshot) in snapshotsByService {
            do {
                if snapshot.enabled {
                    try runNetworksetup([
                        "-setsocksfirewallproxy",
                        service,
                        snapshot.host,
                        String(snapshot.port)
                    ])
                    try runNetworksetup(["-setsocksfirewallproxystate", service, "on"])
                } else {
                    try runNetworksetup(["-setsocksfirewallproxystate", service, "off"])
                }
            } catch {
                errors.append("\(service): \(error.localizedDescription)")
            }
        }

        snapshotsByService.removeAll()

        if !errors.isEmpty {
            throw SystemProxyError.commandFailed(
                command: "networksetup restore SOCKS settings",
                output: errors.joined(separator: "\n")
            )
        }

        logger.log("Restored previous SOCKS proxy settings")
    }

    private func readSnapshots(for services: [String]) throws -> [String: SocksSnapshot] {
        var snapshots: [String: SocksSnapshot] = [:]

        for service in services {
            let output = try runNetworksetup(["-getsocksfirewallproxy", service])
            let fields = keyValueFields(from: output)

            snapshots[service] = SocksSnapshot(
                enabled: (fields["Enabled"] ?? "").lowercased() == "yes",
                host: fields["Server"] ?? "",
                port: Int(fields["Port"] ?? "") ?? 0
            )
        }

        return snapshots
    }

    private func listNetworkServices() throws -> [String] {
        let output = try runNetworksetup(["-listallnetworkservices"])
        var services: [String] = []

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("An asterisk") { continue }
            if line.hasPrefix("*") { continue }
            services.append(line)
        }

        return services
    }

    private func keyValueFields(from output: String) -> [String: String] {
        var fields: [String: String] = [:]

        for rawLine in output.components(separatedBy: .newlines) {
            guard let separator = rawLine.firstIndex(of: ":") else { continue }
            let key = String(rawLine[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(rawLine[rawLine.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            fields[key] = value
        }

        return fields
    }

    private func runNetworksetup(_ arguments: [String]) throws -> String {
        do {
            return try runCommand("/usr/sbin/networksetup", arguments)
        } catch let SystemProxyError.commandFailed(command, output) {
            if isAuthorizationFailure(output) {
                return try runNetworksetupAsAdmin(arguments, baseCommand: command)
            }
            throw SystemProxyError.commandFailed(command: command, output: output)
        } catch {
            throw error
        }
    }

    private func runNetworksetupAsAdmin(_ arguments: [String], baseCommand: String) throws -> String {
        let shellCommand = "/usr/sbin/networksetup " + arguments.map(shellEscaped).joined(separator: " ")
        let escapedForAppleScript = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escapedForAppleScript)\" with administrator privileges"

        do {
            return try runCommand("/usr/bin/osascript", ["-e", script])
        } catch let SystemProxyError.commandFailed(_, output) {
            throw SystemProxyError.commandFailed(command: baseCommand, output: output)
        } catch {
            throw error
        }
    }

    private func isAuthorizationFailure(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("authorizationcreate") ||
            lower.contains("must be root") ||
            lower.contains("-60008") ||
            lower.contains("not authorized")
    }

    private func shellEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func runCommand(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw SystemProxyError.commandFailed(
                command: ([launchPath] + arguments).joined(separator: " "),
                output: error.localizedDescription
            )
        }

        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw SystemProxyError.commandFailed(
                command: ([launchPath] + arguments).joined(separator: " "),
                output: stderr.isEmpty ? stdout : stderr
            )
        }

        return stdout
    }
}
