import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var proxyManager: ProxyManager
    @State private var selectedServerID = ServiceConfig.defaultServerID
    @State private var pulse = false
    @State private var copiedSocksURL = false

    private var selectedServer: ManagedServer? {
        ServiceConfig.server(withID: selectedServerID)
    }

    private var statusColor: Color {
        switch proxyManager.status {
        case .running:
            return Color(red: 0.18, green: 0.86, blue: 0.55)
        case .starting, .stopping:
            return Color(red: 0.97, green: 0.76, blue: 0.22)
        case .failed:
            return Color(red: 0.95, green: 0.32, blue: 0.36)
        case .stopped:
            return Color(red: 0.66, green: 0.70, blue: 0.76)
        }
    }

    private var connectButtonTitle: String {
        switch proxyManager.status {
        case .running, .starting:
            return "Disconnect"
        case .stopping:
            return "Disconnecting..."
        case .failed, .stopped:
            return "Connect"
        }
    }

    private var canChangeServer: Bool {
        proxyManager.status == .stopped || proxyManager.status == .failed
    }

    private var canToggleConnection: Bool {
        !proxyManager.isBusy && selectedServer != nil
    }

    private var connectionHint: String {
        switch proxyManager.status {
        case .running:
            return "Protected. Traffic is routed through \(selectedServer?.name ?? \"the selected server\")."
        case .starting:
            return "Starting secure route and applying system proxy settings..."
        case .stopping:
            return "Disconnecting and restoring your previous network settings..."
        case .failed:
            return "Connection failed. Check the error details and try a different server."
        case .stopped:
            return "Disconnected. Choose a server and connect when ready."
        }
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 18) {
                headerCard
                statusDetailCard
                routeCard
                actionCard

                if let error = proxyManager.lastError {
                    Text(error)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            Color(red: 0.42, green: 0.10, blue: 0.14).opacity(0.76),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }

                Spacer(minLength: 0)
            }
            .padding(28)
        }
        .onAppear {
            pulse = true
        }
    }

    private var statusDetailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))

            Text(connectionHint)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let connectedSince = proxyManager.connectedSince, proxyManager.status == .running {
                Divider().overlay(Color.white.opacity(0.14))

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    detailRow(label: "Connected for", value: uptimeString(since: connectedSince, now: context.date))
                }
            }
        }
        .padding(18)
        .cardStyle()
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.09, blue: 0.14),
                    Color(red: 0.06, green: 0.14, blue: 0.23),
                    Color(red: 0.04, green: 0.19, blue: 0.23)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.09, green: 0.51, blue: 0.70).opacity(0.20))
                .frame(width: 430, height: 430)
                .offset(x: 330, y: -260)
                .blur(radius: 8)

            Circle()
                .fill(Color(red: 0.94, green: 0.54, blue: 0.18).opacity(0.17))
                .frame(width: 320, height: 320)
                .offset(x: -280, y: 250)
                .blur(radius: 8)
        }
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.12, green: 0.70, blue: 0.85), Color(red: 0.06, green: 0.45, blue: 0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)

                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(ServiceConfig.appName)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("build by a IB student")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            Spacer()
            statusPill
        }
        .padding(20)
        .cardStyle()
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Server")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))

                Spacer()

                Picker("Server", selection: $selectedServerID) {
                    ForEach(ServiceConfig.servers) { server in
                        Text(server.name).tag(server.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!canChangeServer)
            }

            Divider().overlay(Color.white.opacity(0.14))

            detailRow(label: "Region", value: selectedServer?.region ?? "Unavailable")
            detailRow(label: "Protocol", value: "VMess / WebSocket")
            detailRow(label: "TLS", value: "Disabled")
            detailRow(label: "Local SOCKS5", value: proxyManager.localSocksAddress)
        }
        .padding(18)
        .cardStyle()
    }

    private var actionCard: some View {
        VStack(spacing: 14) {
            Button(action: toggleConnection) {
                Text(connectButtonTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.62, blue: 0.95), Color(red: 0.04, green: 0.45, blue: 0.82)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canToggleConnection)
            .opacity(canToggleConnection ? 1 : 0.55)

            HStack {
                Button(copiedSocksURL ? "Copied" : "Copy SOCKS URL") {
                    copySocksURL()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.69, green: 0.88, blue: 0.99))

                Spacer()

                Text("Auto system proxy")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.74))
            }

            Text("Connect enables macOS SOCKS proxy on your active network service automatically. Disconnect restores previous proxy settings.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.74))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .cardStyle()
        .onExitCommand(perform: toggleConnection)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .scaleEffect(pulse && (proxyManager.status == .running || proxyManager.status == .starting) ? 1.18 : 0.92)
                .animation(
                    (proxyManager.status == .running || proxyManager.status == .starting)
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                    value: pulse
                )

            Text(proxyManager.statusLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.24), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func toggleConnection() {
        switch proxyManager.status {
        case .running, .starting:
            proxyManager.stop()
        case .stopped, .failed, .stopping:
            guard let server = selectedServer else { return }
            Task {
                await proxyManager.start(server: server)
            }
        }
    }

    private func copySocksURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(proxyManager.localSocksURL, forType: .string)
        copiedSocksURL = true

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedSocksURL = false
        }
    }

    private func uptimeString(since: Date, now: Date) -> String {
        let elapsed = Int(now.timeIntervalSince(since))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        if hours > 0 {
            return String(format: "%02dh %02dm %02ds", hours, minutes, seconds)
        }
        return String(format: "%02dm %02ds", minutes, seconds)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}
