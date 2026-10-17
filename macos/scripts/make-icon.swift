// Draws the app icon: a pulse line — activity measured as it happens — in cream
// on Claude's terracotta, with a small burst of rays in the corner as the nod to
// Claude. The burst is this project's own drawing in that style, not Anthropic's
// mark.
//
//   swift macos/scripts/make-icon.swift <output.iconset>
//   iconutil -c icns <output.iconset> -o macos/Resources/AppIcon.icns
//
// Run by macos/scripts/make-icon.sh; the result is committed, so a build does
// not need to draw anything.
import AppKit

let terracotta = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)  // #D97757
let terracottaDeep = NSColor(srgbRed: 0.74, green: 0.37, blue: 0.25, alpha: 1)
let cream = NSColor(srgbRed: 0.98, green: 0.965, blue: 0.93, alpha: 1)

/// The pulse, left to right: x as a share of the line's width, y as a share of
/// its half-height (positive is up). Flat, a small bump, then the big beat.
let pulse: [(x: CGFloat, y: CGFloat)] = [
    (0.00, 0), (0.20, 0), (0.28, 0.22), (0.36, -0.18), (0.42, 0),
    (0.52, 0), (0.60, 1.0), (0.70, -0.85), (0.78, 0.30), (0.84, 0), (1.00, 0),
]

/// Rays of different lengths around a hub, as a share of the longest.
let rays: [CGFloat] = [1.0, 0.62, 0.84, 0.5, 0.94, 0.7, 0.56, 0.9, 0.66, 0.98, 0.52, 0.78]

func burst(at center: CGPoint, radius: CGFloat, width: CGFloat) {
    let hub = radius * 0.2
    for (i, share) in rays.enumerated() {
        let angle = CGFloat(i) / CGFloat(rays.count) * 2 * .pi + .pi / 2
        let inner = hub + radius * 0.06
        let outer = inner + (radius - inner) * share
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        path.line(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
        cream.setStroke()
        path.stroke()
    }
    cream.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)).fill()
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // macOS icons sit inside a margin of about 10% on each side.
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let body = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.2237, yRadius: tile.width * 0.2237)

    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
        color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    body.fill()
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
    NSGradient(starting: terracotta, ending: terracottaDeep)!.draw(in: body, angle: -90)

    // The pulse, a little below centre so the burst has the upper corner.
    let lineWidth = tile.width * 0.68
    let left = tile.midX - lineWidth / 2
    let mid = tile.midY - tile.height * 0.06
    let amplitude = tile.height * 0.22
    let path = NSBezierPath()
    path.lineWidth = tile.width * 0.05
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    for (i, point) in pulse.enumerated() {
        let p = CGPoint(x: left + lineWidth * point.x, y: mid + amplitude * point.y)
        if i == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    cream.setStroke()
    path.stroke()

    burst(at: CGPoint(x: tile.maxX - tile.width * 0.2, y: tile.maxY - tile.height * 0.2),
          radius: tile.width * 0.14, width: tile.width * 0.03)

    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let dir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
