#!/usr/bin/env swift
// Native vector artwork. Run from the repository root, then use iconutil below.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Dreadline/Resources")
let iconset = root.appendingPathComponent("build/Ghost.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Coordinates use a 24-point, top-left-origin canvas.
func ghost(_ color: NSColor, width: CGFloat) {
    color.setStroke()
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 5, y: 20))
    p.line(to: NSPoint(x: 5, y: 10))
    p.curve(to: NSPoint(x: 12, y: 3), controlPoint1: NSPoint(x: 5, y: 6.13), controlPoint2: NSPoint(x: 8.13, y: 3))
    p.curve(to: NSPoint(x: 19, y: 10), controlPoint1: NSPoint(x: 15.87, y: 3), controlPoint2: NSPoint(x: 19, y: 6.13))
    p.line(to: NSPoint(x: 19, y: 20))
    p.curve(to: NSPoint(x: 15.5, y: 18), controlPoint1: NSPoint(x: 17.8, y: 20), controlPoint2: NSPoint(x: 17, y: 18))
    p.curve(to: NSPoint(x: 12, y: 20), controlPoint1: NSPoint(x: 14, y: 18), controlPoint2: NSPoint(x: 13.5, y: 20))
    p.curve(to: NSPoint(x: 8.5, y: 18), controlPoint1: NSPoint(x: 10.5, y: 20), controlPoint2: NSPoint(x: 10, y: 18))
    p.curve(to: NSPoint(x: 5, y: 20), controlPoint1: NSPoint(x: 7, y: 18), controlPoint2: NSPoint(x: 6.2, y: 20))
    p.close()
    p.lineWidth = width
    p.lineJoinStyle = .round
    p.lineCapStyle = .round
    p.stroke()
    color.setFill()
    for x in [9.5, 14.5] {
        NSBezierPath(roundedRect: NSRect(x: x - 0.8, y: 9, width: 1.6, height: 3), xRadius: 0.8, yRadius: 0.8).fill()
    }
}

final class MarkView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { ghost(.black, width: 1.65) }
}
let mark = MarkView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
try mark.dataWithPDF(inside: mark.bounds).write(to: resources.appendingPathComponent("GhostTemplate.pdf"))

func png(size: Int, tile: Bool) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.translateX(by: 0, yBy: CGFloat(size))
    transform.scaleX(by: CGFloat(size) / 24, yBy: -CGFloat(size) / 24)
    transform.concat()
    if tile {
        NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 22, height: 22), xRadius: 5, yRadius: 5).fill()
        let inset = NSAffineTransform()
        inset.translateX(by: 3.6, yBy: 3.6)
        inset.scale(by: 0.7)
        inset.concat()
    }
    ghost(tile ? NSColor(calibratedRed: 0.55, green: 0.86, blue: 1.0, alpha: 1) : .black, width: tile ? 1.35 : 1.65)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try png(size: size, tile: true).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size: size * 2, tile: true).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
