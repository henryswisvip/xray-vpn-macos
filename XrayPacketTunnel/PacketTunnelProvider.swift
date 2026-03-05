import Foundation
import NetworkExtension
import os.log

enum PacketTunnelError: LocalizedError {
    case invalidProviderConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidProviderConfiguration:
            return "Missing provider configuration."
        }
    }
}

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "com.example.xrayvpn", category: "PacketTunnel")
    private let xrayRunner = XrayRunner()

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard
            let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
            let providerConfiguration = tunnelProtocol.providerConfiguration,
            let xrayConfig = providerConfiguration["xrayConfig"] as? String
        else {
            completionHandler(PacketTunnelError.invalidProviderConfiguration)
            return
        }

        let socksPort = providerConfiguration["socksPort"] as? Int ?? 10808

        do {
            try xrayRunner.start(withConfigJSON: xrayConfig)
        } catch {
            completionHandler(error)
            return
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4Settings

        let dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings

        let proxySettings = NEProxySettings()
        proxySettings.excludeSimpleHostnames = false
        proxySettings.matchDomains = [""]
        proxySettings.socksServer = NEProxyServer(address: "127.0.0.1", port: socksPort)
        settings.proxySettings = proxySettings

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                self?.logger.error("Tunnel setup failed: \(error.localizedDescription, privacy: .public)")
                self?.xrayRunner.stop()
                completionHandler(error)
                return
            }

            self?.logger.log("Tunnel started")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.log("Tunnel stopping, reason: \(reason.rawValue)")
        xrayRunner.stop()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        completionHandler?(Data("ok".utf8))
    }
}
