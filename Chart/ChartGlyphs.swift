import CoreGraphics
import Foundation

extension ChartPen {
    /// Bow points north. The red planking, cream wheelhouse and black funnel
    /// are repeated on the title illustration, even at the smallest zoom.
    func mailboat(echo: CGColor? = nil) {
        let hull = CGMutablePath()
        hull.move(to: chartPoint(0, -0.44))
        hull.addQuadCurve(to: chartPoint(0.19, -0.06), control: chartPoint(0.17, -0.32))
        hull.addQuadCurve(to: chartPoint(0.145, 0.33), control: chartPoint(0.21, 0.14))
        hull.addQuadCurve(to: chartPoint(-0.145, 0.33), control: chartPoint(0, 0.41))
        hull.addQuadCurve(to: chartPoint(-0.19, -0.06), control: chartPoint(-0.20, 0.14))
        hull.addQuadCurve(to: chartPoint(0, -0.44), control: chartPoint(-0.16, -0.34))
        hull.closeSubpath()
        if let echo {
            path(hull, fill: ChartInk.ink.chartAlpha(0.74), stroke: echo, width: 0.034)
            saved {
                ctx.addPath(hull)
                ctx.clip()
                for i in -4...4 {
                    let y = CGFloat(i)*0.115
                    line(-0.23, y, 0.23, y-0.20, echo.chartAlpha(0.52), 0.021)
                }
            }
            rect(-0.106,-0.1,0.212,0.24,ChartInk.ink,stroke:echo,width:0.026)
            oval(-0.046,-0.022,0.092,0.092,echo)
            return
        }
        saved {
            ctx.translateBy(x: 0.045, y: 0.055)
            path(hull, fill: ChartInk.coal.chartAlpha(0.65))
        }
        path(hull, fill: ChartInk.red, stroke: ChartInk.coal, width: 0.045)
        saved {
            ctx.translateBy(x: 0, y: -0.024)
            ctx.scaleBy(x: 0.72, y: 0.80)
            path(hull, fill: ChartInk.ochre, stroke: ChartInk.bright, width: 0.024)
        }
        // Bow rail, mooring cross and the little postal bag on the aft deck.
        line(0,-0.335,0,-0.19,ChartInk.ink,0.019)
        line(-0.043,-0.274,0.043,-0.274,ChartInk.ink,0.023)
        rect(-0.117,-0.155,0.236,0.33,ChartInk.red,stroke:ChartInk.coal,width:0.020)
        rect(-0.106,-0.16,0.21,0.24,ChartInk.bright,stroke:ChartInk.ink,width:0.014)
        rect(-0.077,-0.132,0.154,0.058,ChartInk.sea)
        line(0,-0.13,0,-0.07,ChartInk.ochre,0.018)
        oval(-0.058,-0.026,0.115,0.12,ChartInk.rust,stroke:ChartInk.ink,width:0.015)
        oval(-0.033,-0.018,0.066,0.068,ChartInk.coal,stroke:ChartInk.red,width:0.014)
        rect(-0.079,0.193,0.158,0.085,ChartInk.paper,stroke:ChartInk.ink,width:0.015)
        poly([chartPoint(-0.073,0.20),chartPoint(0,0.244),chartPoint(0.073,0.20)],
             nil,stroke:ChartInk.rust,width:0.012,closed:false)
        for side: CGFloat in [-1,1] {
            oval(side*0.173-0.023,0.055,0.046,0.083,ChartInk.coal,stroke:ChartInk.stone,width:0.009)
        }
    }

    func originDock() {
        // A timber finger pier with four bollards and an outbound pennant.
        oval(-0.36,0.13,0.72,0.19,ChartInk.coal.chartAlpha(0.5))
        let quad = [chartPoint(-0.36,0.10),chartPoint(0.19,-0.085),
                    chartPoint(0.34,0.075),chartPoint(-0.22,0.27)]
        poly(quad,ChartInk.ochre,stroke:ChartInk.ink,width:0.035)
        for i in 0..<8 {
            let x = -0.30+CGFloat(i)*0.066, y = 0.093-CGFloat(i)*0.022
            line(x,y,x+0.13,y+0.135,ChartInk.shadow,0.015)
        }
        for p in [quad[0],quad[1],quad[3]] {
            rect(p.x-0.022,p.y-0.064,0.045,0.09,ChartInk.ink)
            oval(p.x-0.027,p.y-0.074,0.054,0.03,ChartInk.paper)
        }
        line(-0.24,0.09,-0.24,-0.34,ChartInk.paper,0.032)
        poly([chartPoint(-0.225,-0.34),chartPoint(0.014,-0.29),chartPoint(-0.225,-0.208)],
             ChartInk.red,stroke:ChartInk.ink,width:0.014)
    }

    func lighthouse(ready: Bool, phase: CGFloat) {
        let paper = ready ? ChartInk.bright : ChartInk.stone
        // Lighthouse has its own granite plinth rather than appearing as
        // navigable land. Its landing remains centered on the map square.
        oval(-0.34,0.14,0.70,0.19,ChartInk.coal.chartAlpha(0.62))
        poly([chartPoint(-0.32,0.163),chartPoint(-0.04,0.063),chartPoint(0.32,0.144),
              chartPoint(0.3,0.249),chartPoint(0.014,0.326),chartPoint(-0.32,0.242)],
             ChartInk.shadow,stroke:ChartInk.ink,width:0.022)
        poly([chartPoint(-0.32,0.163),chartPoint(-0.03,0.071),chartPoint(0.32,0.144),
              chartPoint(0.021,0.247)],ChartInk.ochre,stroke:ChartInk.ink,width:0.022)
        poly([chartPoint(-0.084,-0.22),chartPoint(0.085,-0.22),chartPoint(0.151,0.18),
              chartPoint(0.047,0.215),chartPoint(-0.145,0.179)],
             paper,stroke:ChartInk.ink,width:0.027)
        poly([chartPoint(0.066,-0.209),chartPoint(0.087,-0.218),chartPoint(0.151,0.18),
              chartPoint(0.048,0.215)],ChartInk.stone.chartAlpha(0.8))
        poly([chartPoint(-0.102,-0.085),chartPoint(0.102,-0.067),
              chartPoint(0.111,-0.016),chartPoint(-0.111,-0.034)],ChartInk.roof)
        rect(-0.028,0.084,0.060,0.108,ChartInk.ink)
        rect(-0.014,-0.149,0.03,0.043,ChartInk.ink)
        rect(-0.134,-0.261,0.268,0.049,ChartInk.ink)
        rect(-0.088,-0.371,0.176,0.112,ready ? ChartInk.amber : ChartInk.stone,
             stroke:ChartInk.ink,width:0.018)
        line(-0.036,-0.369,-0.036,-0.269,ChartInk.ink,0.014)
        line(0.035,-0.369,0.035,-0.269,ChartInk.ink,0.014)
        poly([chartPoint(-0.122,-0.372),chartPoint(-0.066,-0.426),chartPoint(0.0,-0.448),
              chartPoint(0.067,-0.426),chartPoint(0.124,-0.372)],ChartInk.red,stroke:ChartInk.ink,width:0.018)
        line(0,-0.447,0,-0.49,ChartInk.paper,0.019)
        if ready { oval(-0.024,-0.335,0.048,0.046,ChartInk.bright.chartAlpha(0.82+0.18*phase)) }
    }

    /// Street-sign silhouettes and numerals identify circuits without hue.
    /// The number is part of the signal, so it remains visible on either
    /// side of a rotating lock and on the last district's smaller map.
    func signalPlaque(_ group: Int, lit: Bool) {
        let face = lit ? ChartInk.amber : ChartInk.paper
        let dark = ChartInk.ink
        let digitY: CGFloat
        switch group % 3 {
        case 0:
            oval(-0.133,-0.138,0.266,0.276,face,stroke:dark,width:0.026)
            digitY = 0
        case 1:
            poly([chartPoint(0,-0.17),chartPoint(0.159,0),chartPoint(0,0.17),
                  chartPoint(-0.159,0)],face,stroke:dark,width:0.027)
            digitY = 0
        default:
            poly([chartPoint(0,-0.17),chartPoint(0.168,0.129),chartPoint(-0.168,0.129)],
                 face,stroke:dark,width:0.026)
            digitY = 0.035
        }
        // Monoline figures avoid raster-font hinting at fractional view scales.
        placed(at: chartPoint(0,digitY)) {
            switch group % 3 {
            case 0:
                poly([chartPoint(-0.035,-0.035),chartPoint(0.008,-0.073),chartPoint(0.008,0.070)],
                     nil,stroke:dark,width:0.027,closed:false)
                line(-0.035,0.070,0.052,0.070,dark,0.024)
            case 1:
                curve(stroke:dark,width:0.027) { p in
                    p.move(to:chartPoint(-0.048,-0.041))
                    p.addQuadCurve(to:chartPoint(0.049,-0.038),control:chartPoint(0.003,-0.106))
                    p.addQuadCurve(to:chartPoint(-0.045,0.064),control:chartPoint(0.058,-0.01))
                    p.addLine(to:chartPoint(0.056,0.064))
                }
            default:
                curve(stroke:dark,width:0.026) { p in
                    p.move(to:chartPoint(-0.038,-0.054))
                    p.addQuadCurve(to:chartPoint(0.001,-0.006),control:chartPoint(0.079,-0.093))
                    p.addQuadCurve(to:chartPoint(-0.039,0.054),control:chartPoint(0.087,0.065))
                }
            }
        }
    }

    func bellBuoy(group: Int, lit: Bool, plaqueScale: CGFloat = 1) {
        let lamp = lit ? ChartInk.amber : ChartInk.paper
        oval(-0.236,0.135,0.49,0.14,ChartInk.coal.chartAlpha(0.67))
        oval(-0.201,0.11,0.402,0.11,ChartInk.red,stroke:ChartInk.coal,width:0.024)
        poly([chartPoint(-0.154,0.128),chartPoint(-0.080,-0.234),chartPoint(0.082,-0.234),
              chartPoint(0.158,0.128)],ChartInk.ink,stroke:ChartInk.ochre,width:0.029)
        line(-0.103,-0.064,0.114,0.092,ChartInk.ochre,0.020)
        line(0.104,-0.064,-0.114,0.092,ChartInk.ochre,0.020)
        placed(at:chartPoint(0,-0.094),scale:plaqueScale) { signalPlaque(group,lit:lit) }
        rect(-0.06,-0.31,0.12,0.074,lamp,stroke:ChartInk.ink,width:0.02)
        poly([chartPoint(-0.092,-0.311),chartPoint(0,-0.389),chartPoint(0.093,-0.311)],
             ChartInk.red,stroke:ChartInk.ink,width:0.016)
        if lit {
            oval(-0.087,-0.337,0.174,0.13,ChartInk.amber.chartAlpha(0.23))
            oval(-0.025,-0.299,0.05,0.048,ChartInk.bright)
        }
    }

    /// The axes rotate with the corridor. A passable lock physically folds
    /// back both arms, leaving a visible opening even in monochrome.
    func lockGate(group: Int, open: Bool, acrossX: Bool, plaqueScale: CGFloat = 1) {
        let axis: CGFloat = acrossX ? 0 : .pi/2
        placed(at:.zero,angle:axis) {
            for side: CGFloat in [-1,1] {
                let x = side*0.34
                oval(x-0.082,-0.06,0.168,0.244,ChartInk.coal.chartAlpha(0.64))
                rect(x-0.064,-0.122,0.13,0.245,ChartInk.ochre,stroke:ChartInk.ink,width:0.022)
                rect(x-0.036,-0.095,0.07,0.124,ChartInk.shadow)
                oval(x-0.053,-0.114,0.108,0.099,open ? ChartInk.echo : ChartInk.red,
                     stroke:ChartInk.coal,width:0.021)
                saved {
                    ctx.translateBy(x:x,y:0.026)
                    ctx.scaleBy(x:-side,y:1)
                    if open { ctx.rotate(by: .pi*0.45) }
                    rect(0,-0.045,0.34,0.09,open ? ChartInk.mist : ChartInk.red,
                         stroke:ChartInk.coal,width:0.022)
                    for i in 0..<3 {
                        let dx=CGFloat(i)*0.101+0.034
                        poly([chartPoint(dx,-0.039),chartPoint(dx+0.050,-0.039),
                              chartPoint(dx+0.015,0.039),chartPoint(dx-0.03,0.039)], ChartInk.paper)
                    }
                }
            }
        }
        let markPosition = acrossX ? chartPoint(-0.32,-0.20) : chartPoint(0.115,-0.32)
        placed(at:markPosition,scale:0.96*plaqueScale) { signalPlaque(group,lit:open) }
    }

    func stampKiosk(collected: Bool) {
        // A clipped-corner stamp face with a perforated cream edge.
        let radius: CGFloat = 0.244
        var seal: [CGPoint] = []
        for i in 0..<32 {
            let angle = CGFloat(i) * .pi / 16
            let r = radius*(i.isMultiple(of:2) ? 1 : 0.91)
            seal.append(chartPoint(cos(angle)*r,sin(angle)*r))
        }
        oval(-0.247,0.106,0.50,0.16,ChartInk.coal.chartAlpha(0.52))
        poly(seal,collected ? ChartInk.depth : ChartInk.ochre,stroke:ChartInk.coal,width:0.026)
        oval(-0.176,-0.176,0.352,0.352,ChartInk.ink,stroke:ChartInk.paper,width:0.018)
        if collected {
            poly([chartPoint(-0.094,0.006),chartPoint(-0.025,0.073),chartPoint(0.106,-0.075)],
                 nil,stroke:ChartInk.echo,width:0.042,closed:false)
        } else {
            rect(-0.116,-0.077,0.232,0.156,ChartInk.paper,stroke:ChartInk.ochre,width:0.014)
            poly([chartPoint(-0.108,-0.069),chartPoint(0,0.016),chartPoint(0.108,-0.069)],
                 nil,stroke:ChartInk.rust,width:0.023,closed:false)
        }
    }
}
