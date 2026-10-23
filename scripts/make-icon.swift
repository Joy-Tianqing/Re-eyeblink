import AppKit
import Foundation

// Resize the approved artwork without redrawing it; preserve its transparent background.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/make-icon.swift <output.iconset>")
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("packaging/Eyeblink.png")
guard let image = NSImage(contentsOf: source) else {
    fatalError("Cannot read icon artwork: \(source.path)")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func png(_ size: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero, operation: .copy, fraction: 1)
    return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try png(size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
