import SwiftUI

/// Layout constants shared by the device frame and the window sizing.
enum DeviceMetrics {
    static let bezel: CGFloat = 11
    static let outerRadius: CGFloat = 58
    static let innerRadius: CGFloat = 48
    static let barHeight: CGFloat = 40
    static let barSpacing: CGFloat = 8
    static let shadowMargin: CGFloat = 6

    /// Window content size for a given screen width, keeping the phone's aspect ratio.
    static func windowSize(screenWidth: CGFloat, screen: ScreenSize) -> CGSize {
        let screenHeight = screenWidth * CGFloat(screen.height / max(screen.width, 1))
        return CGSize(width: screenWidth + 2 * (bezel + shadowMargin),
                      height: screenHeight + 2 * bezel + barHeight + barSpacing + 2 * shadowMargin)
    }
}

/// Black device body with a thin metallic edge; the content is clipped to the display shape.
struct DeviceFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: DeviceMetrics.outerRadius, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: DeviceMetrics.innerRadius, style: .continuous)
        ZStack {
            outer.fill(Color.black)
            WindowDragHandle().clipShape(outer)  // the bezel moves the window
            outer.strokeBorder(
                LinearGradient(colors: [Color(white: 0.55), Color(white: 0.18), Color(white: 0.42)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1.5)
                .allowsHitTesting(false)
            content
                .clipShape(inner)
                .padding(DeviceMetrics.bezel)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: DeviceMetrics.shadowMargin, y: 2)
    }
}

/// Transparent AppKit view that starts a native window drag on mouse down
/// (SwiftUI's hosting view swallows clicks, so isMovableByWindowBackground alone is not enough).
struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

/// Floating capsule with the phone controls – shown when the pointer is over the window.
struct ControlBar: View {
    @EnvironmentObject private var model: MirrorModel

    var body: some View {
        HStack(spacing: 2) {
            BarButton(symbol: "xmark", help: "Close") { NSApp.keyWindow?.performClose(nil) }
            Divider().frame(height: 16).padding(.horizontal, 4)
            BarButton(symbol: "house", help: "Home  ⇧⌘H") { model.press(.home) }
            BarButton(symbol: "square.stack", help: "App Switcher  ⇧⌘A") { model.openAppSwitcher() }
            BarButton(symbol: "speaker.minus", help: "Volume Down") { model.press(.volumeDown) }
            BarButton(symbol: "speaker.plus", help: "Volume Up") { model.press(.volumeUp) }
            BarButton(symbol: "lock", help: "Lock iPhone") { model.lock() }
            Divider().frame(height: 16).padding(.horizontal, 4)
            BarButton(symbol: model.keepOnTop ? "pin.fill" : "pin",
                      help: model.keepOnTop ? "Keep on Top: On  ⇧⌘T" : "Keep on Top: Off  ⇧⌘T",
                      isActive: model.keepOnTop) { model.keepOnTop.toggle() }
        }
        .padding(.horizontal, 8)
        .frame(height: DeviceMetrics.barHeight - 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct BarButton: View {
    let symbol: String
    let help: String
    var isActive = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 26)
                .background(hovering ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
