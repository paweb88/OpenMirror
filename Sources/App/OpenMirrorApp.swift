import SwiftUI

@main
struct OpenMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MirrorModel()

    var body: some Scene {
        WindowGroup("OpenMirror") {
            ContentView()
                .environmentObject(model)
                .onAppear { appDelegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(DeviceMetrics.windowSize(screenWidth: 360, screen: ScreenSize(width: 440, height: 956)))
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("iPhone") {
                Button("Home") { model.press(.home) }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("App Switcher") { model.openAppSwitcher() }.keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Lock") { model.lock() }
                Divider()
                Toggle("Keep on Top", isOn: $model.keepOnTop).keyboardShortcut("t", modifiers: [.command, .shift])
                Toggle("Show Frame Rate", isOn: $model.showFrameRate).keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("Reconnect") { model.connect() }.keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: MirrorModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.disconnect() }
    }
}
