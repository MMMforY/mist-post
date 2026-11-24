import CoreGraphics
import Foundation

enum ChartDistrict: Int {
    case salt, yard, cliffs
}

struct ChartRegion {
    let district: ChartDistrict
    let water, deep, shoal, beach, land, upland: CGColor
    let relief: CGFloat

    static let salt = ChartRegion(district:.salt,
        water:ChartInk.color(0x24504C),deep:ChartInk.color(0x143331),
        shoal:ChartInk.color(0x7B9A82),beach:ChartInk.color(0xD1BD8C),
        land:ChartInk.color(0xE9DCB7),upland:ChartInk.color(0xAFBF9D),relief:0.043)

    static let yard = ChartRegion(district:.yard,
        water:ChartInk.color(0x2D5456),deep:ChartInk.color(0x17363B),
        shoal:ChartInk.color(0x81A89F),beach:ChartInk.color(0xA3A48B),
        land:ChartInk.color(0xD2D0AD),upland:ChartInk.color(0x91AA94),relief:0.068)

    static let cliffs = ChartRegion(district:.cliffs,
        water:ChartInk.color(0x2D4B58),deep:ChartInk.color(0x182F3A),
        shoal:ChartInk.color(0x849D9F),beach:ChartInk.color(0xA3A095),
        land:ChartInk.color(0xDCD1B2),upland:ChartInk.color(0xAAA997),relief:0.122)

    static func forLevel(_ level: MistLevel) -> ChartRegion {
        switch level.id {
        case 1...4: return .salt
        case 5...8: return .yard
        case 9...12: return .cliffs
        default:
            let climates = [ChartRegion.salt,.yard,.cliffs]
            return climates[(level.width+level.height+level.origin.x) % climates.count]
        }
    }
}

extension ChartPen {
    func weatherMarks(region: ChartRegion, visible: CGRect, seed: Int) {
        var random = SurveySeed(seed &+ 1187)
        let samples = Int(min(360,visible.width*visible.height*0.96))
        for _ in 0..<samples {
            let x=visible.minX+random.next()*visible.width, y=visible.minY+random.next()*visible.height
            let s=0.46+random.next()*0.78
            switch region.district {
            case .salt:
                // Small caustic strokes on the broad, shallow salt flats.
                let ink=ChartInk.paper.chartAlpha(0.16)
                line(x,y,x+0.14*s,y-0.012*s,ink,0.009)
                line(x+0.047*s,y+0.025*s,x+0.22*s,y+0.014*s,ink,0.009)
            case .yard:
                let ink=ChartInk.mist.chartAlpha(0.24)
                if random.next() > 0.64 {
                    // Rain rings are shallow ellipses, unlike route centers.
                    oval(x,y,0.13*s,0.037*s,nil,stroke:ink,width:0.009)
                    line(x+0.122*s,y-0.028*s,x+0.134*s,y-0.067*s,ink,0.010)
                } else {
                    line(x,y,x-0.036*s,y+0.108*s,ink,0.009)
                }
            case .cliffs:
                // Broken parallel wave crests along the exposed headlands.
                curve(stroke:ChartInk.paper.chartAlpha(0.26),width:0.011) { p in
                    p.move(to:chartPoint(x,y))
                    p.addQuadCurve(to:chartPoint(x+0.105*s,y-0.022*s),control:chartPoint(x+0.075*s,y+0.006*s))
                    p.addQuadCurve(to:chartPoint(x+0.224*s,y-0.037*s),control:chartPoint(x+0.143*s,y-0.047*s))
                }
            }
        }
    }

    func saltern() {
        for i in 0..<3 {
            let dx=CGFloat(i)*0.077, dy=CGFloat(i)*0.046
            poly([chartPoint(-0.32+dx,0.01+dy),chartPoint(0.092+dx,-0.084+dy),
                  chartPoint(0.153+dx,-0.047+dy),chartPoint(-0.26+dx,0.052+dy)],
                 i == 1 ? ChartInk.paper : ChartInk.mist,stroke:ChartInk.stone,width:0.014)
        }
        for x: CGFloat in [-0.10,0.074] {
            poly([chartPoint(x-0.072,-0.052),chartPoint(x,-0.151),chartPoint(x+0.071,-0.075)],
                 ChartInk.bright,stroke:ChartInk.stone,width:0.011)
        }
    }

    func boatyardRails() {
        placed(at:.zero,angle:-0.255) {
            for x: CGFloat in [-0.22,-0.08,0.06,0.20] {
                poly([chartPoint(x-0.018,-0.128),chartPoint(x+0.017,-0.131),
                      chartPoint(x+0.034,0.109),chartPoint(x+0.004,0.116)],ChartInk.stone)
            }
            for y: CGFloat in [-0.073,0.058] { line(-0.313,y,0.292,y,ChartInk.shadow,0.021) }
            for i in 0..<3 {
                let y = -0.16-CGFloat(i)*0.037
                line(-0.23,y,0.006,y,ChartInk.roof,0.022)
            }
        }
    }

    func cliffSpurs() {
        for n in 0..<3 {
            let x = CGFloat(n)*0.123-0.164
            let y = CGFloat(n%2)*0.057
            let h = CGFloat(3-n)*0.051+0.074
            poly([chartPoint(x-0.075,0.106+y),chartPoint(x-0.040,-h+y),
                  chartPoint(x+0.034,-h-0.025+y),chartPoint(x+0.103,0.075+y)],
                 ChartInk.stone,stroke:ChartInk.shadow,width:0.013)
            poly([chartPoint(x-0.04,-h+y),chartPoint(x+0.034,-h-0.025+y),
                  chartPoint(x+0.005,-0.003+y),chartPoint(x-0.064,0.070+y)],ChartInk.paper)
            line(x+0.056,-0.059+y,x+0.075,0.028+y,ChartInk.shadow,0.011)
        }
    }
}
