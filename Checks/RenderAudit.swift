import AppKit

/// Draws to a real Core Graphics surface. Time includes all HUD typesetting and
/// accessibility updates. Writing PNG files is deliberately outside the measurements.
@MainActor
enum RenderAudit {
    static func run(_ v: StationView) -> Never {
        for level in MistCampaign.levels {
            var trip = MistVoyage(level:level)
            for c in level.guide { trip.perform(c) }
            v.store.save(trip)
        }
        let sizes = [(960,600,1),(1200,750,1),(1200,750,2)]
        for (w,h,density) in sizes {
            let ctx = CGContext(data:nil,width:w*density,height:h*density,bitsPerComponent:8,bytesPerRow:0,
                                space:CGColorSpace(name:CGColorSpace.sRGB)!,
                                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.translateBy(x:0,y:CGFloat(h*density))
            ctx.scaleBy(x:CGFloat(density),y:-CGFloat(density))
            v.setFrameSize(NSSize(width:w,height:h))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext:ctx,flipped:true)
            for id in [1,8,12] {
                v.start(id)
                let level = v.voyage.level
                for cmd in level.guide.dropLast(1) { v.operate(cmd) }
                var ms: [Double] = []
                var cold = 0.0
                for i in 0...48 {
                    v.frozenTime = Double(i)/24 + 232
                    let start = ProcessInfo.processInfo.systemUptime
                    autoreleasepool { v.draw(v.bounds); ctx.flush() }
                    let elapsed = (ProcessInfo.processInfo.systemUptime-start)*1000
                    if i == 0 { cold = elapsed }
                    else { ms.append(elapsed) }
                }
                ms.sort()
                var idle: [Double] = []
                for i in 0..<24 {
                    v.frozenTime = 270+Double(i)/8
                    let start = ProcessInfo.processInfo.systemUptime
                    autoreleasepool { v.draw(v.viewRect(v.chartRect)); ctx.flush() }
                    idle.append((ProcessInfo.processInfo.systemUptime-start)*1000)
                }
                idle.sort()
                print(String(format:"display %dx%d@%d route %02d cold %.1f ms median %.2f ms p95 %.2f ms idle %.2f ms",
                             w,h,density,id,cold,ms[ms.count/2],ms[ms.count*95/100],idle[idle.count/2]))
                fflush(stdout)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        exit(0)
    }
}
