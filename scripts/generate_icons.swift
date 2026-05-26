#!/usr/bin/env swift
import AppKit

// Regenerates all icon assets from the canonical waveform design.
// Usage: swift scripts/generate_icons.swift Assets/

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try! png.write(to: URL(fileURLWithPath: path))
    print("Saved: \(path)")
}

let waveformHeights: [CGFloat] = [
    0.28, 0.58, 0.90, 0.52, 0.32
]

let waveformOffsets: [CGFloat] = [
    0.0, -0.02, 0.0, 0.04, 0.0
]

func drawWaveformBars(in rect: NSRect, scale s: CGFloat, color: NSColor) {
    let totalBars = waveformHeights.count
    let barWidth: CGFloat = 10.0 * s
    let barSpacing: CGFloat = 10.0 * s
    let totalWidth = CGFloat(totalBars) * barWidth + CGFloat(totalBars - 1) * barSpacing
    let startX = rect.midX - totalWidth / 2.0
    let centerY = rect.midY

    for i in 0..<totalBars {
        let x = startX + CGFloat(i) * (barWidth + barSpacing)
        let h = waveformHeights[i] * rect.height * 0.55
        let yOffset = waveformOffsets[i] * rect.height
        let barRect = NSRect(x: x, y: centerY - h / 2 + yOffset, width: barWidth, height: h)
        let bar = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        let distFromCenter = abs(CGFloat(i) - CGFloat(totalBars - 1) / 2.0) / (CGFloat(totalBars - 1) / 2.0)
        let alpha = 1.0 - distFromCenter * 0.35
        color.withAlphaComponent(alpha).setFill()
        bar.fill()
    }
}

func appIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let s = size / 128.0
        let cornerRadius = 22 * s
        let bg = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSGradient(
            starting: NSColor(red: 0.192, green: 0.192, blue: 0.192, alpha: 1.0),
            ending: NSColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)
        )?.draw(in: bg, angle: -90)
        drawWaveformBars(in: rect, scale: s, color: .white)
        return true
    }
}

func menuBarIcon(pointSize: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
        let s = pointSize / 90.0
        drawWaveformBars(in: rect, scale: s, color: .black)
        return true
    }
    image.isTemplate = true
    return image
}

let baseDir = CommandLine.arguments[1]
savePNG(appIcon(size: 1024), to: "\(baseDir)/AppIcon-1024x1024.png")

let iconsetDir = "\(baseDir)/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
for (name, px): (String, CGFloat) in [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
] { savePNG(appIcon(size: px), to: "\(iconsetDir)/\(name)") }

savePNG(menuBarIcon(pointSize: 18), to: "\(baseDir)/menubar-icon.png")
savePNG(menuBarIcon(pointSize: 36), to: "\(baseDir)/menubar-icon@2x.png")
savePNG(menuBarIcon(pointSize: 128), to: "\(baseDir)/menubar-icon-preview.png")

print("\nDone. Now run:")
print("  iconutil --convert icns --output \(baseDir)/AppIcon.icns \(iconsetDir)/")
print("  cp \(baseDir)/menubar-icon.png Sources/Hush/Resources/")
print("  cp \(baseDir)/menubar-icon@2x.png Sources/Hush/Resources/")
print("  rm -rf \(iconsetDir)")
