import Foundation

/// Fetches, builds (signed with the user's team) and launches WebDriverAgent on the iPhone via xcodebuild.
final class WDARunner {
    static let wdaRepository = "https://github.com/appium/WebDriverAgent.git"
    static let wdaVersion = "v16.15.3"

    enum Event {
        case progress(String)
        case needsUnlock
        case serverStarted
        case failed(String)
    }

    private let supportDirectory: URL
    private var runningProcess: Process?
    private let logURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDirectory = base.appendingPathComponent("OpenMirror", isDirectory: true)
        logURL = supportDirectory.appendingPathComponent("wda.log")
        try? fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    var logFile: URL { logURL }
    private var sourceDirectory: URL { supportDirectory.appendingPathComponent("WebDriverAgent-\(Self.wdaVersion)") }
    private var derivedData: URL { supportDirectory.appendingPathComponent("DerivedData") }
    private var buildStamp: URL { supportDirectory.appendingPathComponent("build-stamp") }

    static func bundleID(teamID: String) -> String { "io.github.openmirror.wda.\(teamID.lowercased())" }

    /// Clones and builds WDA if needed. Blocking – call from a background task.
    func prepare(teamID: String, udid: String, report: (Event) -> Void) throws {
        if !FileManager.default.fileExists(atPath: sourceDirectory.path) {
            report(.progress("Downloading WebDriverAgent \(Self.wdaVersion)…"))
            try run("/usr/bin/git", ["clone", "--depth", "1", "--branch", Self.wdaVersion,
                                    Self.wdaRepository, sourceDirectory.path])
        }
        let stamp = "\(Self.wdaVersion)|\(teamID)"
        if (try? String(contentsOf: buildStamp, encoding: .utf8)) == stamp, xctestrunFile() != nil { return }

        report(.progress("Building WebDriverAgent for your iPhone (first run, ~1–2 min)…"))
        try run("/usr/bin/xcodebuild", [
            "build-for-testing",
            "-project", sourceDirectory.appendingPathComponent("WebDriverAgent.xcodeproj").path,
            "-scheme", "WebDriverAgentRunner",
            "-destination", "id=\(udid)",
            "-derivedDataPath", derivedData.path,
            "-allowProvisioningUpdates",
            "DEVELOPMENT_TEAM=\(teamID)", "CODE_SIGN_STYLE=Automatic",
            "PRODUCT_BUNDLE_IDENTIFIER=\(Self.bundleID(teamID: teamID))",
        ])
        try stamp.write(to: buildStamp, atomically: true, encoding: .utf8)
    }

    /// Starts the WDA test session; events arrive on a background queue until it stops.
    func launch(udid: String, onEvent: @escaping (Event) -> Void) throws {
        guard let xctestrun = xctestrunFile() else { throw RunnerError.missingBuild }
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["test-without-building", "-xctestrun", xctestrun.path, "-destination", "id=\(udid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)

        var reportedStart = false
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            log.write(data)
            let text = String(decoding: data, as: UTF8.self)
            if let event = WDALogInterpreter.event(for: text) {
                if case .serverStarted = event { reportedStart = true }
                onEvent(event)
            }
        }
        process.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            try? log.close()
            if finished.terminationReason != .uncaughtSignal {
                onEvent(.failed(reportedStart ? "WebDriverAgent stopped. Click Reconnect."
                                              : "WebDriverAgent could not start. See the log for details."))
            }
        }
        try process.run()
        runningProcess = process
    }

    func stop() {
        runningProcess?.terminate()
        runningProcess = nil
    }

    private func xctestrunFile() -> URL? {
        let products = derivedData.appendingPathComponent("Build/Products")
        let files = (try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.pathExtension == "xctestrun" }
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try? data.write(to: supportDirectory.appendingPathComponent("build.log"))
        guard process.terminationStatus == 0 else {
            throw RunnerError.commandFailed(WDALogInterpreter.buildFailureHint(String(decoding: data, as: UTF8.self)))
        }
    }

    enum RunnerError: LocalizedError {
        case missingBuild
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingBuild: return "WebDriverAgent is not built yet."
            case .commandFailed(let hint): return hint
            }
        }
    }
}

/// Turns xcodebuild output into user-facing events and hints.
enum WDALogInterpreter {
    static func event(for text: String) -> WDARunner.Event? {
        if text.contains("ServerURLHere") { return .serverStarted }
        if text.contains("is locked") || text.contains("Unlock ") { return .needsUnlock }
        if text.contains("Developer Mode") && text.contains("disabled") {
            return .failed("Turn on Developer Mode: Settings → Privacy & Security → Developer Mode.")
        }
        if text.contains("invalid code signature") || text.contains("not been explicitly trusted")
            || text.contains("Untrusted Developer") {
            return .failed("Trust the developer on the iPhone: Settings → General → VPN & Device Management.")
        }
        return nil
    }

    static func buildFailureHint(_ log: String) -> String {
        if log.contains("No Account for Team") || log.contains("No signing certificate") {
            return "Xcode has no account for this team. Open Xcode → Settings → Accounts and sign in."
        }
        if log.contains("is not available") || log.contains("Unable to find a destination") {
            return "Xcode cannot see the iPhone. Connect it by cable, unlock it and trust this Mac."
        }
        if log.contains("Developer Mode") {
            return "Turn on Developer Mode: Settings → Privacy & Security → Developer Mode."
        }
        let lastError = log.split(separator: "\n").last { $0.contains("error:") }
        return "Build failed: \(lastError.map(String.init) ?? "see build.log in ~/Library/Application Support/OpenMirror")"
    }
}
