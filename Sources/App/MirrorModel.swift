import AppKit
import AVFoundation
import Foundation

/// Orchestrates: find iPhone → build/launch WebDriverAgent → USB tunnels → video + input.
@MainActor
final class MirrorModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working(String)
        case needsUnlock
        case needsTeam
        case connected
        case failed(String)
    }

    enum VideoSource: Equatable {
        case none
        case usbCapture
        case mjpeg
    }

    static let wdaPort: UInt16 = 8100
    static let mjpegPort: UInt16 = 9100
    static let localWDAPort: UInt16 = 18100
    static let localMJPEGPort: UInt16 = 19100
    private static let teamDefaultsKey = "teamID"
    private static let onTopDefaultsKey = "keepOnTop"

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var frame: NSImage?
    /// Live USB screen capture (60 fps + sound); nil when falling back to the MJPEG stream.
    @Published private(set) var captureSession: AVCaptureSession?
    @Published private(set) var videoSource: VideoSource = .none
    @Published private(set) var framesPerSecond: Double = 0
    @Published var showFrameRate = false
    @Published private(set) var screenSize = ScreenSize(width: 440, height: 956)
    @Published var teamID: String = UserDefaults.standard.string(forKey: teamDefaultsKey) ?? ""
    @Published var keepOnTop: Bool = UserDefaults.standard.bool(forKey: onTopDefaultsKey) {
        didSet { UserDefaults.standard.set(keepOnTop, forKey: Self.onTopDefaultsKey) }
    }

    let availableTeams = SigningTeams.discover()
    private let runner = WDARunner()
    private let client = WDAClient(baseURL: URL(string: "http://127.0.0.1:\(localWDAPort)")!)
    private var forwarders: [PortForwarder] = []
    private var stream: MJPEGStream?
    private var capture: ScreenCapture?
    private var connectTask: Task<Void, Never>?
    private var commandChain: Task<Void, Never>?
    @Published var composeText = ""
    @Published private(set) var isComposing = false

    var logFile: URL { runner.logFile }

    init() {
        if teamID.isEmpty, availableTeams.count == 1 { teamID = availableTeams[0].teamID }
        applyDemoArguments(ProcessInfo.processInfo.arguments)
    }

    /// Demo mode for screenshots – shows a static image instead of a phone, no WebDriverAgent:
    /// `--demo-screen <png>` · `--demo-compose <text>` · `--demo-connecting`
    private func applyDemoArguments(_ arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        if arguments.contains("--demo-connecting") {
            phase = .working("Starting WebDriverAgent on the iPhone…")
        } else if let path = value(after: "--demo-screen"), let image = NSImage(contentsOfFile: path) {
            frame = image
            phase = .connected
            if let text = value(after: "--demo-compose") {
                composeText = text
                isComposing = true
            }
        }
    }

    // MARK: - Lifecycle

    func connect() {
        guard SigningTeams.isValidTeamID(teamID) else { phase = .needsTeam; return }
        UserDefaults.standard.set(teamID, forKey: Self.teamDefaultsKey)
        disconnect()
        connectTask = Task { await runConnection() }
    }

    func disconnect() {
        connectTask?.cancel()
        stream?.stop()
        stream = nil
        capture?.stop()
        capture = nil
        captureSession = nil
        videoSource = .none
        forwarders.forEach { $0.stop() }
        forwarders = []
        runner.stop()
    }

    private func runConnection() async {
        do {
            phase = .working("Looking for an iPhone connected by cable…")
            let device = try await findDevice()

            let team = teamID
            let runner = self.runner
            try await Task.detached {
                try runner.prepare(teamID: team, udid: device.udid) { event in
                    Task { @MainActor in self.handle(event) }
                }
            }.value

            phase = .working("Starting WebDriverAgent on the iPhone…")
            try startTunnels(udid: device.udid)
            try runner.launch(udid: device.udid) { event in
                Task { @MainActor in self.handle(event) }
            }
            try await waitForWDA()
            screenSize = try await client.screenSize()
            await startVideo(device: device)
            phase = .connected
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func findDevice() async throws -> UsbmuxDevice {
        for _ in 0..<60 {
            try Task.checkCancellation()
            let devices = (try? UsbmuxClient().listDevices()) ?? []
            if let device = devices.first(where: { $0.connectionType == "USB" }) ?? devices.first { return device }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw MirrorError.noDevice
    }

    private func startTunnels(udid: String) throws {
        forwarders = try [
            PortForwarder(udid: udid, localPort: Self.localWDAPort, remotePort: Self.wdaPort),
            PortForwarder(udid: udid, localPort: Self.localMJPEGPort, remotePort: Self.mjpegPort),
        ]
        forwarders.forEach { $0.start() }
    }

    private func waitForWDA() async throws {
        for _ in 0..<180 {
            try Task.checkCancellation()
            if await client.isReady() { return }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw MirrorError.wdaTimeout
    }

    /// Prefers the 60 fps USB capture device; falls back to WebDriverAgent's MJPEG stream (Wi-Fi, errors).
    private func startVideo(device: UsbmuxDevice) async {
        if device.connectionType == "USB" {
            phase = .working("Starting video…")
            let capture = ScreenCapture()
            do {
                capture.onFPS = { [weak self] fps in self?.framesPerSecond = fps }
                try await capture.start(udid: device.udid)
                self.capture = capture
                captureSession = capture.session
                videoSource = .usbCapture
                return
            } catch {
                NSLog("OpenMirror: USB capture unavailable, using MJPEG: \(error.localizedDescription)")
            }
        }
        videoSource = .mjpeg
        startStream()
    }

    private func startStream() {
        stream?.stop()
        let url = URL(string: "http://127.0.0.1:\(Self.localMJPEGPort)")!
        stream = MJPEGStream(url: url, onFrame: { [weak self] image in
            self?.frame = image
        }, onDisconnect: { [weak self] in
            Task { @MainActor in
                guard let self, self.phase == .connected else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if self.phase == .connected { self.startStream() }
            }
        })
        stream?.onFPS = { [weak self] fps in self?.framesPerSecond = fps }
        stream?.start()
    }

    private func handle(_ event: WDARunner.Event) {
        switch event {
        case .progress(let message): phase = .working(message)
        case .needsUnlock: if phase != .connected { phase = .needsUnlock }
        case .serverStarted: if phase == .needsUnlock { phase = .working("Connecting…") }
        case .failed(let message): phase = .failed(message)
        }
    }

    // MARK: - Input

    func perform(_ gesture: PhoneGesture) {
        send { client in
            switch gesture {
            case let .tap(x, y): try await client.tap(x: x, y: y)
            case let .hold(x, y, seconds): try await client.touchAndHold(x: x, y: y, seconds: seconds)
            case let .drag(fx, fy, tx, ty, press):
                try await client.drag(fromX: fx, fromY: fy, toX: tx, toY: ty, pressSeconds: press)
            }
        }
    }

    /// Sends text to the phone in one event. Every WDA text event makes iOS treat it as a hardware
    /// keyboard and briefly hide the on-screen one, so text is composed on the Mac and sent at once.
    func type(_ text: String) { send { try await $0.type(text) } }

    /// Key presses from the mirrored screen: printable text opens the compose field,
    /// Backspace / Return with nothing composed go straight to the phone.
    func handleKey(_ text: String) {
        if !isComposing, text == "\u{8}" || text == "\n" || text == "\t" {
            type(text)
            return
        }
        composeText += text
        isComposing = true
    }

    func sendComposed() {
        let text = composeText
        composeText = ""
        isComposing = false
        type(text.isEmpty ? "\n" : text)
    }

    func cancelComposing() {
        composeText = ""
        isComposing = false
    }
    func press(_ button: HardwareButton) { send { try await $0.press(button) } }
    func lock() { send { try await $0.lock() } }
    func openAppSwitcher() { perform(GestureMapper.appSwitcher(in: screenSize)) }

    func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        type(String(text.prefix(2_000)))
    }

    /// Runs phone commands strictly one after another (keeps taps and text in order).
    private func send(_ action: @escaping (WDAClient) async throws -> Void) {
        guard phase == .connected else { return }
        let client = self.client
        let previous = commandChain
        commandChain = Task {
            await previous?.value
            do { try await action(client) } catch {
                NSLog("OpenMirror: action failed: \(error.localizedDescription)")
            }
        }
    }
}

enum MirrorError: LocalizedError {
    case noDevice
    case wdaTimeout

    var errorDescription: String? {
        switch self {
        case .noDevice: return "No iPhone found. Connect it with a cable, unlock it and tap “Trust” on the phone."
        case .wdaTimeout: return "WebDriverAgent did not respond. Unlock the iPhone and click Reconnect."
        }
    }
}
