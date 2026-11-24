import AVFoundation
import CoreMediaIO
import Foundation

/// Captures the iPhone screen (up to 60 fps) and sound over USB through the screen-capture device that
/// macOS exposes for connected iPhones – the same public AVFoundation path QuickTime uses.
final class ScreenCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case deviceNotFound
        case cannotAddInput

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Camera access is off for OpenMirror (System Settings → Privacy & Security → Camera)."
            case .deviceNotFound: return "The iPhone's screen-capture device did not appear."
            case .cannotAddInput: return "Could not start screen capture."
            }
        }
    }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "openmirror.capture")
    private let frameQueue = DispatchQueue(label: "openmirror.capture.frames")
    private var frameCount = 0
    private var windowStart = Date()
    private(set) var measuredFPS: Double = 0
    var onFPS: ((Double) -> Void)?

    /// Lets iOS devices show up as AVCapture devices (off by default on macOS).
    static func enableScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
                                  UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    /// iPhone capture devices use the UDID (sometimes without dashes) as uniqueID.
    static func matches(uniqueID: String, udid: String) -> Bool {
        func normalized(_ value: String) -> String { value.replacingOccurrences(of: "-", with: "").uppercased() }
        return normalized(uniqueID) == normalized(udid)
    }

    static let iOSModelID = "iOS Device"

    /// Picks the capture device for the phone: exact UDID match first; macOS usually assigns its own UUID,
    /// so otherwise the only "iOS Device" (or the first one when several iPhones are connected).
    static func chooseDevice(_ candidates: [(uniqueID: String, modelID: String)], udid: String) -> Int? {
        if let exact = candidates.firstIndex(where: { matches(uniqueID: $0.uniqueID, udid: udid) }) { return exact }
        return candidates.firstIndex { $0.modelID == iOSModelID }
    }

    static func findDevice(udid: String) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified).devices
        let index = chooseDevice(devices.map { ($0.uniqueID, $0.modelID) }, udid: udid)
        return index.map { devices[$0] }
    }

    /// Waits for the device (it appears a few seconds after enabling), then starts capturing.
    func start(udid: String, timeout: TimeInterval = 8) async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw CaptureError.permissionDenied }
        Self.enableScreenCaptureDevices()
        let deadline = Date().addingTimeInterval(timeout)
        var device = Self.findDevice(udid: udid)
        while device == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 500_000_000)
            device = Self.findDevice(udid: udid)
        }
        guard let device else { throw CaptureError.deviceNotFound }
        // Configure and start on one serial queue and only return once running, so nothing
        // (e.g. a preview layer) touches the session while AVFoundation is still setting it up.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configure(with: device)
                    self.session.startRunning()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { self.session.stopRunning() }
    }

    private func configure(with device: AVCaptureDevice) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        // phone sound → Mac speakers
        let audio = AVCaptureAudioPreviewOutput()
        audio.volume = 1
        if session.canAddOutput(audio) { session.addOutput(audio) }

        // frame counter only (the picture itself is drawn by AVCaptureVideoPreviewLayer)
        let counter = AVCaptureVideoDataOutput()
        counter.alwaysDiscardsLateVideoFrames = true
        counter.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(counter) { session.addOutput(counter) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        let elapsed = Date().timeIntervalSince(windowStart)
        guard elapsed >= 2 else { return }
        measuredFPS = Double(frameCount) / elapsed
        frameCount = 0
        windowStart = Date()
        NSLog("OpenMirror: capture %.1f fps", measuredFPS)
        let fps = measuredFPS
        DispatchQueue.main.async { self.onFPS?(fps) }
    }
}
