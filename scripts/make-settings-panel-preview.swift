import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift scripts/make-settings-panel-preview.swift IMAGE.jpg OUTPUT.png\n", stderr)
    exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let painting = NSImage(contentsOf: imageURL) else {
    fputs("Cannot read \(imageURL.path)\n", stderr)
    exit(1)
}

let size = NSSize(width: 1600, height: 1500)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let background = NSRect(origin: .zero, size: size)
NSColor.white.setFill()
background.fill()

func text(_ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor = .labelColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    NSAttributedString(string: string, attributes: attributes).draw(at: point)
}

text("Starry Night", at: NSPoint(x: 64, y: 1432), size: 24, weight: .bold)
text("Let the sky flow", at: NSPoint(x: 64, y: 1338), size: 40, weight: .bold)
text("The sky moves along the brushstrokes. The cypress, hills, and village stay still.", at: NSPoint(x: 64, y: 1286), size: 19, weight: .regular, color: .secondaryLabelColor)

let imageRect = NSRect(x: 64, y: 430, width: 1472, height: 810)
let sourceSize = painting.size
let scale = max(imageRect.width / sourceSize.width, imageRect.height / sourceSize.height)
let scaled = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
let drawRect = NSRect(
    x: imageRect.midX - scaled.width / 2,
    y: imageRect.midY - scaled.height / 2,
    width: scaled.width,
    height: scaled.height
)
NSGraphicsContext.current!.cgContext.saveGState()
NSGraphicsContext.current!.cgContext.clip(to: imageRect)
painting.draw(in: drawRect)
NSGraphicsContext.current!.cgContext.restoreGState()

func slider(x: CGFloat, label: String, value: String, knobFraction: CGFloat) {
    text(label, at: NSPoint(x: x, y: 348), size: 22, weight: .semibold)
    text(value, at: NSPoint(x: x + 160, y: 348), size: 22, weight: .regular)
    let track = NSRect(x: x, y: 314, width: 360, height: 10)
    NSColor.systemGray.withAlphaComponent(0.28).setFill()
    NSBezierPath(roundedRect: track, xRadius: 5, yRadius: 5).fill()
    let active = NSRect(x: x, y: 314, width: 360 * knobFraction, height: 10)
    NSColor.systemBlue.setFill()
    NSBezierPath(roundedRect: active, xRadius: 5, yRadius: 5).fill()
    let knob = NSRect(x: x + 360 * knobFraction - 16, y: 303, width: 32, height: 32)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: knob).fill()
    NSColor.systemGray.withAlphaComponent(0.2).setStroke()
    NSBezierPath(ovalIn: knob).stroke()
}

slider(x: 64, label: "Speed", value: "1.13×", knobFraction: 0.5)
slider(x: 504, label: "Amplitude", value: "100%", knobFraction: 0.4)

func button(_ title: String, x: CGFloat, width: CGFloat) {
    let rect = NSRect(x: x, y: 210, width: width, height: 56)
    NSColor.systemGray.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
    text(title, at: NSPoint(x: x + 20, y: 227), size: 18, weight: .semibold)
}

button("Apply to wallpaper and lock screen", x: 64, width: 350)
button("Open Wallpaper Settings", x: 434, width: 290)
button("Export loop video", x: 744, width: 230)
text("Wallpaper enabled. It restores after you sign in and keeps playing when the panel closes.", at: NSPoint(x: 64, y: 128), size: 17, weight: .regular, color: .secondaryLabelColor)

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Cannot encode PNG\n", stderr)
    exit(1)
}
try png.write(to: outputURL)
