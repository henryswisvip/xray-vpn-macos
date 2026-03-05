import SwiftUI

@main
struct XrayVPNApp: App {
    @StateObject private var proxyManager = ProxyManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(proxyManager)
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}
