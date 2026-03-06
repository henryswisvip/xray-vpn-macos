import Foundation

enum ServiceConfig {
    static let appName = "Sprout Connect"
    static let subscriptionURLString = "https://swis.sproutnetworks.co/s/39c264c5b503fe31a416ba02dfb2f28f"
    static let refreshInterval: TimeInterval = 300
    static let defaultSocksPort = 10808

    // Fallback list used when subscription feed is unavailable.
    static let fallbackServers: [ManagedServer] = [
        ManagedServer(
            id: "us-primary",
            name: "US Primary",
            region: "North America",
            endpoint: TunnelEndpoint(
                remark: "US Primary",
                address: "104.168.1.102",
                port: 8222,
                userID: "79d0aad7-7eb2-4393-b99b-e9bb71a20e0b",
                useTLS: false,
                sni: "",
                wsPath: "/",
                wsHost: "",
                allowInsecure: false,
                socksPort: defaultSocksPort
            )
        )
    ]

    static var subscriptionURL: URL? {
        let trimmed = subscriptionURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    static var defaultServerID: String {
        fallbackServers.first?.id ?? ""
    }

    static func server(withID id: String) -> ManagedServer? {
        fallbackServers.first(where: { $0.id == id })
    }
}
