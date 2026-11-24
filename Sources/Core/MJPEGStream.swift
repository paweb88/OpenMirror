import AppKit
import Foundation

/// Splits a byte stream into complete JPEG frames by scanning for SOI (FFD8) / EOI (FFD9) markers.
struct MJPEGParser {
    private var buffer = Data()
    private static let maxBuffer = 8_000_000

    /// Appends bytes and returns the newest complete frame, if any (older frames are dropped).
    mutating func append(_ chunk: Data) -> Data? {
        buffer.append(chunk)
        var latest: Data?
        while let start = Self.find([0xFF, 0xD8], in: buffer, from: buffer.startIndex),
              let end = Self.find([0xFF, 0xD9], in: buffer, from: start + 2) {
            latest = buffer.subdata(in: start..<(end + 2))
            buffer = buffer.subdata(in: (end + 2)..<buffer.endIndex)
        }
        if buffer.count > Self.maxBuffer { buffer.removeAll() }
        return latest
    }

    private static func find(_ marker: [UInt8], in data: Data, from index: Data.Index) -> Data.Index? {
        guard index < data.endIndex else { return nil }
        return data.range(of: Data(marker), in: index..<data.endIndex)?.lowerBound
    }
}

/// Reads WebDriverAgent's MJPEG server and publishes frames as NSImage.
final class MJPEGStream: NSObject, URLSessionDataDelegate {
    private let url: URL
    private let onFrame: (NSImage) -> Void
    private let onDisconnect: () -> Void
    private var parser = MJPEGParser()
    private var session: URLSession?

    init(url: URL, onFrame: @escaping (NSImage) -> Void, onDisconnect: @escaping () -> Void) {
        self.url = url
        self.onFrame = onFrame
        self.onDisconnect = onDisconnect
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = .infinity
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session?.dataTask(with: url).resume()
    }

    func stop() {
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let frame = parser.append(data), let image = NSImage(data: frame) else { return }
        DispatchQueue.main.async { self.onFrame(image) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard session === self.session else { return }
        DispatchQueue.main.async { self.onDisconnect() }
    }
}
