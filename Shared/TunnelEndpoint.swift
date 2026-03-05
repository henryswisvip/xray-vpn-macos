import Foundation

struct TunnelEndpoint: Codable, Equatable {
    var remark: String = "My Xray Server"
    var address: String = ""
    var port: Int = 443
    var userID: String = ""
    var useTLS: Bool = true
    var sni: String = ""
    var wsPath: String = "/"
    var wsHost: String = ""
    var allowInsecure: Bool = false
    var socksPort: Int = 10808

    init(
        remark: String = "My Xray Server",
        address: String = "",
        port: Int = 443,
        userID: String = "",
        useTLS: Bool = true,
        sni: String = "",
        wsPath: String = "/",
        wsHost: String = "",
        allowInsecure: Bool = false,
        socksPort: Int = 10808
    ) {
        self.remark = remark
        self.address = address
        self.port = port
        self.userID = userID
        self.useTLS = useTLS
        self.sni = sni
        self.wsPath = wsPath
        self.wsHost = wsHost
        self.allowInsecure = allowInsecure
        self.socksPort = socksPort
    }

    enum CodingKeys: String, CodingKey {
        case remark
        case address
        case port
        case userID
        case useTLS
        case sni
        case wsPath
        case wsHost
        case allowInsecure
        case socksPort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remark = try container.decodeIfPresent(String.self, forKey: .remark) ?? "My Xray Server"
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 443
        userID = try container.decodeIfPresent(String.self, forKey: .userID) ?? ""
        useTLS = try container.decodeIfPresent(Bool.self, forKey: .useTLS) ?? true
        sni = try container.decodeIfPresent(String.self, forKey: .sni) ?? ""
        wsPath = try container.decodeIfPresent(String.self, forKey: .wsPath) ?? "/"
        wsHost = try container.decodeIfPresent(String.self, forKey: .wsHost) ?? ""
        allowInsecure = try container.decodeIfPresent(Bool.self, forKey: .allowInsecure) ?? false
        socksPort = try container.decodeIfPresent(Int.self, forKey: .socksPort) ?? 10808
    }
}
