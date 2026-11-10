// Draws the Natkeys app icon and writes an .iconset folder.
// Usage: swiftc scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon Resources/AppIcon.iconset
//        iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Background squircle with a deep blue → violet gradient.
    let inset = 100 * s
    let bgRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.27, blue: 0.62, alpha: 1),
        NSColor(calibratedRed: 0.42, green: 0.24, blue: 0.70, alpha: 1),
    ])!.draw(in: bg, angle: -60)

    // A keycap.
    let capRect = NSRect(x: 250 * s, y: 330 * s, width: 524 * s, height: 420 * s)
    let shadow = NSBezierPath(roundedRect: capRect.offsetBy(dx: 0, dy: -22 * s), xRadius: 70 * s, yRadius: 70 * s)
    NSColor(calibratedWhite: 0, alpha: 0.25).setFill()
    shadow.fill()
    let cap = NSBezierPath(roundedRect: capRect, xRadius: 70 * s, yRadius: 70 * s)
    NSGradient(colors: [NSColor(calibratedWhite: 1, alpha: 1), NSColor(calibratedWhite: 0.9, alpha: 1)])!
        .draw(in: cap, angle: -90)

    // The Option symbol on the keycap.
    let glyph = "⌥" as NSString
    let font = NSFont.systemFont(ofSize: 300 * s, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.62, alpha: 1),
    ]
    let glyphSize = glyph.size(withAttributes: attributes)
    glyph.draw(
        at: NSPoint(x: capRect.midX - glyphSize.width / 2, y: capRect.midY - glyphSize.height / 2 + 6 * s),
        withAttributes: attributes
    )

    // A spacebar underneath.
    let barRect = NSRect(x: 250 * s, y: 190 * s, width: 524 * s, height: 90 * s)
    NSColor(calibratedWhite: 1, alpha: 0.85).setFill()
    NSBezierPath(roundedRect: barRect, xRadius: 40 * s, yRadius: 40 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes {
    let data = drawIcon(size: size).representation(using: .png, properties: [:])!
    try! data.write(to: output.appendingPathComponent("\(name).png"))
}
print("Wrote \(output.path)")
