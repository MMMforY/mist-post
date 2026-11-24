import AppKit
import Darwin

/// Focused regression checks for the HUD's flipped, cached Core Text path.
/// Invoke with Checks/verify-typesetter.sh; the normal QA app has its own entry.
enum TypesetterCheck {
    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL typography \(message)\n", stderr); exit(1) }
    }

    static func run() {
        _ = NSApplication.shared
        let w = 440, h = 180
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let paper = CGRect(x: 0, y: 0, width: w, height: h)
        func measure(_ text: String, rect: CGRect, align: NSTextAlignment, center: Bool,
                     wrap: Bool = false) -> (box: CGRect, bands: Int) {
            P.rect(paper, .white)
            P.text(text, rect, P.serif(18), .black, align: align, wrap: wrap, centerY: center)
            ctx.flush()
            let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
            var loX = w, hiX = -1, loY = h, hiY = -1, bands = 0
            var formerInk = false
            for y in 0..<h {
                var ink = false
                for x in 0..<w where bytes[y*ctx.bytesPerRow + x*4] < 175 {
                    loX = min(loX,x); hiX = max(hiX,x)
                    loY = min(loY,y); hiY = max(hiY,y)
                    ink = true
                }
                if ink && !formerInk { bands += 1 }
                formerInk = ink
            }
            require(hiX >= loX && hiY >= loY,"missing ink for \(text)")
            let box = CGRect(x: loX,y: loY,width: hiX-loX+1,height: hiY-loY+1)
            require(rect.contains(box),"glyphs escaped their clipping rect")
            return (box,bands)
        }
        let bounds = CGRect(x: 27,y: 12,width: 380,height: 68)
        let left = measure("港口",rect: bounds,align: .left,center: true).box
        let middle = measure("港口",rect: bounds,align: .center,center: true).box
        let right = measure("港口",rect: bounds,align: .right,center: true).box
        require(left.minX < bounds.minX+5 && right.maxX > bounds.maxX-6,"horizontal alignment")
        require(abs(middle.midX-bounds.midX) < 3 && abs(middle.midY-bounds.midY) < 5,"centered baseline")
        let paragraph = measure("钟声传到了对岸的小邮局。\n\n请留一盏灯。",rect: CGRect(x: 18,y: 8,width: 104,height: 159),
                                align: .left,center: false,wrap: true)
        require(paragraph.box.height > 70 && paragraph.bands >= 3,"Chinese wrap and blank paragraph")
        _ = measure("MARITIME DELIVERY  /  雾信航局",rect: CGRect(x: 24,y: 35,width: 104,height: 46),
                    align: .left,center: false)

        // The route/clock prefix and alternating alpha force cache churn while
        // the stable labels exercise reuse. Every pass paints to real pixels.
        let start = clock()
        let rounds = 4000
        for i in 0..<rounds {
            autoreleasepool {
                P.rect(paper,P.paper)
                let digit = String(format:"%02d / %02d",i%37,37)
                P.text("潮汐节拍",CGRect(x: 8,y: 4,width: 130,height: 27),P.serif(20,heavy:true),P.graphite)
                P.text(digit,CGRect(x: 152,y: 4,width: 96,height: 27),P.mono(15,.medium),P.teal,align:.center)
                let color = P.ink(0x294F56,CGFloat(1+(i%7))/7)
                P.text("船影 \(i)    离港 · PORT \(i%251)",CGRect(x: 8,y: 39,width: 215,height: 31),
                       P.sans(CGFloat(12+i%7),.medium),color,align: i.isMultiple(of:2) ? .right : .left)
                P.text("下一班邮船到港。请送到灯塔。\n\n静候回音。",CGRect(x: 11,y: 78,width: 136,height: 96),
                       P.serif(15),P.graphite,wrap:true,spacing:2)
                P.text("E  留影   Z  撤回",CGRect(x: 243,y: 38,width: 160,height: 34),
                       P.mono(14,.semibold),P.brick,align:.center,centerY:true)
            }
        }
        ctx.flush()
        let seconds = Double(clock()-start)/Double(CLOCKS_PER_SEC)
        print(String(format:"PASS native HUD text, clipping, CJK, alignment, ellipsis and cache churn; %d draws in %.2f CPU seconds.",rounds*5,seconds))
    }
}
