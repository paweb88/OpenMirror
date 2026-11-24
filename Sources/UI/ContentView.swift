import AppKit
import SwiftUI

/// The whole window: a floating phone with a control bar that appears on hover.
struct ContentView: View {
    @EnvironmentObject private var model: MirrorModel
    /// `--show-controls` keeps the control bar visible (used for screenshots).
    @State private var hovering = ProcessInfo.processInfo.arguments.contains("--show-controls")

    var body: some View {
        VStack(spacing: DeviceMetrics.barSpacing) {
            ControlBar()
                .opacity(hovering ? 1 : 0)
                .offset(y: hovering ? 0 : 6)
                .frame(height: DeviceMetrics.barHeight)
                .allowsHitTesting(hovering)
            DeviceFrame { screen }
                .aspectRatio(phoneAspectRatio, contentMode: .fit)
        }
        .padding(DeviceMetrics.shadowMargin)
        .frame(minWidth: 240, minHeight: 500)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { if !Self.pinnedControls { hovering = $0 } }
        .background(WindowConfigurator(keepOnTop: model.keepOnTop, screen: model.screenSize))
        .onAppear { if model.phase == .idle { model.connect() } }
    }

    private static let pinnedControls = ProcessInfo.processInfo.arguments.contains("--show-controls")

    private var phoneAspectRatio: CGFloat {
        let screen = model.screenSize
        let width = 360.0
        let height = width * screen.height / max(screen.width, 1)
        return CGFloat((width + 2 * DeviceMetrics.bezel) / (height + 2 * DeviceMetrics.bezel))
    }

    @ViewBuilder
    private var screen: some View {
        if model.phase == .connected {
            PhoneScreenView(image: model.frame, takesKeyFocus: !model.isComposing) { handle($0) }
                .overlay(alignment: .bottom) {
                    if model.isComposing {
                        ComposeBar().transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: model.isComposing)
        } else {
            StatusView().environment(\.colorScheme, .dark)
        }
    }

    private func handle(_ event: PhoneScreenView.InputEvent) {
        switch event {
        case let .pointer(start, end, held, delay):
            model.perform(GestureMapper.gesture(start: start, end: end, heldSeconds: held,
                                                delayBeforeMove: delay, size: model.screenSize))
        case let .scroll(origin, delta):
            if let swipe = GestureMapper.scrollSwipe(at: origin, normalizedDelta: delta, size: model.screenSize) {
                model.perform(swipe)
            }
        case .text(let text): model.handleKey(text)
        case .paste: model.pasteFromClipboard()
        }
    }
}

/// Turns the hosting window into a borderless, transparent, draggable floating phone.
struct WindowConfigurator: NSViewRepresentable {
    let keepOnTop: Bool
    let screen: ScreenSize

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            [.closeButton, .miniaturizeButton, .zoomButton].forEach { window.standardWindowButton($0)?.isHidden = true }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false  // the device frame draws its own shadow
            window.isMovableByWindowBackground = true
            window.level = keepOnTop ? .floating : .normal
            window.collectionBehavior = keepOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
            let size = DeviceMetrics.windowSize(screenWidth: 360, screen: screen)
            window.contentAspectRatio = size
        }
    }
}

/// Shown on the phone's "display" while connecting or when something needs attention.
struct StatusView: View {
    @EnvironmentObject private var model: MirrorModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.16), .black],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(.white.opacity(0.85))
                Text("OpenMirror").font(.title3.weight(.semibold)).foregroundStyle(.white)
                content
            }
            .padding(24)
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .connected:
            ProgressView().controlSize(.small)
        case .working(let message):
            ProgressView().controlSize(.small)
            Text(message).font(.callout).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
        case .needsUnlock:
            Image(systemName: "lock.open").font(.title2)
            Text("Unlock your iPhone").font(.headline)
            Text("Mirroring starts as soon as the phone is unlocked.")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
        case .needsTeam:
            TeamPicker()
        case .failed(let message):
            Text(message).font(.callout).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.85))
            HStack {
                Button("Reconnect") { model.connect() }.keyboardShortcut(.defaultAction)
                Button("Show Log") { NSWorkspace.shared.activateFileViewerSelecting([model.logFile]) }
            }
        }
    }
}

struct TeamPicker: View {
    @EnvironmentObject private var model: MirrorModel

    var body: some View {
        VStack(spacing: 10) {
            Text("Choose a signing team").font(.headline)
            Text("A small helper (WebDriverAgent) runs on your iPhone, signed with your Apple ID team.")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
            if !model.availableTeams.isEmpty {
                Picker("", selection: $model.teamID) {
                    ForEach(model.availableTeams, id: \.teamID) { team in
                        Text(team.teamID).tag(team.teamID)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            TextField("Team ID", text: $model.teamID).textFieldStyle(.roundedBorder).frame(width: 180)
            Button("Continue") { model.connect() }
                .keyboardShortcut(.defaultAction)
                .disabled(!SigningTeams.isValidTeamID(model.teamID))
        }
    }
}
