import AppKit
import Foundation

// Tekent het Bonk-app-icoon: een comic-style "knal"-ster (impact burst) met een
// vette "!" op een paars→magenta gradient-squircle. Schrijft alle iconset-PNG's
// naar ./Bonk.iconset.

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let outDir = fm.currentDirectoryPath + "/Bonk.iconset"
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func starburst(center: CGPoint, outer: CGFloat, inner: CGFloat, points: Int, rotation: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let total = points * 2
    for i in 0..<total {
        let r = (i % 2 == 0) ? outer : inner
        let angle = rotation + CGFloat(i) * .pi / CGFloat(points)
        let p = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        if i == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    path.close()
    return path
}

func makeIcon(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: px, height: px)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let size = CGFloat(px)
    let inset = size * 0.085
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Gradient-achtergrond (diagonaal, levendig)
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let purple = NSColor(srgbRed: 0x6A / 255, green: 0x11 / 255, blue: 0xCB / 255, alpha: 1)
    let pink   = NSColor(srgbRed: 0xE7 / 255, green: 0x26 / 255, blue: 0x77 / 255, alpha: 1)
    NSGradient(colors: [purple, pink])?.draw(in: rect, angle: -55)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), .clear])?
        .draw(in: rect, relativeCenterPosition: NSPoint(x: -0.35, y: 0.55))
    NSGraphicsContext.restoreGraphicsState()

    let center = CGPoint(x: rect.midX, y: rect.midY)
    let burstOuter = rect.width * 0.41
    let burstInner = burstOuter * 0.55

    // Schaduw onder de burst voor diepte
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = rect.width * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.015)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    // Gele accent-ster erachter (iets groter en gedraaid)
    let yellow = NSColor(srgbRed: 1.0, green: 0.84, blue: 0.27, alpha: 1)
    yellow.setFill()
    starburst(center: center, outer: burstOuter * 1.06, inner: burstInner * 1.04,
              points: 11, rotation: .pi / 11).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Witte ster ervoor
    NSColor.white.setFill()
    starburst(center: center, outer: burstOuter, inner: burstInner, points: 11, rotation: 0).fill()

    // Vette "!" in het midden
    let fontSize = rect.width * 0.34
    let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let font = NSFont(descriptor: baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor,
                      size: fontSize) ?? baseFont
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: purple,
    ]
    let str = NSAttributedString(string: "!", attributes: attrs)
    let sz = str.size()
    str.draw(at: CGPoint(x: center.x - sz.width / 2,
                         y: center.y - sz.height / 2 + rect.width * 0.005))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    if let data = makeIcon(px: px) {
        try? data.write(to: URL(fileURLWithPath: outDir + "/\(name).png"))
        print("wrote \(name).png (\(px)px)")
    } else {
        FileHandle.standardError.write(Data("FAILED \(name)\n".utf8))
    }
}
