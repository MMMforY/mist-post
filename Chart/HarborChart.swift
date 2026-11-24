import AppKit

struct ChartOptions {
    var showTrails = true
    var reduceMotion = false
    var highContrast = false
    var hintPoint: MistPoint?
    var signalStations: [MistPoint] = []
    var hoverPoint: MistPoint?
    /// The clock domain must match `time`. Nil draws a settled board.
    var motionStartedAt: TimeInterval?
    /// Inspect a future echo beat while leaving the live vessel in place.
    var previewBeat: Int?
}

private struct ChartLayout {
    let frame: CGRect
    let board: CGRect
    let sx: CGFloat
    let sy: CGFloat

    init(frame: CGRect, level: MistLevel) {
        self.frame = frame
        let insetX = min(35, max(3, frame.width*0.046))
        let insetY = min(30, max(3, frame.height*0.073))
        let availW = max(0.1, frame.width-2*insetX)
        let availH = max(0.1, frame.height-2*insetY)
        let square = min(availW/CGFloat(level.width),availH/CGFloat(level.height))
        sx = min(availW/CGFloat(level.width),square*1.23)
        sy = square
        let w = sx*CGFloat(level.width), h = sy*CGFloat(level.height)
        board = CGRect(x:frame.midX-w/2,y:frame.midY-h/2,width:w,height:h)
    }
    var visible: CGRect {
        CGRect(x:(frame.minX-board.minX)/sx,y:(frame.minY-board.minY)/sy,
               width:frame.width/sx,height:frame.height/sy)
    }
    func at(_ p: MistPoint) -> CGPoint {
        chartPoint(board.minX+(CGFloat(p.x)+0.5)*sx,board.minY+(CGFloat(p.y)+0.5)*sy)
    }
    func inMap(_ pen: ChartPen, draw: () -> Void) {
        pen.saved {
            pen.ctx.translateBy(x:board.minX,y:board.minY)
            pen.ctx.scaleBy(x:sx,y:sy)
            draw()
        }
    }
}

/// All methods take coordinates in their host's flipped AppKit view. Use the
/// same chart rect for painting and hit testing, including a nonzero origin.
final class HarborChart {
    private struct PlateKey: Equatable {
        let route: Int
        let size: CGSize
        let scale: CGFloat
        let contrast: Bool
    }
    private struct NavigationKey: Equatable {
        let plate: PlateKey
        let history: [MistCommand]
        let turnLimit: Int
        let preview: Int?
        let trails: Bool
    }
    private var navKey: NavigationKey?
    private var navPlate: CGImage?
    private var coastRoute: Int?
    private var coast: ChartCoast?
    private var plateKey: PlateKey?
    private var plate: CGImage?

    func center(of point: MistPoint, in rect: NSRect, game: MistVoyage) -> NSPoint {
        ChartLayout(frame:rect,level:game.level).at(point)
    }

    func cell(at p: NSPoint, in rect: NSRect, game: MistVoyage) -> MistPoint? {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
              p.x.isFinite, p.y.isFinite, rect.contains(p) else { return nil }
        let l = ChartLayout(frame:rect,level:game.level)
        let x = Int(floor((p.x-l.board.minX)/l.sx)), y = Int(floor((p.y-l.board.minY)/l.sy))
        guard (0..<game.level.width).contains(x), (0..<game.level.height).contains(y) else { return nil }
        return MistPoint(x:x,y:y)
    }

    func draw(in rect: NSRect, game: MistVoyage, time: TimeInterval,
              options: ChartOptions = .init()) {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 1, rect.height > 1,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        let pen = ChartPen(ctx:ctx)
        pen.saved {
            ctx.clip(to:rect)
            ctx.setLineDash(phase:0,lengths:[])
            ctx.translateBy(x:rect.minX,y:rect.minY)
            let local = CGRect(origin:.zero,size:rect.size)
            let layout = ChartLayout(frame:local,level:game.level)
            // Half-step backing tiers avoid rebuilding the full survey for
            // every fractional zoom during a live window resize.
            let scale = max(1,min(3,ceil(hypot(ctx.ctm.a,ctx.ctm.b)*2)/2))
            let route = signature(game.level)
            let key = PlateKey(route:route,size:rect.size,scale:scale,contrast:options.highContrast)
            if coastRoute != route || coast == nil {
                coast = ChartCoast(level:game.level)
                coastRoute = route
            }
            guard let coast else { return }
            if key != plateKey {
                plate = makeImage(layout:layout,scale:scale) { ink in
                    drawPlate(ink,level:game.level,coast:coast,layout:layout,contrast:options.highContrast)
                }
                plateKey = key
            }
            let turn = NavigationKey(plate:key,history:game.history,turnLimit:game.level.turnLimit,
                                     preview:options.previewBeat,trails:options.showTrails)
            func paintNavigation(_ ink: ChartPen) {
                if let plate { drawImage(plate,using:ink,in:local) }
                else { drawPlate(ink,level:game.level,coast:coast,layout:layout,contrast:options.highContrast) }
                ink.ctx.setLineCap(.round)
                ink.ctx.setLineJoin(.round)
                layout.inMap(ink) { drawSignage(ink,game:game,options:options,cellHeight:layout.sy) }
            }
            if navKey != turn {
                navPlate = makeImage(layout:layout,scale:scale,paint:paintNavigation)
                navKey = turn
            }
            if let navPlate { drawImage(navPlate,using:pen,in:local) }
            else { paintNavigation(pen) }
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            layout.inMap(pen) { drawVoyage(pen,game:game,time:time,options:options) }
        }
    }

    func drawKey(_ tile: MistTile, in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let pen = ChartPen(ctx:ctx)
        pen.placed(at:chartPoint(rect.midX,rect.midY),scale:min(rect.width,rect.height)*1.03) {
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            switch tile {
            case .origin: pen.originDock()
            case .harbor: pen.lighthouse(ready:true,phase:0.5)
            case .stamp: pen.stampKiosk(collected:false)
            case .buoy(let id): pen.bellBuoy(group:id,lit:false)
            case .gate(let id): pen.lockGate(group:id,open:false,acrossX:true)
            case .water:
                pen.line(-0.28,0,0.28,0,ChartInk.mist,0.024)
                pen.oval(-0.060,-0.060,0.12,0.12,ChartInk.sea,stroke:ChartInk.paper,width:0.027)
            case .land:
                pen.poly([chartPoint(-0.33,0.12),chartPoint(-0.12,-0.17),chartPoint(0.13,-0.23),
                          chartPoint(0.31,0.048),chartPoint(0.21,0.17),chartPoint(-0.14,0.2)],
                         ChartInk.ochre,stroke:ChartInk.ink,width:0.038)
            }
        }
    }

    func drawBoatKey(in rect: NSRect, echo: Bool = false) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let pen = ChartPen(ctx:ctx)
        pen.placed(at:chartPoint(rect.midX,rect.midY),scale:min(rect.width,rect.height)*1.03,angle:.pi/4) {
            pen.mailboat(echo:echo ? ChartInk.echo : nil)
        }
    }

    private func signature(_ level: MistLevel) -> Int {
        var s = level.id &* 73 &+ level.width &* 43 &+ level.height
        for y in 0..<level.height {
            for x in 0..<level.width {
                let value: Int
                switch level.tile(at:.init(x:x,y:y)) {
                case .water: value=1
                case .land: value=2
                case .origin: value=3
                case .harbor: value=4
                case .stamp: value=5
                case .buoy(let i): value=6+i*2
                case .gate(let i): value=7+i*2
                }
                s = s &* 31 &+ value
            }
        }
        return s
    }

    /// Quartz images are y-up; chart geometry and the host view are y-down.
    private func drawImage(_ image: CGImage, using pen: ChartPen, in rect: CGRect) {
        pen.saved {
            pen.ctx.translateBy(x:rect.minX,y:rect.maxY)
            pen.ctx.scaleBy(x:1,y:-1)
            pen.ctx.setBlendMode(.copy)
            pen.ctx.interpolationQuality = .low
            pen.ctx.draw(image,in:CGRect(origin:.zero,size:rect.size))
        }
    }

    private func makeImage(layout: ChartLayout, scale: CGFloat,
                           paint: (ChartPen)->Void) -> CGImage? {
        let width = ceil(layout.frame.width*scale), height = ceil(layout.frame.height*scale)
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { return nil }
        let w = Int(width), h = Int(height)
        guard let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,
                                  space:CGColorSpace(name:CGColorSpace.sRGB)!,
                                  bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.translateBy(x:0,y:CGFloat(h))
        ctx.scaleBy(x:CGFloat(w)/layout.frame.width,y:-CGFloat(h)/layout.frame.height)
        paint(ChartPen(ctx:ctx))
        return ctx.makeImage()
    }

    private func drawPlate(_ pen: ChartPen, level: MistLevel, coast: ChartCoast,
                           layout: ChartLayout, contrast: Bool) {
        let f = layout.frame, ctx = pen.ctx
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let region = ChartRegion.forLevel(level)
        let colors = [region.water,region.deep] as CFArray
        if let gradient = CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:colors,locations:[0,1]) {
            ctx.drawRadialGradient(gradient,startCenter:chartPoint(f.midX*0.85,f.midY*0.69),
                                   startRadius:0,endCenter:chartPoint(f.midX,f.midY),endRadius:max(f.width,f.height)*0.76,
                                   options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
        } else { pen.rect(0,0,f.width,f.height,ChartInk.sea) }
        layout.inMap(pen) { pen.terrain(level:level,coast:coast,visible:layout.visible,contrast:contrast) }
        ChartGrain.apply(to:ctx)
        drawEdges(pen,layout:layout,level:level,contrast:contrast)
    }

    private func drawEdges(_ p: ChartPen, layout l: ChartLayout, level: MistLevel, contrast: Bool) {
        let f=l.frame, b=l.board
        let faint = ChartInk.mist.chartAlpha(contrast ? 0.53 : 0.31)
        let type = ChartInk.paper.chartAlpha(contrast ? 0.96 : 0.75)
        let inset: CGFloat = max(4,min(9,f.height*0.026))
        p.rect(inset,inset,f.width-2*inset,f.height-2*inset,nil,stroke:faint,width:0.7)
        let labelSize = max(6,min(9,l.sy*0.2))
        for x in 0..<level.width {
            let px = b.minX+(CGFloat(x)+0.5)*l.sx
            p.line(px,inset,px,inset+4,faint,0.85)
            p.line(px,f.maxY-inset,px,f.maxY-inset-4,faint,0.85)
            if l.sy >= 20 && b.minY-inset >= labelSize*1.6 {
                let letter = String(UnicodeScalar(65+x%26)!)
                p.text(letter,centeredAt:chartPoint(px,(inset+b.minY)*0.5),size:labelSize,color:type)
            }
        }
        for y in 0..<level.height {
            let py = b.minY+(CGFloat(y)+0.5)*l.sy
            p.line(inset,py,inset+4,py,faint,0.85)
            p.line(f.maxX-inset,py,f.maxX-inset-4,py,faint,0.85)
            if l.sy >= 20 && b.minX-inset >= labelSize*1.6 {
                p.text(String(y+1),centeredAt:chartPoint(inset+min(16,(b.minX-inset)*0.55),py),size:labelSize,color:type)
            }
        }
        if b.minX > 67 && f.height > 150 {
            let x = max(34,b.minX*0.49), y = f.minY+48
            p.placed(at:chartPoint(x,y)) {
                p.oval(-12,-12,24,24,nil,stroke:faint,width:0.6)
                p.line(-16,0,16,0,faint,0.7); p.line(0,-19,0,16,faint,0.7)
                p.poly([chartPoint(0,-16),chartPoint(3.7,4),chartPoint(0,0)],ChartInk.paper.chartAlpha(0.72))
                p.poly([chartPoint(0,-16),chartPoint(-3.7,4),chartPoint(0,0)],ChartInk.mist.chartAlpha(0.36))
                p.text("N",centeredAt:chartPoint(0,-24),size:8,color:type)
            }
        }
    }
}
