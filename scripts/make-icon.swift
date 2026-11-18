// Draws the app icon and writes App/Resources/AppIcon.icns.
//   swift scripts/make-icon.swift            (from the repo root)
//   swift scripts/make-icon.swift preview.png (also saves a 1024 px preview)
//
// Design: two photo prints feeding into a scanner slot, with the scan light glowing
// where they enter. Drawn on the standard macOS icon grid (824 pt body on a 1024 canvas).

import AppKit
import CoreGraphics

let S: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locations)!
}

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A print with a white border and a small landscape inside, drawn upright in its own space.
func drawPrint(_ ctx: CGContext, size: CGSize, sky: (UInt32, UInt32), hills: (UInt32, UInt32), sun: UInt32) {
    let r = CGRect(origin: .zero, size: size)
    // paper
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(roundedPath(r, 14)); ctx.setFillColor(color(0xFBFAF7)); ctx.fillPath()
    ctx.restoreGState()
    // picture area
    let inset = size.width * 0.075
    let pic = CGRect(x: inset, y: inset * 1.0, width: size.width - inset * 2, height: size.height - inset * 2)
    ctx.saveGState()
    ctx.addPath(roundedPath(pic, 6)); ctx.clip()
    ctx.drawLinearGradient(gradient([color(sky.0), color(sky.1)], [0, 1]),
                           start: CGPoint(x: 0, y: pic.maxY), end: CGPoint(x: 0, y: pic.minY), options: [])
    // sun
    ctx.setFillColor(color(sun))
    let sr = pic.width * 0.11
    ctx.fillEllipse(in: CGRect(x: pic.maxX - pic.width * 0.32, y: pic.maxY - pic.height * 0.34, width: sr * 2, height: sr * 2))
    // back hills
    ctx.setFillColor(color(hills.0))
    ctx.move(to: CGPoint(x: pic.minX, y: pic.minY + pic.height * 0.42))
    ctx.addCurve(to: CGPoint(x: pic.maxX, y: pic.minY + pic.height * 0.50),
                 control1: CGPoint(x: pic.minX + pic.width * 0.35, y: pic.minY + pic.height * 0.70),
                 control2: CGPoint(x: pic.minX + pic.width * 0.60, y: pic.minY + pic.height * 0.25))
    ctx.addLine(to: CGPoint(x: pic.maxX, y: pic.minY)); ctx.addLine(to: CGPoint(x: pic.minX, y: pic.minY))
    ctx.closePath(); ctx.fillPath()
    // front hills
    ctx.setFillColor(color(hills.1))
    ctx.move(to: CGPoint(x: pic.minX, y: pic.minY + pic.height * 0.22))
    ctx.addCurve(to: CGPoint(x: pic.maxX, y: pic.minY + pic.height * 0.30),
                 control1: CGPoint(x: pic.minX + pic.width * 0.45, y: pic.minY + pic.height * 0.05),
                 control2: CGPoint(x: pic.minX + pic.width * 0.70, y: pic.minY + pic.height * 0.45))
    ctx.addLine(to: CGPoint(x: pic.maxX, y: pic.minY)); ctx.addLine(to: CGPoint(x: pic.minX, y: pic.minY))
    ctx.closePath(); ctx.fillPath()
    ctx.restoreGState()
}

/// A document page with a heading bar and text lines.
func drawDocument(_ ctx: CGContext, size: CGSize) {
    let r = CGRect(origin: .zero, size: size)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0x000000, 0.30))
    ctx.addPath(roundedPath(r, 12)); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    let m = size.width * 0.13
    ctx.setFillColor(color(0x5B8DEF))
    ctx.addPath(roundedPath(CGRect(x: m, y: size.height - m - 26, width: size.width * 0.45, height: 26), 8)); ctx.fillPath()
    ctx.setFillColor(color(0xC5CCD8))
    var y = size.height - m - 80
    var i = 0
    while y > m {
        let w = (size.width - 2 * m) * (i % 4 == 3 ? 0.6 : 1.0)
        ctx.addPath(roundedPath(CGRect(x: m, y: y, width: w, height: 14), 7)); ctx.fillPath()
        y -= 36; i += 1
    }
}

func drawIcon(_ ctx: CGContext) {
    // Body with soft drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.30))
    ctx.addPath(roundedPath(body, radius)); ctx.setFillColor(color(0x1B2A4A)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(roundedPath(body, radius)); ctx.clip()
    // Background: deep indigo to teal.
    ctx.drawLinearGradient(gradient([color(0x2B5876), color(0x1E3C72), color(0x16213E)], [0, 0.55, 1]),
                           start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // Soft highlight top-left.
    ctx.drawRadialGradient(gradient([color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)], [0, 1]),
                           startCenter: CGPoint(x: body.minX + 220, y: body.maxY - 180), startRadius: 0,
                           endCenter: CGPoint(x: body.minX + 220, y: body.maxY - 180), endRadius: 520, options: [])

    // Scanner base: a rounded slab across the lower part.
    let base = CGRect(x: body.minX + 70, y: body.minY + 110, width: body.width - 140, height: 170)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0x000000, 0.45))
    ctx.addPath(roundedPath(base, 48))
    ctx.setFillColor(color(0xE9EDF3)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(roundedPath(base, 48)); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xF7F9FC), color(0xC9D1DC)], [0, 1]),
                           start: CGPoint(x: 0, y: base.maxY), end: CGPoint(x: 0, y: base.minY), options: [])
    ctx.restoreGState()

    // Feed slot (dark) near the top of the base.
    let slot = CGRect(x: base.minX + 60, y: base.maxY - 62, width: base.width - 120, height: 30)
    ctx.addPath(roundedPath(slot, 15)); ctx.setFillColor(color(0x1A1F2B)); ctx.fillPath()

    // Prints entering the slot: clip so they disappear into it.
    let printSize = CGSize(width: 380, height: 300)
    ctx.saveGState()
    ctx.clip(to: CGRect(x: body.minX, y: slot.midY, width: body.width, height: body.maxY - slot.midY))
    // document page behind, tilted right
    ctx.saveGState()
    ctx.translateBy(x: body.midX + 150, y: slot.midY - 30)
    ctx.rotate(by: -0.20)
    ctx.translateBy(x: -150, y: 0)
    drawDocument(ctx, size: CGSize(width: 300, height: 420))
    ctx.restoreGState()
    // back print, tilted left
    ctx.saveGState()
    ctx.translateBy(x: body.midX - 90, y: slot.midY - 20)
    ctx.rotate(by: 0.20)
    ctx.translateBy(x: -printSize.width / 2, y: 0)
    drawPrint(ctx, size: printSize, sky: (0xF6C177, 0xF28C61), hills: (0xB55D4C, 0x7A3E48), sun: 0xFFF1C9)
    ctx.restoreGState()
    // front print, slightly tilted right
    ctx.saveGState()
    ctx.translateBy(x: body.midX + 10, y: slot.midY - 45)
    ctx.rotate(by: -0.06)
    ctx.translateBy(x: -printSize.width / 2, y: 0)
    drawPrint(ctx, size: printSize, sky: (0x8EC5FC, 0xE0C3FC), hills: (0x5DA271, 0x2E7D5B), sun: 0xFFE08A)
    ctx.restoreGState()
    ctx.restoreGState()

    // Scan light: a soft glow rising from the slot, then a bright line along it.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: slot.minX - 20, y: slot.midY, width: slot.width + 40, height: 140))
    ctx.drawLinearGradient(gradient([color(0x6FE7FF, 0.55), color(0x6FE7FF, 0)], [0, 1]),
                           start: CGPoint(x: 0, y: slot.midY), end: CGPoint(x: 0, y: slot.midY + 140), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0x6FE7FF, 1))
    ctx.addPath(roundedPath(CGRect(x: slot.minX + 6, y: slot.midY - 5, width: slot.width - 12, height: 10), 5))
    ctx.setFillColor(color(0xE6FCFF)); ctx.fillPath()
    ctx.fillPath()
    ctx.restoreGState()

    // Status light on the base.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 12, color: color(0x34C759, 0.9))
    ctx.setFillColor(color(0x34C759))
    ctx.fillEllipse(in: CGRect(x: base.maxX - 92, y: base.minY + 40, width: 26, height: 26))
    ctx.restoreGState()

    ctx.restoreGState()
}

func render(_ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / S, y: CGFloat(px) / S)
    drawIcon(ctx)
    return ctx.makeImage()!
}

func writePNG(_ img: CGImage, _ url: URL) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 1 {
    writePNG(render(1024), URL(fileURLWithPath: CommandLine.arguments[1]))
}
let out = root.appendingPathComponent("App/Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
