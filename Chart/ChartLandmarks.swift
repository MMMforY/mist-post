import CoreGraphics
import Foundation

extension ChartPen {
    /// Each delivery has a particular place in its letter. A single land-side
    /// motif sketches that place without introducing another interactive tile.
    func localLandmark(route: Int) {
        switch route {
        case 1:
            for row in 0..<2 {
                for col in 0..<3 {
                    let x = -0.41 + CGFloat(col)*0.224 + CGFloat(row)*0.085
                    let y = -0.04 + CGFloat(row)*0.139 - CGFloat(col)*0.028
                    poly([chartPoint(x,y),chartPoint(x+0.217,y-0.025),
                          chartPoint(x+0.291,y+0.093),chartPoint(x+0.074,y+0.122)],
                         (row+col).isMultiple(of:2) ? ChartInk.mist : ChartInk.paper,
                         stroke:ChartInk.shadow,width:0.014)
                    line(x+0.091,y+0.07,x+0.20,y+0.056,ChartInk.bright,0.020)
                }
            }
            placed(at:chartPoint(-0.10,-0.14),scale:0.69) { boathouse(redRoof:true) }
        case 2:
            bellFrame()
            placed(at:chartPoint(0.28,0.16), scale:0.42) { boathouse(redRoof:false) }
        case 3:
            marketStall()
        case 4:
            placed(at:chartPoint(-0.03,0.08),scale:1.10) { boathouse(redRoof:true) }
            line(-0.10,-0.18,-0.10,-0.38,ChartInk.ink,0.018)
            line(-0.22,-0.33,0.069,-0.33,ChartInk.ink,0.018)
            poly([chartPoint(-0.22,-0.33),chartPoint(-0.13,-0.37),chartPoint(-0.13,-0.3)],ChartInk.roof)
            line(-0.35,0.23,-0.20,0.19,ChartInk.shadow,0.018)
        case 5:
            wellHouse()
        case 6:
            placed(at:chartPoint(-0.045,0.11),scale:0.70) { boathouse(redRoof:false) }
            for (x,y) in [(-0.29,-0.08),(0.27,0.01),(0.12,-0.18)] as [(CGFloat,CGFloat)] {
                line(x,y+0.15,x+0.014,y-0.13,ChartInk.ink,0.017)
                line(x-0.06,y-0.112,x+0.09,y-0.13,ChartInk.ink,0.014)
                bird(at:chartPoint(x+0.025,y-0.15),scale:0.78)
            }
            bird(at:chartPoint(-0.15,-0.26),scale:1.16)
        case 7:
            boatCradle()
        case 8:
            wireHarp()
        case 9:
            lanternWorkshop()
        case 10:
            placed(at:chartPoint(-0.16,0.01),scale:0.83) { boathouse(redRoof:false) }
            placed(at:chartPoint(0.17,0.14),scale:0.69) { bellFrame() }
        case 11:
            placed(at:chartPoint(-0.10,-0.10),scale:0.84) { boathouse(redRoof:false) }
            placed(at:chartPoint(0.03,0.13),scale:0.94) { marketStall() }
        default:
            placed(at:chartPoint(0.08,0.06),scale:0.90) { lanternWorkshop() }
            line(-0.25,0.17,-0.25,-0.33,ChartInk.ink,0.019)
            for i in 0..<3 {
                let y = -0.32+0.085*CGFloat(i)
                poly([chartPoint(-0.24,y),chartPoint(-0.075,y+0.032),chartPoint(-0.24,y+0.065)],
                     i == 1 ? ChartInk.shadow : ChartInk.roof)
            }
        }
    }

    private func bellFrame() {
        poly([chartPoint(-0.30,0.115),chartPoint(0.04,0.22),chartPoint(0.33,0.10),
              chartPoint(-0.024,0.025)],ChartInk.stone)
        for x: CGFloat in [-0.20,0.20] {
            line(x,0.12,x*0.78,-0.275,ChartInk.ink,0.041)
            line(x,0.12,x*0.78,-0.275,ChartInk.ochre,0.016)
        }
        line(-0.17,-0.257,0.168,-0.257,ChartInk.ink,0.034)
        line(-0.01,-0.255,-0.01,-0.176,ChartInk.shadow,0.020)
        curve(fill:ChartInk.ochre,stroke:ChartInk.ink,width:0.019) { p in
            p.move(to:chartPoint(-0.145,0.016))
            p.addQuadCurve(to:chartPoint(-0.098,-0.093),control:chartPoint(-0.103,-0.012))
            p.addQuadCurve(to:chartPoint(0.084,-0.10),control:chartPoint(-0.008,-0.248))
            p.addQuadCurve(to:chartPoint(0.146,0.016),control:chartPoint(0.084,-0.036))
            p.addQuadCurve(to:chartPoint(-0.145,0.016),control:chartPoint(0,0.066))
        }
        oval(-0.121,0.006,0.25,0.045,ChartInk.shadow)
        oval(-0.021,0.026,0.042,0.045,ChartInk.ink)
        poly([chartPoint(-0.257,-0.258),chartPoint(-0.071,-0.38),chartPoint(0.17,-0.305),
              chartPoint(0.25,-0.23)],ChartInk.roof,stroke:ChartInk.ink,width:0.018)
    }

    private func marketStall() {
        poly([chartPoint(-0.33,0.15),chartPoint(0.125,0.245),chartPoint(0.344,0.159),
              chartPoint(-0.10,0.08)],ChartInk.stone)
        for (x,y) in [(-0.25,0.12),(0.16,0.199),(0.28,0.102)] as [(CGFloat,CGFloat)] {
            line(x,y,x,y-0.36,ChartInk.ink,0.023)
        }
        poly([chartPoint(-0.28,0.04),chartPoint(0.147,0.12),chartPoint(0.31,0.04),
              chartPoint(-0.102,-0.044)],ChartInk.ochre,stroke:ChartInk.ink,width:0.017)
        for i in 0..<4 {
            let x = -0.204+CGFloat(i)*0.085, y = 0.011+CGFloat(i)*0.017
            rect(x,y,0.073,0.032,i.isMultiple(of:2) ? ChartInk.roof : ChartInk.shadow,
                 stroke:ChartInk.ink,width:0.009)
        }
        let pts=[chartPoint(-0.325,-0.174),chartPoint(-0.17,-0.303),
                 chartPoint(0.323,-0.219),chartPoint(0.151,-0.085)]
        poly(pts,ChartInk.paper,stroke:ChartInk.ink,width:0.021)
        for i in 0..<4 {
            let d=CGFloat(i)*0.117
            poly([chartPoint(-0.319+d,-0.175+d*0.18),chartPoint(-0.265+d,-0.166+d*0.18),
                  chartPoint(-0.11+d,-0.291+d*0.18),chartPoint(-0.167+d,-0.301+d*0.18)],ChartInk.roof)
        }
    }

    private func wellHouse() {
        oval(-0.29,0.055,0.59,0.20,ChartInk.stone)
        rect(-0.198,-0.045,0.396,0.16,ChartInk.ochre,stroke:ChartInk.ink,width:0.016)
        oval(-0.2,0.072,0.40,0.117,ChartInk.ochre,stroke:ChartInk.shadow,width:0.016)
        oval(-0.213,-0.088,0.426,0.138,ChartInk.paper,stroke:ChartInk.ink,width:0.018)
        oval(-0.145,-0.067,0.29,0.080,ChartInk.ink)
        for x: CGFloat in [-0.157,0.147] { line(x,0,x,-0.255,ChartInk.ink,0.029) }
        line(-0.151,-0.18,0.168,-0.18,ChartInk.ochre,0.035)
        line(-0.01,-0.17,-0.01,-0.038,ChartInk.ink,0.014)
        poly([chartPoint(-0.249,-0.243),chartPoint(-0.087,-0.34),chartPoint(0.168,-0.303),
              chartPoint(0.235,-0.217)],ChartInk.roof,stroke:ChartInk.ink,width:0.017)
        for i in 0..<4 { line(-0.135+CGFloat(i)*0.08,0.038,-0.135+CGFloat(i)*0.08,0.096,ChartInk.shadow,0.011) }
    }

    private func bird(at point: CGPoint, scale: CGFloat) {
        placed(at:point,scale:scale) {
            curve(stroke:ChartInk.ink,width:0.019) { p in
                p.move(to:chartPoint(-0.093,-0.016))
                p.addQuadCurve(to:.zero,control:chartPoint(-0.048,-0.053))
                p.addQuadCurve(to:chartPoint(0.090,-0.038),control:chartPoint(0.042,-0.058))
            }
        }
    }

    private func boatCradle() {
        placed(at:.zero,angle:-0.24) {
            for x: CGFloat in [-0.21,0,0.21] { line(x,-0.14,x,0.18,ChartInk.shadow,0.035) }
            curve(fill:ChartInk.ochre,stroke:ChartInk.ink,width:0.024) { p in
                p.move(to:chartPoint(-0.35,-0.106))
                p.addQuadCurve(to:chartPoint(0.36,-0.079),control:chartPoint(-0.05,-0.175))
                p.addQuadCurve(to:chartPoint(0.295,0.061),control:chartPoint(0.342,-0.002))
                p.addQuadCurve(to:chartPoint(-0.265,0.091),control:chartPoint(0.08,0.162))
                p.closeSubpath()
            }
            for i in 0..<7 {
                let x = -0.27+CGFloat(i)*0.087
                curve(stroke:ChartInk.ink,width:0.022) { p in
                    p.move(to:chartPoint(x,-0.16+abs(x)*0.12))
                    p.addQuadCurve(to:chartPoint(x+0.065,0.084-abs(x)*0.12),control:chartPoint(x-0.02,0.024))
                }
            }
            line(-0.30,-0.038,0.313,-0.052,ChartInk.shadow,0.018)
        }
    }

    private func wireHarp() {
        for i in 0..<3 {
            let x = -0.24+CGFloat(i)*0.23, y = CGFloat(i)*0.055
            line(x,0.11+y,x,-0.273+y,ChartInk.ink,0.028)
            poly([chartPoint(x-0.074,-0.282+y),chartPoint(x+0.074,-0.282+y),
                  chartPoint(x+0.022,-0.216+y),chartPoint(x-0.022,-0.216+y)],ChartInk.ochre,
                 stroke:ChartInk.shadow,width:0.015)
        }
        for i in 0..<4 {
            let y = -0.215+CGFloat(i)*0.059
            curve(stroke:ChartInk.shadow,width:0.012) { p in
                p.move(to:chartPoint(-0.24,y)); p.addQuadCurve(to:chartPoint(0.22,y+0.11),control:chartPoint(-0.03,y+0.145))
            }
        }
        oval(0.16,0.12,0.24,0.071,ChartInk.mist,stroke:ChartInk.shadow,width:0.012)
    }

    private func lanternWorkshop() {
        placed(at:chartPoint(-0.09,0.13),scale:0.94) { boathouse(redRoof:true) }
        poly([chartPoint(0.101,0.10),chartPoint(0.132,-0.224),chartPoint(0.228,-0.224),
              chartPoint(0.252,0.114),chartPoint(0.19,0.15)],ChartInk.stone,stroke:ChartInk.ink,width:0.017)
        rect(0.118,-0.30,0.121,0.109,ChartInk.ochre,stroke:ChartInk.ink,width:0.017)
        poly([chartPoint(0.09,-0.297),chartPoint(0.18,-0.382),chartPoint(0.26,-0.297)],
             ChartInk.shadow,stroke:ChartInk.ink,width:0.016)
        line(0.18,-0.298,0.18,-0.213,ChartInk.ink,0.013)
        line(0.176,-0.376,0.176,-0.43,ChartInk.ink,0.013)
    }
}
