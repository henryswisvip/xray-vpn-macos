import Foundation

enum ServiceConfig {
    static let appName = "Aegis Connect"

    // Add or remove servers here; users only see this managed list.
    static let servers: [ManagedServer] = [
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
                socksPort: 10808
            )
        )
    ]

    static var defaultServerID: String {
        servers.first?.id ?? ""
    }

    static func server(withID id: String) -> ManagedServer? {
        servers.first(where: { $0.id == id })
    }
}
