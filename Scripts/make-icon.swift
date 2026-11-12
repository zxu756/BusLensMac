#!/usr/bin/env swift
import AppKit
import Foundation

let iconsetPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func drawIcon(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    let pad = s * 0.08
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    cg.saveGState()
    cg.addPath(path)
    cg.clip()

    let bgColors = [
        CGColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1.0),
        CGColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1.0)
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0.0, 1.0])!
    cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // USB-C oval receptacle housing
    let pillW = s * 0.62
    let pillH = s * 0.26
    let pillRect = CGRect(x: (s - pillW) / 2, y: s * 0.44, width: pillW, height: pillH)
    let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil)
    cg.setFillColor(CGColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 0.18))
    cg.addPath(pillPath)
    cg.fillPath()
    cg.setStrokeColor(CGColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 0.95))
    cg.setLineWidth(s * 0.045)
    cg.addPath(pillPath)
    cg.strokePath()

    // Center tongue pins inside USB-C port
    let tongueW = pillW * 0.64
    let tongueH = s * 0.045
    let tongueRect = CGRect(x: (s - tongueW) / 2, y: pillRect.midY - tongueH / 2, width: tongueW, height: tongueH)
    cg.setFillColor(CGColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 0.95))
    cg.fill(tongueRect)

    // 4 differential PCIe / USB4 signal traces below port
    let laneColors: [CGColor] = [
        CGColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1.0),
        CGColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1.0),
        CGColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1.0),
        CGColor(red: 0.98, green: 0.44, blue: 0.52, alpha: 1.0)
    ]
    cg.setLineWidth(s * 0.036)
    cg.setLineCap(.round)
    for i in 0..<4 {
        let x = s * (0.32 + CGFloat(i) * 0.12)
        cg.setStrokeColor(laneColors[i])
        cg.move(to: CGPoint(x: x, y: s * 0.36))
        cg.addLine(to: CGPoint(x: x, y: s * 0.18))
        cg.strokePath()
    }

    cg.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    try drawIcon(size: px).write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
}
