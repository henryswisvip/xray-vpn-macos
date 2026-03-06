import Foundation

struct ManagedServer: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let region: String
    let endpoint: TunnelEndpoint
}
