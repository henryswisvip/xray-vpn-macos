# AGENTS.md

## Cursor Cloud specific instructions

### Platform constraint

This is a **native macOS Swift/SwiftUI application** (Sprout Connect / XrayVPN). It requires **macOS 13+** and **Xcode 15+** to build and run. The cloud VM runs Linux, so **building the `.app` bundle and running the GUI are not possible here**. All build/run scripts in `Scripts/` use macOS-only tools (`xcodebuild`, `ditto`, `networksetup`).

### What works on the Linux cloud VM

| Tool | Command | Notes |
|------|---------|-------|
| **Lint** | `swiftlint lint` | SwiftLint 0.63.2 (static binary) is installed at `/usr/local/bin/swiftlint`. Runs without SourceKit (some rules skipped). |
| **Syntax check** | `swiftc -parse <file>` | Swift 6.0.3 at `/opt/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/`. Works for `Shared/*.swift` (Foundation-only). App files using `SwiftUI`/`AppKit` will fail import resolution but syntax is still partially validated. |
| **Project structure validation** | `python3 -c "import yaml; ..."` or manual review of `project.yml` | The XcodeGen spec can be validated structurally. |

### Key caveats

- `swiftlint lint` skips rules that need SourceKit (e.g. `statement_position`), since the Swift toolchain on Linux does not provide `libsourcekitdInProc.so` to the static binary. This is acceptable for CI-level linting.
- `swiftc -parse` on files that `import SwiftUI` or `import AppKit` will report import errors, not syntax errors. Use it only for `Shared/` files or new Foundation-only code.
- The `fetch_xray.sh` script downloads macOS-specific Xray binaries and uses `ditto`; it will not run on Linux.
- There are **no automated tests** in this project. No test targets or test files exist.
- There are **no third-party dependencies** (no SPM, CocoaPods, Carthage, npm, pip). The only external binary is Xray-core, fetched by `Scripts/fetch_xray.sh`.

### Project layout (quick reference)

See `README.md` for full details. Key paths:
- `project.yml` — XcodeGen project definition
- `XrayVPNApp/` — Main SwiftUI macOS app (proxy manager, system proxy, xray runner, UI)
- `Shared/` — Server list, config builder, data models (Foundation-only, can be syntax-checked on Linux)
- `XrayPacketTunnel/` — Network Extension target (placeholder/future, not in active build)
- `Scripts/` — fetch_xray.sh, generate_project.sh, package_app.sh (all macOS-only)

### Developing on macOS (reference)

On a macOS machine with Xcode 15+ and Homebrew:
1. `brew install xcodegen`
2. `./Scripts/fetch_xray.sh`
3. `./Scripts/generate_project.sh`
4. Open `XrayVPN.xcodeproj` and build (Cmd+B) / run (Cmd+R)
