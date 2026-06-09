#!/usr/bin/env swift
// Generates a 1024x1024 opaque PNG placeholder app icon (receipt + red seal "計").
// Run from repo root: swift tools/generate_app_icon.swift
import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 3,
    hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.50, alpha: 1),
    NSColor(calibratedRed: 0.00, green: 0.70, blue: 0.67, alpha: 1),
])!
gradient.draw(in: bounds, angle: -45)

NSColor.white.withAlphaComponent(0.96).setFill()
NSBezierPath(roundedRect: NSRect(x: 312, y: 196, width: 400, height: 620), xRadius: 52, yRadius: 52).fill()

NSColor(calibratedWhite: 0.72, alpha: 1).setFill()
for (index, width) in [160, 280, 320, 240, 220].enumerated() {
    NSBezierPath(
        roundedRect: NSRect(x: 372, y: 700 - index * 72, width: width, height: 22),
        xRadius: 11,
        yRadius: 11
    ).fill()
}

NSColor(calibratedRed: 0.86, green: 0.10, blue: 0.08, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 552, y: 272, width: 168, height: 168)).fill()
let seal = NSAttributedString(string: "計", attributes: [
    .font: NSFont.boldSystemFont(ofSize: 104),
    .foregroundColor: NSColor.white,
])
let sealSize = seal.size()
seal.draw(at: NSPoint(x: 636 - sealSize.width / 2, y: 356 - sealSize.height / 2))

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
let out = URL(fileURLWithPath: "SnapKei/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
try png.write(to: out)
print("Wrote \(out.path) (\(png.count) bytes)")
