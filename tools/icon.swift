import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func symbol(_ name: String, _ pt: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: weight).applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
}
func drawCentered(_ img: NSImage, _ cx: CGFloat, _ cy: CGFloat) {
    img.draw(in: NSRect(x: cx - img.size.width / 2, y: cy - img.size.height / 2, width: img.size.width, height: img.size.height))
}

for (size, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
    let s = CGFloat(size), k = s / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let path = NSBezierPath(roundedRect: body, xRadius: 186 * k, yRadius: 186 * k)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 24 * k
    shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
    shadow.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(srgbRed: 30/255, green: 30/255, blue: 30/255, alpha: 1).setFill()
    path.fill()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.08), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5 * k, dy: 1.5 * k), xRadius: 185 * k, yRadius: 185 * k)
    rim.lineWidth = max(1, 3 * k)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    rim.stroke()

    let cx = body.midX, cy = body.midY - 6 * k
    if let m = symbol("computermouse.fill", 330 * k, .medium, .white) { drawCentered(m, cx, cy) }
    if size >= 64 {
        if let l = symbol("chevron.compact.left", 150 * k, .bold, NSColor.white.withAlphaComponent(0.75)) { drawCentered(l, cx - 245 * k, cy) }
        if let r = symbol("chevron.compact.right", 150 * k, .bold, NSColor.white.withAlphaComponent(0.75)) { drawCentered(r, cx + 245 * k, cy) }
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
