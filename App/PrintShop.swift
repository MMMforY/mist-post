import AppKit

// Drawing primitives shared by the station's typeset menus and paper forms.
enum PrintShop {
    static func ink(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    static let night = ink(0x102c30), deep = ink(0x12383b), sea = ink(0x205257)
    static let paper = ink(0xeee4ca), cream = ink(0xffefd0), pale = ink(0xd9cfb3)
    static let graphite = ink(0x203e3d), gray = ink(0x536960), teal = ink(0x387174)
    static let ochre = ink(0xf6bd72), brick = ink(0x96452e), coral = ink(0xe78a54)
    static let rule = ink(0x9f9e84), foam = ink(0xa7c8b7)

    static func serif(_ size: CGFloat, heavy: Bool = false) -> NSFont {
        StationTypesetter.font(.serif,size:size,weight:heavy ? .semibold : .regular)
    }
    static func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        StationTypesetter.font(.sans,size:size,weight:weight)
    }
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        StationTypesetter.font(.mono,size:size,weight:weight)
    }
    static func rect(_ r: NSRect, _ color: NSColor) {
        color.setFill()
        r.fill()
    }
    static func frame(_ r: NSRect, _ color: NSColor, _ width: CGFloat = 1) {
        color.setStroke()
        let path = NSBezierPath(rect: r.insetBy(dx: width / 2, dy: width / 2))
        path.lineWidth = width
        path.stroke()
    }
    static func line(_ points: [NSPoint], _ color: NSColor, _ width: CGFloat = 1, dash: [CGFloat] = []) {
        guard let first = points.first else { return }
        let p = NSBezierPath()
        p.move(to: first)
        points.dropFirst().forEach { p.line(to: $0) }
        p.lineWidth = width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        if !dash.isEmpty { p.setLineDash(dash, count: dash.count, phase: 0) }
        color.setStroke()
        p.stroke()
    }
    static func rule(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ color: NSColor) {
        line([.init(x: x, y: y), .init(x: x+w, y: y)], color)
    }
    static func ellipse(_ r: NSRect, fill: NSColor? = nil, stroke: NSColor? = nil, width: CGFloat = 1) {
        let p = NSBezierPath(ovalIn: r)
        if let fill { fill.setFill(); p.fill() }
        if let stroke { stroke.setStroke(); p.lineWidth = width; p.stroke() }
    }
    static func polygon(_ pts: [NSPoint], fill: NSColor) {
        guard let first = pts.first else { return }
        let p = NSBezierPath()
        p.move(to: first)
        pts.dropFirst().forEach { p.line(to: $0) }
        p.close()
        fill.setFill()
        p.fill()
    }
    static func text(_ str: String, _ r: NSRect, _ font: NSFont, _ color: NSColor,
                     align: NSTextAlignment = .left, kern: CGFloat = 0, wrap: Bool = false,
                     spacing: CGFloat = 2, centerY: Bool = false) {
        StationTypesetter.draw(str,in:r,font:font,color:color,align:align,kern:kern,
                               wrap:wrap,spacing:spacing,centerY:centerY)
    }
    static func imageCover(_ image: NSImage, in rect: NSRect) {
        let aspect = rect.width / max(1, rect.height)
        let size = image.size
        var crop = NSRect(origin: .zero, size: size)
        if size.width / size.height > aspect {
            crop.size.width = size.height * aspect
            crop.origin.x = (size.width - crop.width) / 2
        } else {
            crop.size.height = size.width / aspect
            crop.origin.y = (size.height - crop.height) / 2
        }
        image.draw(in: rect, from: crop, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    static func mark(_ r: NSRect, _ color: NSColor) {
        // Postal pennant over two wake lines.
        let q: (CGFloat,CGFloat) -> CGPoint = { .init(x: r.minX + $0 * r.width, y: r.minY + $1 * r.height) }
        line([q(0.48,0.08), q(0.48,0.6)], color, 1.8)
        polygon([q(0.49,0.08), q(0.91,0.18), q(0.49,0.33)], fill: color)
        line([q(0.09,0.52), q(0.29,0.72), q(0.74,0.72), q(0.92,0.49), q(0.09,0.52)], color, 2)
        line([q(0.06,0.88),q(0.32,0.82),q(0.54,0.9),q(0.78,0.83),q(0.95,0.85)],color,1.5)
    }
    static func sound(_ r: NSRect, on: Bool, color: NSColor) {
        let q: (CGFloat,CGFloat) -> CGPoint = { .init(x: r.minX + $0 * r.width, y: r.minY + $1 * r.height) }
        line([q(0.06,0.37),q(0.25,0.37),q(0.51,0.15),q(0.51,0.85),q(0.25,0.63),q(0.06,0.63),q(0.06,0.37)],color,1.6)
        if on {
            for k in [0.0, 0.16] {
                line([q(0.65+k,0.31-k/2),q(0.75+k,0.44),q(0.75+k,0.56),q(0.65+k,0.69+k/2)],color,1.5)
            }
        } else {
            line([q(0.68,0.35),q(0.95,0.65)],color,1.5)
            line([q(0.95,0.35),q(0.68,0.65)],color,1.5)
        }
    }
    static func arrow(_ r: NSRect, color: NSColor, left: Bool = false) {
        let a = left ? r.maxX : r.minX, b = left ? r.minX : r.maxX
        line([.init(x:a, y:r.midY), .init(x:b, y:r.midY)], color, 1.8)
        let d:CGFloat = left ? 1 : -1
        line([.init(x:b+d*r.height/2,y:r.minY),.init(x:b,y:r.midY),
              .init(x:b+d*r.height/2,y:r.maxY)],color,1.8)
    }
}

typealias P = PrintShop
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: y, width: w, height: h)
}
