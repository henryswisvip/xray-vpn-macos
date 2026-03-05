import Foundation
import os.log

@MainActor
final class ProxyManager: ObservableObject {
    enum Status {
        case stopped
        case starting
        case running
        case stopping
        case failed
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var isBusy = false
    @Published var lastError: String?
    @Published private(set) var activeSocksPort: Int = ServiceConfig.servers.first?.endpoint.socksPort ?? 10808

    private let logger = Logger(subsystem: "com.henryswisvip.xrayvpn", category: "ProxyManager")
    private let xrayRunner = XrayRunner()
    private let systemProxyManager = SystemProxyManager()
    private var isStoppingProcess = false

    var statusLabel: String {
        switch status {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .failed: return "Failed"
        }
    }

    var localSocksAddress: String {
        "127.0.0.1:\(activeSocksPort)"
    }

    var localSocksURL: String {
        "socks5://\(localSocksAddress)"
    }

    init() {
        xrayRunner.onTermination = { [weak self] code in
            Task { @MainActor in
                guard let self else { return }
                if self.isStoppingProcess {
                    self.isStoppingProcess = false
                    return
                }

                do {
                    try self.systemProxyManager.restoreSocksProxyIfNeeded()
                } catch {
                    self.logger.error("Failed to restore SOCKS proxy after crash: \(error.localizedDescription, privacy: .public)")
                }

                self.logger.error("xray exited with status \(code)")
                self.status = .failed
                self.lastError = "xray exited unexpectedly (status \(code))."
            }
        }
    }

    func start(server: ManagedServer) async {
        isBusy = true
        lastError = nil
        status = .starting

        defer {
            isBusy = false
        }

        do {
            isStoppingProcess = false
            let endpoint = server.endpoint
            activeSocksPort = endpoint.socksPort
            let xrayConfig = try XrayConfigBuilder.makeConfig(for: endpoint)
            try xrayRunner.start(withConfigJSON: xrayConfig)

            do {
                try systemProxyManager.enableSocksProxy(host: "127.0.0.1", port: endpoint.socksPort)
            } catch {
                isStoppingProcess = true
                xrayRunner.stop()
                isStoppingProcess = false
                throw error
            }

            status = .running
        } catch {
            status = .failed
            lastError = "Could not start proxy: \(error.localizedDescription)"
        }
    }

    func stop() {
        isBusy = true
        lastError = nil
        status = .stopping
        isStoppingProcess = true

        xrayRunner.stop()
        isStoppingProcess = false

        do {
            try systemProxyManager.restoreSocksProxyIfNeeded()
        } catch {
            logger.error("Failed to restore SOCKS proxy: \(error.localizedDescription, privacy: .public)")
            lastError = "Disconnected, but could not restore previous proxy settings."
        }

        status = .stopped
        isBusy = false
    }
}
