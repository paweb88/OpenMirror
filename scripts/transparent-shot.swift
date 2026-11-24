// Makes the white backdrop around a window capture transparent (flood fill from the edges).
// Usage: swift scripts/transparent-shot.swift <input.jpg|png> <output.png> [threshold 0-255]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let source = NSImage(contentsOfFile: args[1]),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("usage: transparent-shot <input> <output.png> [threshold]\n", stderr)
    exit(1)
}
let threshold = UInt8(args.count > 3 ? Int(args[3]) ?? 238 : 238)
let width = cg.width, height = cg.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

func isBackdrop(_ i: Int) -> Bool {
    pixels[i] >= threshold && pixels[i + 1] >= threshold && pixels[i + 2] >= threshold && pixels[i + 3] > 0
}

var stack: [Int] = []
for x in 0..<width { stack.append(x); stack.append((height - 1) * width + x) }
for y in 0..<height { stack.append(y * width); stack.append(y * width + width - 1) }
while let p = stack.popLast() {
    let i = p * 4
    guard isBackdrop(i) else { continue }
    pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
    let x = p % width, y = p / width
    if x > 0 { stack.append(p - 1) }
    if x < width - 1 { stack.append(p + 1) }
    if y > 0 { stack.append(p - width) }
    if y < height - 1 { stack.append(p + width) }
}

// crop to the visible content
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height { for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let full = context.makeImage()!
let output = full.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? full
let rep = NSBitmapImageRep(cgImage: output)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) (\(width)×\(height))")
