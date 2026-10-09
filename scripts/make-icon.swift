import AppKit

let destination = CommandLine.arguments[1]
let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.91, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
        let green = NSColor(calibratedRed: 0.32, green: 0.43, blue: 0.34, alpha: 1)
        green.setFill()
        NSBezierPath(ovalIn: NSRect(x: 228, y: 560, width: 240, height: 240)).fill()
        NSColor.white.setStroke()
        let check = NSBezierPath()
        check.lineWidth = 23
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.move(to: NSPoint(x: 287, y: 682))
        check.line(to: NSPoint(x: 330, y: 639))
        check.line(to: NSPoint(x: 411, y: 725))
        check.stroke()
        green.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: NSRect(x: 525, y: 658, width: 238, height: 35), xRadius: 17, yRadius: 17).fill()
        green.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: 239, y: 423, width: 524, height: 35), xRadius: 17, yRadius: 17).fill()
        NSBezierPath(roundedRect: NSRect(x: 239, y: 295, width: 354, height: 35), xRadius: 17, yRadius: 17).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
