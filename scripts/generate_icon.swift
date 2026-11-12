import AppKit
import CoreGraphics
import Foundation

func renderMonochromeIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // macOS icon grid guideline: ~824px squircle inside 1024px canvas
    let margin = size * 0.09
    let squircleRect = rect.insetBy(dx: margin, dy: margin)
    let cornerRadius = squircleRect.width * 0.224

    // 1. Drop Shadow
    ctx.saveGState()
    let shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.04, color: shadowColor)

    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Base Background (Matte Charcoal to Dark Slate gradient)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(white: 0.16, alpha: 1.0).cgColor,
        NSColor(white: 0.07, alpha: 1.0).cgColor
    ] as CFArray

    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: squircleRect.midX, y: squircleRect.maxY), end: CGPoint(x: squircleRect.midX, y: squircleRect.minY), options: [])
    }

    // 3. Subtle Inner Rim Stroke
    ctx.addPath(squirclePath)
    ctx.setLineWidth(size * 0.006)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.20).cgColor)
    ctx.strokePath()

    // 4. Flat Monochrome Magnet & P2P Swarm Motif
    let centerX = squircleRect.midX
    let centerY = squircleRect.midY
    let iconScale = squircleRect.width * 0.52

    ctx.saveGState()
    ctx.translateBy(x: centerX, y: centerY)

    let magnetPath = CGMutablePath()
    let r = iconScale * 0.44
    let armW = iconScale * 0.20
    let armH = iconScale * 0.40

    magnetPath.addArc(center: CGPoint(x: 0, y: 0), radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
    magnetPath.addLine(to: CGPoint(x: r, y: armH))
    magnetPath.addLine(to: CGPoint(x: r - armW, y: armH))
    magnetPath.addLine(to: CGPoint(x: r - armW, y: 0))
    magnetPath.addArc(center: CGPoint(x: 0, y: 0), radius: r - armW, startAngle: 0, endAngle: .pi, clockwise: true)
    magnetPath.addLine(to: CGPoint(x: -r + armW, y: armH))
    magnetPath.addLine(to: CGPoint(x: -r, y: armH))
    magnetPath.closeSubpath()

    // Magnet Body
    ctx.setFillColor(NSColor(white: 0.95, alpha: 1.0).cgColor)
    ctx.addPath(magnetPath)
    ctx.fillPath()

    // Downward Download Flow Arrow
    let arrowPath = CGMutablePath()
    let arrowW = iconScale * 0.18
    let arrowHeadH = iconScale * 0.28
    let arrowShaftH = iconScale * 0.28
    let topY = armH * 0.9
    let tipY = topY - arrowShaftH - arrowHeadH

    arrowPath.move(to: CGPoint(x: -arrowW * 0.5, y: topY))
    arrowPath.addLine(to: CGPoint(x: arrowW * 0.5, y: topY))
    arrowPath.addLine(to: CGPoint(x: arrowW * 0.5, y: topY - arrowShaftH))
    arrowPath.addLine(to: CGPoint(x: arrowW * 1.1, y: topY - arrowShaftH))
    arrowPath.addLine(to: CGPoint(x: 0, y: tipY))
    arrowPath.addLine(to: CGPoint(x: -arrowW * 1.1, y: topY - arrowShaftH))
    arrowPath.addLine(to: CGPoint(x: -arrowW * 0.5, y: topY - arrowShaftH))
    arrowPath.closeSubpath()

    ctx.setFillColor(NSColor(white: 0.82, alpha: 1.0).cgColor)
    ctx.addPath(arrowPath)
    ctx.fillPath()

    // P2P Network Nodes
    let nodeRadius = iconScale * 0.05
    let nodes: [(CGFloat, CGFloat)] = [
        (-iconScale * 0.65, iconScale * 0.10),
        (iconScale * 0.65, iconScale * 0.10),
        (0, -iconScale * 0.55),
        (-iconScale * 0.40, -iconScale * 0.42),
        (iconScale * 0.40, -iconScale * 0.42)
    ]

    ctx.setFillColor(NSColor(white: 0.95, alpha: 0.90).cgColor)
    for (nx, ny) in nodes {
        ctx.fillEllipse(in: CGRect(x: nx - nodeRadius, y: ny - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2))
    }

    ctx.restoreGState()
    ctx.restoreGState()

    img.unlockFocus()
    return img
}

func savePNG(image: NSImage, at url: URL, pixelSize: Int) throws {
    guard let _ = image.tiffRepresentation else {
        throw NSError(domain: "ImageError", code: 1, userInfo: nil)
    }

    let exactRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: exactRep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = exactRep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PNGError", code: 2, userInfo: nil)
    }

    try pngData.write(to: url)
}

// Main execution
let args = CommandLine.arguments
let outputDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "./Resources")
let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")

try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

print("🎨 Rendering Flat Monochrome macOS Iconset...")

let iconSizes: [(String, Int)] = [
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

let monoImage = renderMonochromeIcon(size: 1024)

for (filename, pixelSize) in iconSizes {
    try savePNG(image: monoImage, at: iconsetDir.appendingPathComponent(filename), pixelSize: pixelSize)
}

try savePNG(image: monoImage, at: outputDir.appendingPathComponent("AppIcon.png"), pixelSize: 512)

print("✅ Saved flat monochrome iconset into \(iconsetDir.path)")
