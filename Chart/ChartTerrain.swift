import CoreGraphics
import Foundation

extension ChartPen {
    func terrain(level: MistLevel, coast: ChartCoast, visible: CGRect, contrast: Bool) {
        let seed = level.id &* 149 &+ level.width &* 37 &+ level.height
        let region = ChartRegion.forLevel(level)
        var random = SurveySeed(seed)
        let contours = coast.contours
        // Semi-transparent shallow plates carry the underlying deep water tone.
        for (depth, opacity): (CGFloat, CGFloat) in [(1.08,0.075),(0.72,0.075),(0.43,0.11),(0.25,0.15),(0.14,0.18)] {
            if let p = contours[depth] { path(p, fill:region.shoal.chartAlpha(opacity)) }
        }
        let waves = Int(min(600,visible.width*visible.height*2.3))
        for _ in 0..<waves {
            let x = visible.minX + random.next()*visible.width
            let y = visible.minY + random.next()*visible.height
            let width = 0.065+pow(random.next(),2)*0.33, lift = random.next()*0.032
            let alpha = 0.065+random.next()*0.14
            curve(stroke:ChartInk.mist.chartAlpha(alpha),width:0.010) { p in
                p.move(to:chartPoint(x-width*0.5,y))
                p.addQuadCurve(to:chartPoint(x+width*0.5,y-lift*0.6),control:chartPoint(x,y+lift))
            }
            if width > 0.29 { line(x+width*0.03,y+0.028,x+width*0.32,y+0.028,ChartInk.mist.chartAlpha(alpha*0.7),0.009) }
        }
        weatherMarks(region:region,visible:visible,seed:seed)
        for depth: CGFloat in [0.14,0.25,0.43,0.72,1.08] {
            if let p = contours[depth] {
                let alpha: CGFloat = depth < 0.3 ? 0.30 : (depth < 0.6 ? 0.20 : 0.105)
                path(p,stroke:ChartInk.mist.chartAlpha(alpha),width:depth < 0.3 ? 0.011 : 0.009)
            }
        }
        // Route marks follow only real orthogonal connections. An empty square
        // gets a visible center, but no painted box competes with the coast.
        for y in 0..<level.height {
            for x in 0..<level.width {
                let loc = MistPoint(x:x,y:y), tile = level.tile(at:loc)
                guard tile != .land else { continue }
                let cx = CGFloat(x)+0.5, cy = CGFloat(y)+0.5
                for (dx,dy) in [(1,0),(0,1)] where level.tile(at:.init(x:x+dx,y:y+dy)) != .land {
                    saved {
                        ctx.setLineDash(phase:0,lengths:[0.023,0.073])
                        line(cx,cy,cx+CGFloat(dx),cy+CGFloat(dy),
                             ChartInk.paper.chartAlpha(contrast ? 0.68 : 0.43),contrast ? 0.024 : 0.018)
                    }
                }
                if tile == .water {
                    oval(cx-0.038,cy-0.038,0.076,0.076,ChartInk.sea,stroke:ChartInk.mist.chartAlpha(contrast ? 0.9 : 0.64),width:0.020)
                }
            }
        }
        guard let land = contours[0] else { return }
        saved {
            ctx.translateBy(x:0.024,y:region.relief+0.018)
            path(land,fill:ChartInk.ink.chartAlpha(0.82),stroke:ChartInk.mist.chartAlpha(0.42),width:0.026)
        }
        saved {
            ctx.translateBy(x:0.008,y:region.relief)
            path(land,fill:ChartInk.shadow,stroke:ChartInk.ink,width:0.018)
        }
        if region.district == .cliffs {
            // Strata appear on the seaward face. Painting them beneath the
            // top plate keeps the actual land footprint and route centers clear.
            for h: CGFloat in [0.029,0.068,0.098] {
                saved {
                    ctx.translateBy(x:0.008,y:h)
                    path(land,stroke:ChartInk.paper.chartAlpha(0.55),width:0.010)
                }
            }
        }
        path(land,fill:region.beach,stroke:ChartInk.ink,width:contrast ? 0.041 : 0.027)
        if let upland = contours[-0.075] {
            path(upland,fill:region.land,stroke:ChartInk.shadow.chartAlpha(0.54),width:0.012)
        }
        if let scarp = contours[-0.24] {
            path(scarp,fill:region.upland.chartAlpha(0.40),stroke:ChartInk.stone.chartAlpha(0.60),width:0.011)
        }
        for depth: CGFloat in [-0.38,-0.54] {
            if let ridge=contours[depth] {
                path(ridge,fill:ChartInk.stone.chartAlpha(0.08),stroke:ChartInk.shadow.chartAlpha(0.16),width:0.008)
            }
        }
        path(coast.bankHatching,stroke:ChartInk.shadow.chartAlpha(0.47),width:0.009)
        let site = landmarkSite(in:level,land:coast.headlands)
        saved {
            ctx.addPath(land)
            ctx.clip(using:.evenOdd)
            for p in coast.headlands {
                let x = CGFloat(p.x), y = CGFloat(p.y)
                var rng = SurveySeed((p.x+37)*8943 &+ (p.y+11)*3167 &+ seed)
                // Small broken dry-brush marks follow the long shore wind.
                for _ in 0..<16 {
                    let xx = x+rng.next()*1.2-0.1, yy = y+rng.next()*1.2-0.1
                    let len = 0.025+rng.next()*0.09
                    line(xx,yy,xx+len,yy-len*0.26,ChartInk.shadow.chartAlpha(0.15+rng.next()*0.28),0.009)
                }
                // Buildings and maritime pines occupy different, deterministic
                // patches. The geography remains recognizable on every visit.
                if p == site { continue }
                let f = rng.next()
                let location = chartPoint(x+0.34+rng.next()*0.31,y+0.35+rng.next()*0.29)
                let byPort = [level.harbor,level.origin].contains { abs($0.x-p.x)+abs($0.y-p.y) == 1 }
                let nearLandmark = site.map { abs($0.x-p.x)+abs($0.y-p.y) == 1 } ?? false
                if f > 0.895 || (byPort && !nearLandmark && f > 0.54) {
                    placed(at:location,scale:0.55+rng.next()*0.32,angle:(rng.next()-0.5)*0.12) {
                        boathouse(redRoof:byPort || f > 0.95)
                    }
                    if f > 0.943 {
                        placed(at:chartPoint(location.x-0.22,location.y+0.14),scale:0.42) { boathouse(redRoof:false) }
                    }
                } else if f > 0.40 && f < 0.62 {
                    placed(at:location,scale:0.68+rng.next()*0.24) {
                        switch region.district {
                        case .salt: saltern()
                        case .yard: boatyardRails()
                        case .cliffs: cliffSpurs()
                        }
                    }
                } else if f > (region.district == .cliffs ? 0.74 : 0.67) {
                    let count = 2+Int(rng.next()*3)
                    for i in 0..<count {
                        let dx = (rng.next()-0.5)*0.44, dy = CGFloat(i)*0.042
                        placed(at:chartPoint(location.x+dx,location.y+dy),scale:0.50+rng.next()*0.72) { maritimePine() }
                    }
                } else if f < (region.district == .cliffs ? 0.30 : 0.14) {
                    placed(at:location,scale:0.50+rng.next()*0.52) { rockOutcrop() }
                    if f < 0.056 {
                        placed(at:chartPoint(location.x-0.16,location.y+0.10),scale:0.36) { rockOutcrop() }
                    }
                } else {
                    for _ in 0..<(2+Int(rng.next()*3)) {
                        let gx=x+0.2+rng.next()*0.6, gy=y+0.24+rng.next()*0.51
                        let len=0.025+rng.next()*0.042, ink=ChartInk.shadow.chartAlpha(0.49)
                        line(gx-0.018,gy,gx-0.043,gy-len,ink,0.011)
                        line(gx,gy-0.004,gx+0.014,gy-len*1.48,ink,0.011)
                        line(gx+0.014,gy,gx+0.047,gy-len*0.81,ink,0.010)
                    }
                }
            }
            if let site {
                placed(at:chartPoint(CGFloat(site.x)+0.5,CGFloat(site.y)+0.54),scale:1.05) {
                    localLandmark(route:level.id)
                }
            }
        }
    }

    private func landmarkSite(in level: MistLevel, land: [MistPoint]) -> MistPoint? {
        // Prefer a coastal town with land behind it and some room on either
        // side. Fixed coordinate tie-breaks keep each map reproducible.
        let tx = CGFloat(level.width)*(0.24+CGFloat(level.id%4)*0.145)
        let ty = CGFloat(level.height)*0.48
        func weight(_ point: MistPoint) -> CGFloat {
            let neighbors = [MistMove.north,.south,.east,.west].map { point.moved($0) }
            let enclosed = neighbors.filter { p in
                p.x >= 0 && p.y >= 0 && p.x < level.width && p.y < level.height && level.tile(at:p) == .land
            }.count
            return CGFloat(min(3,enclosed))*1.32-abs(CGFloat(point.x)-tx)*0.44-abs(CGFloat(point.y)-ty)*0.51
        }
        return land.max { weight($0) < weight($1) }
    }

    private func rockOutcrop() {
        let stone = ChartInk.stone
        poly([chartPoint(-0.23,0.08),chartPoint(-0.14,-0.026),chartPoint(-0.055,-0.058),
              chartPoint(0.02,-0.178),chartPoint(0.11,-0.194),chartPoint(0.22,0.021),
              chartPoint(0.07,0.078)],stone.chartAlpha(0.9),stroke:ChartInk.shadow,width:0.013)
        poly([chartPoint(-0.055,-0.058),chartPoint(0.02,-0.178),chartPoint(0.11,-0.194),
              chartPoint(0.028,-0.07),chartPoint(-0.08,0.043)],ChartInk.paper)
        for i in 0..<4 {
            let x=CGFloat(i)*0.035
            line(0.06+x,-0.08+x,0.015+x,0.014+x,ChartInk.shadow,0.010)
        }
        line(-0.26,0.12,-0.12,0.095,ChartInk.shadow,0.013)
    }

    func boathouse(redRoof: Bool) {
        poly([chartPoint(-0.26,0.067),chartPoint(0.08,0.155),chartPoint(0.31,0.076),
              chartPoint(-0.036,-0.004)],ChartInk.shadow.chartAlpha(0.28))
        poly([chartPoint(-0.24,-0.112),chartPoint(0.075,-0.035),chartPoint(0.075,0.122),
              chartPoint(-0.24,0.045)],ChartInk.ochre,stroke:ChartInk.ink,width:0.015)
        poly([chartPoint(0.075,-0.035),chartPoint(0.191,-0.12),chartPoint(0.25,-0.066),
              chartPoint(0.25,0.039),chartPoint(0.075,0.122)],ChartInk.paper,stroke:ChartInk.ink,width:0.017)
        let roof = redRoof ? ChartInk.roof : ChartInk.shadow
        poly([chartPoint(-0.273,-0.109),chartPoint(-0.141,-0.229),chartPoint(0.203,-0.153),
              chartPoint(0.075,-0.027)],roof,stroke:ChartInk.ink,width:0.018)
        poly([chartPoint(-0.141,-0.229),chartPoint(-0.070,-0.22),chartPoint(0.273,-0.074),
              chartPoint(0.204,-0.151)],ChartInk.ink,stroke:ChartInk.ink,width:0.013)
        for i in 0..<6 {
            let x=CGFloat(i)*0.048
            line(-0.199+x,-0.097+x*0.23,-0.102+x,-0.191+x*0.23,ChartInk.paper.chartAlpha(0.36),0.010)
        }
        for i in 0..<3 {
            let x=CGFloat(i)*0.085
            poly([chartPoint(-0.188+x,-0.063+x*0.23),chartPoint(-0.15+x,-0.054+x*0.23),
                  chartPoint(-0.15+x,0.015+x*0.23),chartPoint(-0.188+x,0.005+x*0.23)],ChartInk.ink)
        }
        poly([chartPoint(0.143,0.013),chartPoint(0.192,-0.01),chartPoint(0.192,0.063),
              chartPoint(0.143,0.086)],ChartInk.shadow)
        rect(-0.078,-0.265,0.04,0.080,ChartInk.stone,stroke:ChartInk.ink,width:0.011)
    }

    private func maritimePine() {
        line(-0.034,0.108,0.009,-0.158,ChartInk.ink,0.023)
        line(-0.003,-0.033,0.087,-0.087,ChartInk.ink,0.014)
        line(0,-0.075,-0.102,-0.128,ChartInk.ink,0.012)
        let green = ChartInk.shadow
        curve(fill:green,stroke:ChartInk.ink,width:0.012) { p in
            p.move(to:chartPoint(-0.194,-0.102))
            p.addQuadCurve(to:chartPoint(-0.088,-0.157),control:chartPoint(-0.176,-0.148))
            p.addQuadCurve(to:chartPoint(-0.036,-0.212),control:chartPoint(-0.09,-0.184))
            p.addQuadCurve(to:chartPoint(0.083,-0.194),control:chartPoint(0.017,-0.240))
            p.addQuadCurve(to:chartPoint(0.152,-0.159),control:chartPoint(0.139,-0.185))
            p.addLine(to:chartPoint(0.033,-0.147))
            p.addQuadCurve(to:chartPoint(0.176,-0.08),control:chartPoint(0.122,-0.139))
            p.addQuadCurve(to:chartPoint(0.070,-0.076),control:chartPoint(0.108,-0.061))
            p.addLine(to:chartPoint(0.020,-0.101))
            p.addQuadCurve(to:chartPoint(-0.055,-0.070),control:chartPoint(-0.025,-0.059))
            p.addLine(to:chartPoint(-0.07,-0.096))
            p.closeSubpath()
        }
        line(-0.112,-0.135,-0.066,-0.145,ChartInk.mist,0.009)
        line(0.018,-0.184,0.062,-0.176,ChartInk.mist,0.009)
    }
}
