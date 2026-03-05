import Foundation

struct ManagedServer: Identifiable {
    let id: String
    let name: String
    let region: String
    let endpoint: TunnelEndpoint
}
