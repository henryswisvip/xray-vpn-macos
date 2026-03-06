import SwiftUI

@main
struct XrayVPNApp: App {
    @StateObject private var proxyManager = ProxyManager()
    @StateObject private var serverCatalog = ServerCatalog()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(proxyManager)
                .environmentObject(serverCatalog)
                .frame(
                    minWidth: 920,
                    idealWidth: 1040,
                    maxWidth: .infinity,
                    minHeight: 700,
                    idealHeight: 760,
                    maxHeight: .infinity
                )
        }
    }
}
