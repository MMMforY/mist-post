import AppKit
import CoreText

/// All chart artwork is drawn in flipped coordinates, with one map square per unit.
enum ChartInk {
    static let abyss = color(0x102E30)
    static let sea = color(0x204747)
    static let shoal = color(0x52776F)
    static let depth = color(0x72938A)
    static let mist = color(0xACC4AD)
    static let paper = color(0xE8DAB2)
    static let bright = color(0xFFF0C8)
    static let ochre = color(0xCEB580)
    static let stone = color(0x9D9F86)
    static let shadow = color(0x435956)
    static let ink = color(0x163738)
    static let coal = color(0x102B2E)
    static let roof = color(0xA75E43)
    static let red = color(0xD8764E)
    static let rust = color(0x853F33)
    static let amber = color(0xF4C270)
    static let echo = color(0xA5E1CE)
    static let echoTwo = color(0xDECCE7)

    static func color(_ hex: Int) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

extension CGColor {
    func chartAlpha(_ alpha: CGFloat) -> CGColor { copy(alpha: alpha)! }
}

struct ChartPen {
    let ctx: CGContext

    func saved(_ paint: () -> Void) {
        ctx.saveGState()
        paint()
        ctx.restoreGState()
    }

    func placed(at point: CGPoint, scale: CGFloat = 1, angle: CGFloat = 0,
                paint: () -> Void) {
        saved {
            ctx.translateBy(x: point.x, y: point.y)
            ctx.rotate(by: angle)
            ctx.scaleBy(x: scale, y: scale)
            paint()
        }
    }

    func path(_ path: CGPath, fill: CGColor? = nil, stroke: CGColor? = nil, width: CGFloat = 0.02) {
        guard fill != nil || stroke != nil else { return }
        ctx.beginPath()
        ctx.addPath(path)
        if let fill { ctx.setFillColor(fill) }
        if let stroke { ctx.setStrokeColor(stroke); ctx.setLineWidth(width) }
        ctx.drawPath(using: fill == nil ? .stroke : (stroke == nil ? .eoFill : .eoFillStroke))
    }

    func curve(fill: CGColor? = nil, stroke: CGColor? = nil, width: CGFloat = 0.02,
               _ build: (CGMutablePath) -> Void) {
        let p = CGMutablePath()
        build(p)
        path(p, fill: fill, stroke: stroke, width: width)
    }

    func poly(_ points: [CGPoint], _ fill: CGColor?, stroke: CGColor? = nil,
              width: CGFloat = 0.02, closed: Bool = true) {
        guard let first = points.first else { return }
        curve(fill: fill, stroke: stroke, width: width) { path in
            path.move(to: first)
            for p in points.dropFirst() { path.addLine(to: p) }
            if closed { path.closeSubpath() }
        }
    }

    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
              _ color: CGColor, _ width: CGFloat = 0.02) {
        ctx.beginPath()
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color)
        ctx.strokePath()
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
              _ fill: CGColor?, stroke: CGColor? = nil, width: CGFloat = 0.02) {
        path(CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: nil),
             fill: fill, stroke: stroke, width: width)
    }

    func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
              _ fill: CGColor?, stroke: CGColor? = nil, width: CGFloat = 0.02) {
        path(CGPath(ellipseIn: CGRect(x: x, y: y, width: w, height: h), transform: nil),
             fill: fill, stroke: stroke, width: width)
    }

    func text(_ string: String, centeredAt p: CGPoint, size: CGFloat, color: CGColor) {
        let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string,
          attributes: [.font: font, .foregroundColor: NSColor(cgColor: color) ?? .white]))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        saved {
            ctx.translateBy(x: p.x - width / 2, y: p.y + (ascent - descent) / 2)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = .identity
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
        }
    }
}

@inline(__always) func chartPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

struct SurveySeed {
    private var value: UInt64
    init(_ value: Int) { self.value = UInt64(truncatingIfNeeded: value) &+ 467831 }
    mutating func next() -> CGFloat {
        value = value &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(value >> 40) / 16777216
    }
}
