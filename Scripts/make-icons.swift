import Cocoa

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)

func drawIcon(_ name: String, size: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    let plate = NSBezierPath(roundedRect: NSRect(x: 84, y: 84, width: 856, height: 856), xRadius: 192, yRadius: 192)
    NSColor(srgbRed: 0.91, green: 0.93, blue: 0.88, alpha: 1).setFill(); plate.fill()
    NSColor(srgbRed: 0.32, green: 0.42, blue: 0.35, alpha: 1).setStroke()
    NSColor(srgbRed: 0.32, green: 0.42, blue: 0.35, alpha: 1).setFill()
    func path(_ points: [NSPoint], close: Bool = false) {
        let p = NSBezierPath(); p.lineWidth = 34; p.lineCapStyle = .round; p.lineJoinStyle = .round
        p.move(to: points[0]); for point in points.dropFirst() { p.line(to: point) }; if close { p.close() }; p.stroke()
    }
    switch name {
    case "Fokus":
        let ring = NSBezierPath(ovalIn: NSRect(x: 294, y: 294, width: 436, height: 436)); ring.lineWidth = 32; ring.stroke()
        NSBezierPath(ovalIn: NSRect(x: 343, y: 343, width: 338, height: 338)).fill()
    case "Offen":
        let outline = NSBezierPath(roundedRect: NSRect(x: 266, y: 338, width: 492, height: 232), xRadius: 42, yRadius: 42)
        outline.lineWidth = 32; outline.stroke()
        path([NSPoint(x: 266, y: 538), NSPoint(x: 370, y: 690), NSPoint(x: 654, y: 690), NSPoint(x: 758, y: 538)])
        path([NSPoint(x: 266, y: 494), NSPoint(x: 421, y: 494), NSPoint(x: 443, y: 440), NSPoint(x: 581, y: 440), NSPoint(x: 603, y: 494), NSPoint(x: 758, y: 494)])
    case "Grid":
        let outline = NSBezierPath(roundedRect: NSRect(x: 288, y: 288, width: 448, height: 448), xRadius: 44, yRadius: 44)
        outline.lineWidth = 32; outline.stroke()
        path([NSPoint(x: 512, y: 288), NSPoint(x: 512, y: 736)])
        path([NSPoint(x: 288, y: 512), NSPoint(x: 736, y: 512)])
    case "RAMUsage":
        let chip = NSBezierPath(roundedRect: NSRect(x: 340, y: 340, width: 344, height: 344), xRadius: 44, yRadius: 44)
        chip.lineWidth = 32; chip.stroke()
        for offset in [420.0, 512.0, 604.0] {
            path([NSPoint(x: offset, y: 275), NSPoint(x: offset, y: 340)])
            path([NSPoint(x: offset, y: 684), NSPoint(x: offset, y: 749)])
            path([NSPoint(x: 275, y: offset), NSPoint(x: 340, y: offset)])
            path([NSPoint(x: 684, y: offset), NSPoint(x: 749, y: offset)])
        }
    default:
        path([NSPoint(x: 420, y: 724), NSPoint(x: 420, y: 330)])
        path([NSPoint(x: 310, y: 446), NSPoint(x: 420, y: 330), NSPoint(x: 530, y: 446)])
        path([NSPoint(x: 647, y: 330), NSPoint(x: 647, y: 650)])
        path([NSPoint(x: 563, y: 562), NSPoint(x: 647, y: 650), NSPoint(x: 731, y: 562)])
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for name in ["Fokus", "Offen", "Grid", "NetSpeed", "RAMUsage"] {
    let iconset = "\(destination)/\(name).iconset"
    try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for multiplier in [1, 2] {
            let bitmap = drawIcon(name, size: base * multiplier)
            let suffix = multiplier == 2 ? "@2x" : ""
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)\(suffix).png"))
        }
    }
    let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset, "-o", "\(destination)/\(name).icns"]
    try task.run(); task.waitUntilExit()
    guard task.terminationStatus == 0 else { exit(1) }
    try drawIcon(name, size: 512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/\(name).png"))
    try FileManager.default.removeItem(atPath: iconset)
}
print("Five icon families generated.")
