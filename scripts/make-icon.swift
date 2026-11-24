// Renders the OpenMirror app icon (1024×1024) and the macOS AppIcon set.
// Usage: swift scripts/make-icon.swift <output.appiconset>
import AppKit

let canvas: CGFloat = 1024

func render() -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    defer { image.unlockFocus() }

    // macOS icon grid: 824pt rounded square centred in 1024 canvas
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.29, green: 0.40, blue: 1.00, alpha: 1),
                        NSColor(red: 0.55, green: 0.24, blue: 0.93, alpha: 1)])!
        .draw(in: tilePath, angle: -60)

    // back phone (the "reflection"), slightly offset and translucent
    func phone(_ rect: NSRect, fill: NSColor, stroke: NSColor?) {
        let body = NSBezierPath(roundedRect: rect, xRadius: 62, yRadius: 62)
        fill.setFill()
        body.fill()
        if let stroke {
            stroke.setStroke()
            body.lineWidth = 14
            body.stroke()
        }
    }
    phone(NSRect(x: 450, y: 270, width: 300, height: 520), fill: NSColor.white.withAlphaComponent(0.22), stroke: nil)
    phone(NSRect(x: 290, y: 230, width: 300, height: 520), fill: NSColor(white: 0.08, alpha: 1),
          stroke: NSColor.white.withAlphaComponent(0.95))

    // screen glow on the front phone
    let screen = NSBezierPath(roundedRect: NSRect(x: 318, y: 258, width: 244, height: 464), xRadius: 40, yRadius: 40)
    NSGradient(colors: [NSColor(red: 0.42, green: 0.80, blue: 1.0, alpha: 1),
                        NSColor(red: 0.35, green: 0.45, blue: 1.0, alpha: 1)])!.draw(in: screen, angle: -90)

    // dynamic island
    NSColor(white: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 400, y: 680, width: 80, height: 22), xRadius: 11, yRadius: 11).fill()

    // mirror arrows between the phones
    let arrow = NSBezierPath()
    arrow.lineWidth = 22
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 640, y: 560)); arrow.line(to: NSPoint(x: 720, y: 490)); arrow.line(to: NSPoint(x: 640, y: 420))
    NSColor.white.setStroke()
    arrow.stroke()
    return image
}

func writePNG(_ image: NSImage, size: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let icon = render()
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try writePNG(icon, size: points * scale, to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
try writePNG(icon, size: 1024, to: output.deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("icon-1024.png"))
print("Icon written to \(output.path)")
