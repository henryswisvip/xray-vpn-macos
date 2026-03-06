import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let defaultSize: NSSize
    let minimumSize: NSSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            apply(to: view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(to: nsView.window, coordinator: context.coordinator)
        }
    }

    private func apply(to window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.minSize = minimumSize

        guard !coordinator.didApplyDefaultSize else { return }
        coordinator.didApplyDefaultSize = true
        window.setContentSize(defaultSize)
        window.center()
    }

    final class Coordinator {
        var didApplyDefaultSize = false
    }
}
