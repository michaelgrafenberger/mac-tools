import Cocoa

let project = CommandLine.arguments[1]
for appearance in ["light", "dark"] {
    let dark = appearance == "dark"
    let width = 2088, height = 1080
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
    }
    let bg = color(dark ? 0x191C19 : 0xEDEEE7)
    let ink = color(dark ? 0xEEF0E9 : 0x252C28)
    let secondary = color(dark ? 0xA7AEA3 : 0x72796F)
    bg.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
    text("NATIVE DESIGN PREVIEW", x: 42, y: 1032, size: 10, weight: .medium, color: secondary)
    text("Fünf Tools. Ein ruhiger Mac.", x: 42, y: 978, size: 37, weight: .medium, color: ink)
    text("Einzelne Apps. Eine Designsprache. So wenig Menübar wie du möchtest.", x: 43, y: 947, size: 15, weight: .regular, color: secondary)
    for (index, name) in ["Fokus", "Offen", "Grid", "NetSpeed", "RAMUsage"].enumerated() {
        guard let image = NSImage(contentsOfFile: "\(project)/Preview/\(name)-\(appearance).png") else { exit(2) }
        let png = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: "\(project)/Preview/\(name)-\(appearance).png")))!
        let h = CGFloat(png.pixelsHigh) / CGFloat(png.pixelsWide) * 372
        let rect = NSRect(x: 42 + CGFloat(index) * 408, y: 905 - h, width: 372, height: h)
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: rect, xRadius: 17, yRadius: 17); clip.addClip()
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        color(dark ? 0x3D443B : 0xD9DED2).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 17, yRadius: 17); border.lineWidth = 0.75; border.stroke()
    }
    text("0.3.0 · Native SwiftUI-Oberflächen · Ansichten mit Beispieldaten · \(dark ? "Dark" : "Light")", x: 43, y: 35, size: 12, weight: .regular, color: secondary)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(project)/Preview/Collection-\(appearance).png"))
}
print("Preview boards generated.")
