import AppKit
import CoreText

/// Fonts and shaped lines can outlive any individual AppKit drawing pass.
/// Both caches have a hard entry limit and store only immutable objects.
private final class TypeCache<Key: Hashable, Value> {
    private let limit: Int
    private let lock = NSLock()
    private var entries: [Key: Value] = [:]
    private var order: [Key] = []
    private var oldest = 0

    init(limit: Int) { self.limit = limit }

    func value(for key: Key, create: () -> Value) -> Value {
        lock.lock()
        if let value = entries[key] {
            lock.unlock()
            return value
        }
        lock.unlock()

        let value = create()
        lock.lock()
        defer { lock.unlock() }
        if let existing = entries[key] { return existing }
        if order.count == limit {
            entries.removeValue(forKey: order[oldest])
            order[oldest] = key
            oldest = (oldest + 1) % limit
        } else {
            order.append(key)
        }
        entries[key] = value
        return value
    }
}

enum StationTypesetter {
    enum Face: Hashable { case serif, sans, mono }
    private struct FontKey: Hashable {
        let face: Face
        let size: CGFloat
        let weight: CGFloat
    }
    private struct LayoutKey: Hashable {
        let text: String
        let font: NSFont
        let width: CGFloat
        let kern: CGFloat
        let wrap: Bool
        let spacing: CGFloat
    }
    private struct Row {
        let line: CTLine?
        let baseline: CGFloat
    }
    private struct Layout {
        let rows: [Row]
        let height: CGFloat
    }
    private static let fonts = TypeCache<FontKey, NSFont>(limit: 160)
    private static let layouts = TypeCache<LayoutKey, Layout>(limit: 768)

    static func font(_ face: Face, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let key = FontKey(face: face, size: size, weight: weight.rawValue)
        return fonts.value(for: key) {
            switch face {
            case .serif:
                let bold = weight != .regular
                return NSFont(name: bold ? "Songti SC Bold" : "Songti SC Regular", size: size)
                    ?? NSFont(name: bold ? "STSongti-SC-Bold" : "STSongti-SC-Regular", size: size)
                    ?? .systemFont(ofSize: size, weight: weight)
            case .sans:
                return .systemFont(ofSize: size, weight: weight)
            case .mono:
                return .monospacedSystemFont(ofSize: size, weight: weight)
            }
        }
    }

    static func draw(_ text: String, in rect: CGRect, font: NSFont, color: NSColor,
                     align: NSTextAlignment, kern: CGFloat, wrap: Bool, spacing: CGFloat, centerY: Bool) {
        guard !text.isEmpty, rect.width > 0, rect.height > 0,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        let key = LayoutKey(text: text, font: font, width: rect.width, kern: kern, wrap: wrap, spacing: spacing)
        let layout = text.utf8.count <= 4096 ? layouts.value(for: key) { shape(key) } : shape(key)
        let flush: CGFloat
        switch align {
        case .center: flush = 0.5
        case .right: flush = 1
        default: flush = 0
        }
        let inset = centerY ? max(0,(rect.height-ceil(layout.height))/2) : 0
        ctx.saveGState()
        let formerMatrix = ctx.textMatrix
        let formerPosition = ctx.textPosition
        defer {
            ctx.restoreGState()
            ctx.textMatrix = formerMatrix
            ctx.textPosition = formerPosition
        }
        ctx.clip(to: rect)
        ctx.translateBy(x: rect.minX, y: rect.minY+inset)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.setTextDrawingMode(.fill)
        ctx.setFillColor(color.cgColor)
        for row in layout.rows {
            guard let line = row.line else { continue }
            let offset = flush == 0 ? 0 : CTLineGetPenOffsetForFlush(line, flush, Double(rect.width))
            ctx.textPosition = CGPoint(x: offset, y: -row.baseline)
            CTLineDraw(line, ctx)
        }
    }

    private static func shape(_ key: LayoutKey) -> Layout {
        let font = key.font as CTFont
        // These are Core Text attributes with native, immutable CF values.
        // Foreground ink comes from the current context; hover and selection
        // colors can reuse precisely the same glyph runs and line breaks.
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorFromContextAttributeName: kCFBooleanTrue as Any,
            kCTKernAttributeName: NSNumber(value: Double(key.kern))
        ]
        let dictionary = attributes as CFDictionary
        let baseAscent = CTFontGetAscent(font)
        let baseDescent = CTFontGetDescent(font)
        let baseLeading = max(0,CTFontGetLeading(font))
        var rows: [Row] = []
        var y: CGFloat = 0
        var lastLeading: CGFloat = 0
        func append(_ line: CTLine?) {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            if let line { _ = CTLineGetTypographicBounds(line,&ascent,&descent,&leading) }
            ascent = max(baseAscent,ascent)
            descent = max(baseDescent,descent)
            leading = max(baseLeading,leading)
            let baseline = y + ascent
            rows.append(Row(line: line, baseline: baseline))
            y = baseline + descent + leading + key.spacing
            lastLeading = leading
        }
        // Swift recognizes CRLF as one newline, and keeps intentional empty
        // paragraphs in the final letter.
        let paragraphs = key.text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        for paragraph in paragraphs {
            guard !paragraph.isEmpty else { append(nil); continue }
            let string = String(paragraph)
            let attributed = CFAttributedStringCreate(nil,string as CFString,dictionary)!
            if !key.wrap {
                let line = CTLineCreateWithAttributedString(attributed)
                if CTLineGetTypographicBounds(line,nil,nil,nil) <= Double(key.width) {
                    append(line)
                } else {
                    let ellipsis = CFAttributedStringCreate(nil,"…" as CFString,dictionary)!
                    let token = CTLineCreateWithAttributedString(ellipsis)
                    append(CTLineCreateTruncatedLine(line,Double(key.width),.end,token))
                }
                continue
            }
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let length = CFAttributedStringGetLength(attributed)
            let ns = string as NSString
            var start = 0
            while start < length {
                var count = CTTypesetterSuggestLineBreak(typesetter,start,Double(key.width))
                if count == 0 { count = ns.rangeOfComposedCharacterSequence(at:start).length }
                append(CTTypesetterCreateLine(typesetter,CFRange(location:start,length:count)))
                start += count
            }
        }
        return Layout(rows: rows, height: max(0,y-key.spacing-lastLeading))
    }
}
