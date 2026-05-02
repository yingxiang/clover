#!/usr/bin/swift

import AppKit
import CoreImage
import Foundation

// MARK: - Parameters

let canvasSize: CGFloat = 1024
let cornerRadiusRatio: CGFloat = 0.2        // 圆角比例 (0.0 ~ 0.5)
let iconSizeRatio: CGFloat = 1.2          // 中心图标占画布比例 (0.0 ~ 1.0)
let blobOpacity: CGFloat = 0.28
let gradientSeedOverride: UInt64? = nil     // 固定值则每次相同，nil 则随机
let outputFileName = "app_icon.png"

// MARK: - Seeded Random (同原代码)

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

func randomUnit(using generator: inout SeededGenerator) -> CGFloat {
    CGFloat(Double(generator.next()) / Double(UInt64.max))
}

func makeGradientPalette(seed: UInt64) -> [NSColor] {
    var generator = SeededGenerator(seed: seed)
    let baseHue = randomUnit(using: &generator)
    let hueShift1 = 0.07 + randomUnit(using: &generator) * 0.08
    let hueShift2 = 0.15 + randomUnit(using: &generator) * 0.10
    return [
        NSColor(calibratedHue: baseHue, saturation: 0.72, brightness: 0.98, alpha: 1),
        NSColor(calibratedHue: (baseHue + hueShift1).truncatingRemainder(dividingBy: 1), saturation: 0.78, brightness: 0.82, alpha: 1),
        NSColor(calibratedHue: (baseHue + hueShift2).truncatingRemainder(dividingBy: 1), saturation: 0.66, brightness: 0.62, alpha: 1),
    ]
}

// MARK: - Paths

let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconURL = scriptDirectory.appendingPathComponent("icon.png")
let outputURL = scriptDirectory.appendingPathComponent(outputFileName)

// MARK: - Render

guard let iconImage = NSImage(contentsOf: iconURL) else {
    print("Error: icon.png not found at \(iconURL.path)")
    exit(1)
}

let seed = gradientSeedOverride ?? UInt64.random(in: 0...UInt64.max)
let palette = makeGradientPalette(seed: seed)
let cornerRadius = canvasSize * cornerRadiusRatio
let rect = NSRect(origin: .zero, size: NSSize(width: canvasSize, height: canvasSize))

let px = Int(canvasSize)
let bitmapCtx = CGContext(data: nil, width: px, height: px,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let nsCtx = NSGraphicsContext(cgContext: bitmapCtx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx

// Gradient background
let gradient = NSGradient(colors: palette)!
gradient.draw(in: NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius), angle: -35)

// Glow blobs
// var blobGen = SeededGenerator(seed: seed &+ 1)
// for i in 0..<3 {
//     let diameter = CGFloat(320 + Int(randomUnit(using: &blobGen) * 320))
//     let x = CGFloat(40 + Int(randomUnit(using: &blobGen) * (canvasSize - diameter - 80)))
//     let y = CGFloat(40 + Int(randomUnit(using: &blobGen) * (canvasSize - diameter - 80)))
//     palette[i % palette.count].withAlphaComponent(blobOpacity).setFill()
//     NSBezierPath(ovalIn: CGRect(x: x, y: y, width: diameter, height: diameter)).fill()
// }

// Center icon
let iconSize = canvasSize * iconSizeRatio
let iconOrigin = CGPoint(x: (canvasSize - iconSize) / 2, y: (canvasSize - iconSize) / 2)
iconImage.draw(in: CGRect(origin: iconOrigin, size: CGSize(width: iconSize, height: iconSize)),
               from: .zero, operation: .sourceOver, fraction: 1.0)

// Water drop lens effect
let ctx = NSGraphicsContext.current!.cgContext
let roundClip = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
let cx = canvasSize / 2, cy = canvasSize / 2

// 1. Refraction dark ring (middle zone darker, like light bending around a droplet)
ctx.saveGState()
ctx.addPath(roundClip)
ctx.clip()
let ringColors = [NSColor.black.withAlphaComponent(0).cgColor,
                  NSColor.black.withAlphaComponent(0).cgColor,
                  NSColor.black.withAlphaComponent(0.06).cgColor,
                  NSColor.black.withAlphaComponent(0).cgColor] as CFArray
let ringGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: ringColors, locations: [0, 0.42, 0.72, 1.0])!
ctx.drawRadialGradient(ringGrad,
    startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
    endCenter: CGPoint(x: cx, y: cy), endRadius: canvasSize * 0.62,
    options: [.drawsAfterEndLocation])
ctx.restoreGState()

// 2. Bright rim (total internal reflection at edge)
ctx.saveGState()
ctx.addPath(roundClip)
ctx.clip()
let rimColors = [NSColor.white.withAlphaComponent(0).cgColor,
                 NSColor.white.withAlphaComponent(0).cgColor,
                 NSColor.white.withAlphaComponent(0.28).cgColor] as CFArray
let rimGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: rimColors, locations: [0, 0.78, 1.0])!
ctx.drawRadialGradient(rimGrad,
    startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
    endCenter: CGPoint(x: cx, y: cy), endRadius: canvasSize * 0.62,
    options: [.drawsAfterEndLocation])
ctx.restoreGState()

// 3. Primary specular: bright oval top-left (main light reflection on droplet surface)
ctx.saveGState()
ctx.addPath(roundClip)
ctx.clip()
let spec1 = CGPoint(x: canvasSize * 0.35, y: canvasSize * 0.72)
let s1Colors = [NSColor.white.withAlphaComponent(0.72).cgColor,
                NSColor.white.withAlphaComponent(0).cgColor] as CFArray
let s1Grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: s1Colors, locations: [0, 1.0])!
ctx.saveGState()
ctx.translateBy(x: spec1.x, y: spec1.y)
ctx.scaleBy(x: 1.0, y: 0.55)
ctx.translateBy(x: -spec1.x, y: -spec1.y)
ctx.drawRadialGradient(s1Grad, startCenter: spec1, startRadius: 0,
                       endCenter: spec1, endRadius: canvasSize * 0.28, options: [])
ctx.restoreGState()
ctx.restoreGState()

// 4. Secondary specular: tiny bright dot (second reflection)
ctx.saveGState()
ctx.addPath(roundClip)
ctx.clip()
let spec2 = CGPoint(x: canvasSize * 0.62, y: canvasSize * 0.34)
let s2Colors = [NSColor.white.withAlphaComponent(0.35).cgColor,
                NSColor.white.withAlphaComponent(0).cgColor] as CFArray
let s2Grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: s2Colors, locations: [0, 1.0])!
ctx.drawRadialGradient(s2Grad, startCenter: spec2, startRadius: 0,
                       endCenter: spec2, endRadius: canvasSize * 0.12, options: [])
ctx.restoreGState()

// 5. Thin outer stroke
NSGraphicsContext.current?.saveGraphicsState()
NSColor.white.withAlphaComponent(0.2).setStroke()
let strokePath = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1),
                              xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
strokePath.lineWidth = 1.5
strokePath.stroke()
NSGraphicsContext.current?.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

// Export PNG at exact 1024x1024 pixels
guard let cgImage = bitmapCtx.makeImage() else {
    print("Error: failed to get cgImage")
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Error: failed to render image")
    exit(1)
}

try! png.write(to: outputURL)
print("Icon saved to: \(outputURL.path) (seed: \(seed))")
