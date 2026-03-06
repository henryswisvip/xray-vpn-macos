# XrayVPN (macOS, Proxy-Only)

Starter template for a macOS app that runs **Xray Core** as a local proxy client.

This project gives you:
- A SwiftUI macOS app with a managed server dropdown and one-tap connect.
- Local SOCKS5 proxy endpoint on `127.0.0.1:<port>`.
- No Packet Tunnel extension and no system VPN entitlement dependency.
- Automatic system SOCKS proxy enable/restore on connect/disconnect.

## Important caveats

- This is **not** a system VPN tunnel. Only apps configured to use the local proxy will route through Xray.
- You must configure app or macOS proxy settings manually.
- For full-device VPN behavior, you need a separate Network Extension architecture.

## Requirements

- macOS 13+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Quick start

1. Install XcodeGen:
   ```bash
   brew install xcodegen
   ```
2. Download and install Xray Core into app resources:
   ```bash
   cd xray-vpn-macos
   ./Scripts/fetch_xray.sh
   ```
3. (Optional) Set your own bundle ID/team in `project.yml`.
4. Generate the Xcode project:
   ```bash
   ./Scripts/generate_project.sh
   ```
5. Open `XrayVPN.xcodeproj` and build.

## Run

1. Launch the app.
2. Choose a server from the dropdown.
3. Click **Connect**.
4. The app applies macOS SOCKS proxy automatically while connected (macOS may ask for admin permission).

## Build A Shareable App

End users do **not** need Xcode or a separate Xray install. The app bundle includes Xray.

1. Build a shareable zip:
   ```bash
   cd xray-vpn-macos
   ./Scripts/package_app.sh
   ```
   Output appears in `dist/` as:
   - `XrayVPNApp.app`
   - `XrayVPNApp-<timestamp>.zip`

2. For proper external distribution (recommended), build with signing:
   ```bash
   TEAM_ID=YOUR_TEAM_ID ./Scripts/package_app.sh
   ```

3. For notarized distribution (best user experience), configure a notary profile first:
   ```bash
   xcrun notarytool store-credentials xray-notary --apple-id "<APPLE_ID>" --team-id "<TEAM_ID>" --password "<APP_SPECIFIC_PASSWORD>"
   TEAM_ID=YOUR_TEAM_ID NOTARY_PROFILE=xray-notary ./Scripts/package_app.sh
   ```

## Project layout

- `XrayVPNApp/`: SwiftUI app, proxy manager, system proxy manager, and local Xray runner.
- `XrayVPNApp/Resources/`: bundled `xray`, `geoip.dat`, and `geosite.dat`.
- `Shared/`: managed server list, shared endpoint, and Xray config builder.
- `Scripts/`: helper scripts (fetch/build/generate/package).

## Managed servers

- Edit `Shared/ServiceConfig.swift` to add/remove service-managed servers shown in the dropdown.

## Customize protocol settings

Default config is VMess over WebSocket (WS), with optional TLS. Modify `Shared/XrayConfigBuilder.swift` to support:
- REALITY
- WebSocket/gRPC
- VMess/Trojan
- Custom routing rules
