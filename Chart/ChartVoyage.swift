import CoreGraphics
import Foundation

extension HarborChart {
    func drawVoyage(_ pen: ChartPen, game: MistVoyage, time: TimeInterval, options: ChartOptions) {
        let inspected = options.previewBeat
        let beat = max(0, inspected ?? game.beat)
        let t: CGFloat = options.reduceMotion ? 0 : CGFloat(time.truncatingRemainder(dividingBy:60000))
        let blend: CGFloat
        if !options.reduceMotion, inspected == nil, let started = options.motionStartedAt {
            let f = CGFloat(min(1,max(0,(time-started)/0.22)))
            blend = f*f*(3-2*f)
        } else { blend=1 }

        let harbor = game.level.harbor
        let allStamps = game.stamped == game.level.stamps
        if allStamps {
            let lamp = chartPoint(CGFloat(harbor.x)+0.5,CGFloat(harbor.y)+0.18)
            pen.placed(at:lamp,angle:.pi+sin(t*0.32)*0.34) {
                pen.saved {
                    let ctx = pen.ctx
                    ctx.beginPath()
                    ctx.move(to:.zero); ctx.addLine(to:chartPoint(1.65,-0.155)); ctx.addLine(to:chartPoint(1.65,0.16)); ctx.closePath()
                    ctx.clip()
                    let inks = [ChartInk.amber.chartAlpha(options.highContrast ? 0.48 : 0.37),
                                ChartInk.amber.chartAlpha(0)] as CFArray
                    if let grad = CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:inks,locations:[0,1]) {
                        ctx.drawLinearGradient(grad,start:.zero,end:chartPoint(1.65,0),options:[])
                    }
                }
            }
        }

        if let hover = options.hoverPoint, inspected == nil,
           abs(hover.x-game.position.x)+abs(hover.y-game.position.y) == 1 && !game.delivered {
            let legal = game.obstruction(at:hover,arrivingAt:game.beat+1,with:game.stamped) == nil
            brackets(pen,at:hover,ink:legal ? ChartInk.bright : ChartInk.red,r:0.38,width:0.027)
        }
        for point in options.signalStations {
            brackets(pen,at:point,ink:ChartInk.amber,r:0.45,width:0.054)
        }
        if let hint=options.hintPoint {
            brackets(pen,at:hint,ink:ChartInk.amber,r:0.408,width:0.045)
        }
        let echoPoints = game.echoPositions(at:beat)
        for pt in Set(echoPoints) {
            if case .buoy = game.level.tile(at:pt) {
                let phase = options.reduceMotion ? 0.3 : (t*0.47).truncatingRemainder(dividingBy:1)
                ring(pen,at:chartPoint(CGFloat(pt.x)+0.5,CGFloat(pt.y)+0.5),ink:ChartInk.amber,phase:phase)
            }
        }
        let departure = departureBearing(level:game.level)
        let liveHeading = bearing(game.path,index:game.beat,departure:departure)
        for (i,route) in game.echoes.enumerated() {
            let pos = echoPoints[i]
            let index = min(beat,route.count-1)
            let prior = route[min(max(0,beat-1),route.count-1)]
            var location = interpolate(from:prior,to:pos,fraction:blend)
            var size: CGFloat = 0.72
            if pos == game.position {
                // Berth alongside the live steamer, perpendicular to its hull.
                // Two ghosts at the same dock are consequently both visible.
                let side: CGFloat = i == 0 ? 0.244 : -0.244
                location.x += side*cos(liveHeading)-0.035*sin(liveHeading)
                location.y += side*sin(liveHeading)+0.035*cos(liveHeading)
                size = 0.58
            } else if echoPoints.filter({ $0 == pos }).count > 1 || game.level.tile(at:pos) != .water {
                location.x += i == 0 ? -0.195 : 0.185
                location.y += i == 0 ? 0.115 : -0.11
            }
            pen.placed(at:location,scale:size,angle:bearing(route,index:index,departure:departure)) {
                pen.mailboat(echo:i == 0 ? ChartInk.echo : ChartInk.echoTwo)
            }
        }

        let prev = game.path[max(0,game.path.count-2)]
        let loc = interpolate(from:prev,to:game.position,fraction:blend)
        pen.saved {
            if inspected != nil { pen.ctx.setAlpha(0.47) }
            pen.placed(at:loc,angle:liveHeading) {
                for side: CGFloat in [-1,1] {
                    let sway = 0.014*(0.5+0.5*sin(t*1.6+side))
                    pen.curve(stroke:ChartInk.mist.chartAlpha(0.66),width:0.015) { p in
                        p.move(to:chartPoint(side*(0.207+sway),-0.14))
                        p.addQuadCurve(to:chartPoint(side*(0.215+sway),0.094),
                                       control:chartPoint(side*(0.242+sway),-0.039))
                    }
                }
                if blend < 1 && game.position != prev {
                    for side: CGFloat in [-1,1] {
                        pen.curve(stroke:ChartInk.mist.chartAlpha((1-blend)*0.8),width:0.029) { p in
                            p.move(to:chartPoint(side*0.11,0.23))
                            p.addQuadCurve(to:chartPoint(side*0.265,0.49),
                                           control:chartPoint(side*0.18,0.42))
                        }
                    }
                }
                pen.mailboat()
            }
            if inspected == nil {
                let wind = options.reduceMotion ? 0.4 : (t*0.53).truncatingRemainder(dividingBy:1)
                for n in 0..<3 {
                    let age = (wind+CGFloat(n)/3).truncatingRemainder(dividingBy:1)
                    let x = loc.x-0.21*age+0.018*sin(age*5), y = loc.y-0.30*age
                    let radius = 0.016+age*0.041
                    pen.oval(x-radius,y-radius*0.68,2*radius,radius*1.36,
                             ChartInk.bright.chartAlpha(0.42*(1-age)))
                }
            }
        }
    }

    /// Base navigation marks depend on a turn and its inspected beat. They
    /// are printed together at the final pixel size, avoiding texture blur.
    func drawSignage(_ pen: ChartPen, game: MistVoyage, options: ChartOptions, cellHeight: CGFloat) {
        let inspected = options.previewBeat
        let beat = max(0,inspected ?? game.beat)
        let gateBeat = inspected == nil ? beat+1 : beat
        let allStamps = game.stamped == game.level.stamps
        let badgeScale = max(1,min(1.48,42/max(1,cellHeight))) * (options.highContrast ? 1.09 : 1)
        if options.showTrails {
            for (index, route) in game.echoes.enumerated() {
                let ink = index == 0 ? ChartInk.echo : ChartInk.echoTwo
                drawTrack(pen,route:route,ink:ink,echoIndex:index,contrast:options.highContrast)
            }
            drawTrack(pen,route:game.path,ink:ChartInk.amber,echoIndex:nil,contrast:options.highContrast)
        }
        if inspected == nil && !game.delivered && game.beat < game.level.turnLimit {
            for move in [MistMove.north,.east,.south,.west] {
                let pt = game.position.moved(move)
                guard game.obstruction(at:pt,arrivingAt:game.beat+1,with:game.stamped) == nil else { continue }
                let dx=CGFloat(pt.x-game.position.x), dy=CGFloat(pt.y-game.position.y)
                let center = chartPoint(CGFloat(game.position.x)+0.5+dx*0.53,CGFloat(game.position.y)+0.5+dy*0.53)
                pen.placed(at:center,angle:atan2(dy,dx)) {
                    pen.poly([chartPoint(-0.042,-0.054),chartPoint(0.025,0),chartPoint(-0.042,0.054)],
                             nil,stroke:ChartInk.bright.chartAlpha(options.highContrast ? 1 : 0.80),
                             width:0.028,closed:false)
                }
            }
        }

        for y in 0..<game.level.height {
            for x in 0..<game.level.width {
                let pt = MistPoint(x:x,y:y)
                let tile = game.level.tile(at:pt)
                guard tile != .land && tile != .water else { continue }
                pen.placed(at:chartPoint(CGFloat(x)+0.5,CGFloat(y)+0.5)) {
                    switch tile {
                    case .origin: pen.originDock()
                    case .harbor: pen.lighthouse(ready:allStamps,phase:0.8)
                    case .stamp: pen.stampKiosk(collected:game.stamped.contains(pt))
                    case .buoy(let id):
                        let lit=game.gateOpen(id,at:beat)
                        pen.bellBuoy(group:id,lit:lit,plaqueScale:badgeScale)
                    case .gate(let id):
                        let widen = [(-1,0),(1,0)].filter { game.level.tile(at:.init(x:x+$0.0,y:y+$0.1)) != .land }.count
                        let deepen = [(0,-1),(0,1)].filter { game.level.tile(at:.init(x:x+$0.0,y:y+$0.1)) != .land }.count
                        pen.lockGate(group:id,open:game.gateOpen(id,at:gateBeat),acrossX:deepen > widen,plaqueScale:badgeScale)
                    default: break
                    }
                }
            }
        }

    }

    private func drawTrack(_ pen: ChartPen, route: [MistPoint], ink: CGColor, echoIndex: Int?, contrast: Bool) {
        guard route.count > 1 else { return }
        let offset: CGFloat
        switch echoIndex { case 0:offset = -0.057; case 1:offset = 0.068; default:offset = 0 }
        let trail = CGMutablePath()
        func shifted(_ pt: MistPoint) -> CGPoint { chartPoint(CGFloat(pt.x)+0.5+offset,CGFloat(pt.y)+0.5+offset) }
        trail.move(to:shifted(route[0]))
        var previous = route[0]
        var waits: Set<MistPoint> = []
        for pt in route.dropFirst() {
            if pt != previous { trail.addLine(to:shifted(pt)) }
            else { waits.insert(pt) }
            previous = pt
        }
        pen.path(trail,stroke:ChartInk.coal.chartAlpha(0.45),width:0.064)
        pen.saved {
            if let i=echoIndex { pen.ctx.setLineDash(phase:0,lengths:i == 0 ? [0.10,0.062] : [0.035,0.046]) }
            pen.path(trail,stroke:ink.chartAlpha(contrast ? 1 : 0.82),width:echoIndex == nil ? 0.046 : 0.035)
        }
        for pt in waits {
            let p=shifted(pt)
            pen.oval(p.x-0.084,p.y-0.084,0.168,0.168,nil,stroke:ink.chartAlpha(0.85),width:0.024)
        }
        if echoIndex != nil, let last=route.last {
            let end = shifted(last)
            pen.oval(end.x-0.080,end.y-0.080,0.16,0.16,ChartInk.sea,stroke:ink,width:0.024)
        }
    }

    private func interpolate(from: MistPoint, to: MistPoint, fraction: CGFloat) -> CGPoint {
        chartPoint(CGFloat(from.x)+0.5+CGFloat(to.x-from.x)*fraction,
                   CGFloat(from.y)+0.5+CGFloat(to.y-from.y)*fraction)
    }

    private func departureBearing(level: MistLevel) -> CGFloat {
        let neighbors = [MistMove.east,.north,.south,.west].map { level.origin.moved($0) }
        let water = neighbors.filter { pt in
            switch level.tile(at:pt) { case .land,.gate: return false; default: return true }
        }
        // A dock always faces an adjacent channel, including rotated surveys.
        guard let first=water.min(by: { lhs,rhs in
            let harbor=level.harbor
            return abs(lhs.x-harbor.x)+abs(lhs.y-harbor.y) < abs(rhs.x-harbor.x)+abs(rhs.y-harbor.y)
        }) else { return .pi/2 }
        return atan2(CGFloat(first.x-level.origin.x),CGFloat(level.origin.y-first.y))
    }

    private func bearing(_ path: [MistPoint], index: Int, departure: CGFloat) -> CGFloat {
        let pt = path[index]
        if index > 0 {
            for i in (0..<index).reversed() where path[i] != pt {
                return atan2(CGFloat(pt.x-path[i].x),CGFloat(path[i].y-pt.y))
            }
        }
        // A recorded route already knows which way its first leg sailed.
        if index+1 < path.count, let next=path[(index+1)...].first(where:{ $0 != pt }) {
            return atan2(CGFloat(next.x-pt.x),CGFloat(pt.y-next.y))
        }
        return departure
    }

    private func ring(_ pen: ChartPen, at p: CGPoint, ink: CGColor, phase: CGFloat) {
        let r = 0.20+0.23*phase
        pen.oval(p.x-r,p.y-r*0.48+0.15,2*r,r*0.96,nil,stroke:ink.chartAlpha(0.69*(1-phase)),width:0.022)
    }

    private func brackets(_ pen: ChartPen, at point: MistPoint, ink: CGColor, r: CGFloat, width: CGFloat) {
        pen.placed(at:chartPoint(CGFloat(point.x)+0.5,CGFloat(point.y)+0.5)) {
            for sx: CGFloat in [-1,1] {
                for sy: CGFloat in [-1,1] {
                    let c=chartPoint(sx*r,sy*r)
                    let pts=[chartPoint(sx*(r-0.145),sy*r),c,chartPoint(sx*r,sy*(r-0.145))]
                    pen.poly(pts,nil,stroke:ChartInk.coal,width:width+0.029,closed:false)
                    pen.poly(pts,nil,stroke:ink,width:width,closed:false)
                }
            }
        }
    }
}
