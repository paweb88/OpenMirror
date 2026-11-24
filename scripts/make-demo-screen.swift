// Draws a neutral, data-free phone home screen used for README screenshots (demo mode).
// Usage: swift scripts/make-demo-screen.swift <output.png>
import AppKit

let size = NSSize(width: 1320, height: 2868)  // 440×956 pt @3x
let image = NSImage(size: size)
image.lockFocus()

// wallpaper
NSGradient(colors: [NSColor(red: 0.16, green: 0.20, blue: 0.45, alpha: 1),
                    NSColor(red: 0.42, green: 0.22, blue: 0.62, alpha: 1),
                    NSColor(red: 0.95, green: 0.52, blue: 0.45, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: -70)

func text(_ string: String, at point: NSPoint, size fontSize: CGFloat, weight: NSFont.Weight, center: Bool = false) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: NSColor.white]
    let str = NSAttributedString(string: string, attributes: attributes)
    let x = center ? point.x - str.size().width / 2 : point.x
    str.draw(at: NSPoint(x: x, y: point.y))
}

// status bar + dynamic island
text("9:41", at: NSPoint(x: 150, y: size.height - 150), size: 52, weight: .semibold)
NSColor.black.setFill()
NSBezierPath(roundedRect: NSRect(x: 470, y: size.height - 170, width: 380, height: 112), xRadius: 56, yRadius: 56).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 1080, y: size.height - 132, width: 90, height: 42), xRadius: 12, yRadius: 12).fill()

struct App { let name: String; let symbol: String; let color: NSColor }
let apps: [App] = [
    App(name: "Notes", symbol: "note.text", color: .systemYellow),
    App(name: "Music", symbol: "music.note", color: .systemPink),
    App(name: "Weather", symbol: "cloud.sun.fill", color: .systemBlue),
    App(name: "Clock", symbol: "clock.fill", color: .darkGray),
    App(name: "Calendar", symbol: "calendar", color: .systemRed),
    App(name: "Maps", symbol: "map.fill", color: .systemGreen),
    App(name: "Files", symbol: "folder.fill", color: .systemIndigo),
    App(name: "Podcasts", symbol: "mic.fill", color: .systemPurple),
    App(name: "Books", symbol: "book.fill", color: .systemOrange),
    App(name: "Fitness", symbol: "figure.run", color: .systemTeal),
    App(name: "Calculator", symbol: "plus.forwardslash.minus", color: .systemGray),
    App(name: "Shortcuts", symbol: "square.stack.3d.up.fill", color: .systemCyan),
    App(name: "Home", symbol: "house.fill", color: .systemOrange),
    App(name: "Translate", symbol: "character.bubble.fill", color: .systemBlue),
    App(name: "Tips", symbol: "lightbulb.fill", color: .systemYellow),
    App(name: "Settings", symbol: "gearshape.fill", color: .gray),
]
let dock: [App] = [
    App(name: "", symbol: "phone.fill", color: .systemGreen),
    App(name: "", symbol: "message.fill", color: .systemGreen),
    App(name: "", symbol: "globe", color: .systemBlue),
    App(name: "", symbol: "camera.fill", color: .darkGray),
]

func icon(_ app: App, at origin: NSPoint) {
    let rect = NSRect(x: origin.x, y: origin.y, width: 192, height: 192)
    let path = NSBezierPath(roundedRect: rect, xRadius: 44, yRadius: 44)
    NSGradient(colors: [app.color.blended(withFraction: 0.25, of: .white)!, app.color])!.draw(in: path, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: 88, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: app.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
    }
    if !app.name.isEmpty { text(app.name, at: NSPoint(x: rect.midX, y: rect.minY - 52), size: 34, weight: .medium, center: true) }
}

let columns: [CGFloat] = [100, 412, 724, 1036]
for (index, app) in apps.enumerated() {
    let row = CGFloat(index / 4)
    icon(app, at: NSPoint(x: columns[index % 4], y: size.height - 520 - row * 330))
}

// search pill
NSColor.white.withAlphaComponent(0.22).setFill()
NSBezierPath(roundedRect: NSRect(x: 560, y: 470, width: 200, height: 66), xRadius: 33, yRadius: 33).fill()
text("Search", at: NSPoint(x: 660, y: 484), size: 32, weight: .medium, center: true)

// dock
NSColor.white.withAlphaComponent(0.25).setFill()
NSBezierPath(roundedRect: NSRect(x: 50, y: 60, width: 1220, height: 330), xRadius: 110, yRadius: 110).fill()
for (index, app) in dock.enumerated() { icon(app, at: NSPoint(x: columns[index], y: 130)) }

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let output = CommandLine.arguments.dropFirst().first ?? "demo-screen.png"
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
