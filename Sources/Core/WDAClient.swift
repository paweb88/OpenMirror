import Foundation

struct ScreenSize: Equatable {
    let width: Double
    let height: Double
}

enum HardwareButton: String {
    case home, volumeUp, volumeDown
}

enum WDAError: LocalizedError {
    case badResponse(Int, String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code, let body): return "WebDriverAgent HTTP \(code): \(body.prefix(200))"
        }
    }
}

/// Thin async client for the WebDriverAgent REST API.
actor WDAClient {
    static let streamSettings: [String: Any] = [
        "mjpegServerFramerate": 30, "mjpegScalingFactor": 50, "mjpegServerScreenshotQuality": 60,
    ]

    private let baseURL: URL
    private var sessionID: String?

    init(baseURL: URL) { self.baseURL = baseURL }

    func isReady() async -> Bool {
        (try? await call("GET", "/status", nil)) != nil
    }

    func screenSize() async throws -> ScreenSize {
        let value = try await inSession("GET", "/window/size", nil)["value"] as? [String: Any] ?? [:]
        return ScreenSize(width: value["width"] as? Double ?? 0, height: value["height"] as? Double ?? 0)
    }

    func tap(x: Double, y: Double) async throws {
        _ = try await inSession("POST", "/wda/tap", ["x": x, "y": y])
    }

    func touchAndHold(x: Double, y: Double, seconds: Double) async throws {
        _ = try await inSession("POST", "/wda/touchAndHold", ["x": x, "y": y, "duration": seconds])
    }

    func drag(fromX: Double, fromY: Double, toX: Double, toY: Double, pressSeconds: Double) async throws {
        _ = try await inSession("POST", "/wda/dragfromtoforduration", [
            "fromX": fromX, "fromY": fromY, "toX": toX, "toY": toY, "duration": pressSeconds,
        ])
    }

    func type(_ text: String) async throws {
        guard !text.isEmpty else { return }
        _ = try await inSession("POST", "/wda/keys", ["value": text.map(String.init)])
    }

    func press(_ button: HardwareButton) async throws {
        if button == .home {
            _ = try await call("POST", "/wda/homescreen", [:])
        } else {
            _ = try await inSession("POST", "/wda/pressButton", ["name": button.rawValue])
        }
    }

    func lock() async throws {
        _ = try await call("POST", "/wda/lock", [:])
    }

    // MARK: - Plumbing

    private func ensureSession() async throws -> String {
        if let sessionID { return sessionID }
        let created = try await call("POST", "/session", ["capabilities": [:]])
        let id = created["sessionId"] as? String
            ?? (created["value"] as? [String: Any])?["sessionId"] as? String ?? ""
        sessionID = id
        _ = try await call("POST", "/session/\(id)/appium/settings", ["settings": Self.streamSettings])
        return id
    }

    private func inSession(_ method: String, _ path: String, _ body: [String: Any]?) async throws -> [String: Any] {
        do {
            return try await call(method, "/session/\(try await ensureSession())\(path)", body)
        } catch WDAError.badResponse(404, _) {
            sessionID = nil  // WDA restarted; open a fresh session once
            return try await call(method, "/session/\(try await ensureSession())\(path)", body)
        }
    }

    private func call(_ method: String, _ path: String, _ body: [String: Any]?) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw WDAError.badResponse(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
