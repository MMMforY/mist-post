import CoreGraphics
import Foundation

/// A signed-distance survey of the shoreline. Distance isolines are shared by
/// the land plate, beach, soundings and ink bathymetry, so their shapes agree.
struct ChartCoast {
    let contours: [CGFloat: CGPath]
    let headlands: [MistPoint]
    let bankHatching: CGPath

    init(level: MistLevel) {
        var boundaries: [CGRect] = []
        var headlands: [MistPoint] = []
        func land(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < level.width && y < level.height
                && level.tile(at: MistPoint(x: x, y: y)) == .land
        }
        for y in 0..<level.height {
            for x in 0..<level.width where land(x, y) {
                let px = CGFloat(x), py = CGFloat(y)
                headlands.append(MistPoint(x: x, y: y))
                if !land(x, y-1) { boundaries.append(CGRect(x:px, y:py, width:1, height:0)) }
                if !land(x, y+1) { boundaries.append(CGRect(x:px, y:py+1, width:1, height:0)) }
                if !land(x-1, y) { boundaries.append(CGRect(x:px, y:py, width:0, height:1)) }
                if !land(x+1, y) { boundaries.append(CGRect(x:px+1, y:py, width:0, height:1)) }
            }
        }
        self.headlands = headlands
        guard !boundaries.isEmpty else {
            self.contours = [:]
            self.bankHatching = CGMutablePath()
            return
        }

        let density = 10, margin = 2
        let w = (level.width + margin * 2) * density + 1
        let h = (level.height + margin * 2) * density + 1
        let phase = CGFloat(level.id % 1021) * 1.73
        // Only nearby shoreline segments can affect a printed depth contour.
        // Bucket them once, instead of testing every edge at every sample.
        let tileMargin=margin+1, binWidth=level.width+2*tileMargin+1
        let binHeight=level.height+2*tileMargin+1
        struct Bank {
            let x0, y0, x1, y1: CGFloat
        }
        let reach: CGFloat = 1.65
        var bins = [[Bank]](repeating:[],count:binWidth*binHeight)
        for edge in boundaries {
            let bank=Bank(x0:edge.minX,y0:edge.minY,x1:edge.maxX,y1:edge.maxY)
            let loX=max(0,Int(floor(bank.x0-reach))+tileMargin)
            let hiX=min(binWidth-1,Int(floor(bank.x1+reach))+tileMargin)
            let loY=max(0,Int(floor(bank.y0-reach))+tileMargin)
            let hiY=min(binHeight-1,Int(floor(bank.y1+reach))+tileMargin)
            for yy in loY...hiY {
                for xx in loX...hiX { bins[yy*binWidth+xx].append(bank) }
            }
        }
        var samples = [CGFloat](repeating: 0, count: w * h)
        for j in 0..<h {
            for i in 0..<w {
                let px = CGFloat(i) / CGFloat(density) - CGFloat(margin)
                let py = CGFloat(j) / CGFloat(density) - CGFloat(margin)
                // Warp the survey, rather than the drawn line. A bank and all
                // its neighboring depth contours consequently erode together.
                let x = px + 0.090*sin(4.7*py+phase) + 0.046*sin(8.1*py+2.0*px) + 0.027*cos(13.2*px-6.4*py)
                let y = py + 0.085*sin(4.1*px-phase) + 0.045*cos(7.7*px+2.9*py) + 0.020*sin(11.8*py+3.1*px)
                let ix=Int(floor(x)), iy=Int(floor(y))
                var nearest = reach*reach
                for edge in bins[(iy+tileMargin)*binWidth+ix+tileMargin] {
                    let dx = max(0, max(edge.x0-x, x-edge.x1))
                    let dy = max(0, max(edge.y0-y, y-edge.y1))
                    nearest = min(nearest, dx*dx + dy*dy)
                }
                let sign: CGFloat = land(ix,iy) ? -1 : 1
                samples[j*w+i] = sqrt(nearest) * sign
            }
        }
        // Soften convex and inner corners without changing cell connectivity.
        for _ in 0..<3 {
            var smooth = samples
            for j in 1..<(h-1) {
                for i in 1..<(w-1) {
                    let k = j*w+i
                    smooth[k] = samples[k]*0.28 +
                        (samples[k-1] + samples[k+1] + samples[k-w] + samples[k+w])*0.18
                }
            }
            samples = smooth
        }
        var contours: [CGFloat: CGPath] = [:]
        let levels: [CGFloat] = [-0.54, -0.38, -0.24, -0.075, 0, 0.065, 0.14, 0.25, 0.43, 0.72, 1.08]
        for threshold in levels {
            contours[threshold] = Self.contour(samples: samples, w: w, h: h,
                threshold: threshold, density: CGFloat(density), margin: CGFloat(margin))
        }
        self.contours = contours

        // Engravers use hachures normal to a contour to describe a steep
        // bank. The sampled distance gradient points from upland to water.
        let hatching = CGMutablePath()
        var rng = SurveySeed(level.id &* 971)
        for j in 1..<(h-1) {
            for i in 1..<(w-1) {
                let k = j*w+i, depth = samples[k]
                guard depth < -0.065 && depth > -0.22 && rng.next() > 0.48 else { continue }
                let gx = samples[k+1]-samples[k-1], gy = samples[k+w]-samples[k-w]
                let magnitude = max(0.001, hypot(gx,gy))
                let nx = gx/magnitude, ny = gy/magnitude
                let x = CGFloat(i)/CGFloat(density)-CGFloat(margin)+(rng.next()-0.5)*0.055
                let y = CGFloat(j)/CGFloat(density)-CGFloat(margin)+(rng.next()-0.5)*0.05
                let length = 0.026+rng.next()*0.065
                hatching.move(to:chartPoint(x,y))
                hatching.addLine(to:chartPoint(x+nx*length+0.012,y+ny*length))
            }
        }
        self.bankHatching = hatching
    }

    private static func contour(samples: [CGFloat], w: Int, h: Int, threshold: CGFloat,
                                density: CGFloat, margin: CGFloat) -> CGPath {
        // An edge has one stable integer key in both of its adjacent cells.
        // Chaining edge keys gives closed loops with holes for archipelagos.
        var neighbors: [Int: [Int]] = [:]
        var vertices: [Int: CGPoint] = [:]
        for j in 0..<(h-1) {
            for i in 0..<(w-1) {
                let a = j*w+i, b = a+1, c = b+w, d = a+w
                let minV = min(samples[a], samples[b], samples[c], samples[d])
                let maxV = max(samples[a], samples[b], samples[c], samples[d])
                guard minV <= threshold && maxV > threshold else { continue }
                let ends = [(a,b), (b,c), (d,c), (a,d)]
                let keys = [2*a, 2*b+1, 2*d, 2*a+1]
                var crossings: [Int] = []
                for n in 0..<4 {
                    let (v1,v2) = ends[n]
                    guard (samples[v1] <= threshold) != (samples[v2] <= threshold) else { continue }
                    let key = keys[n]
                    crossings.append(key)
                    if vertices[key] == nil {
                        let f = (threshold - samples[v1]) / (samples[v2]-samples[v1])
                        let x = CGFloat(v1%w) + (v2 == v1+1 ? f : 0)
                        let y = CGFloat(v1/w) + (v2 == v1+w ? f : 0)
                        vertices[key] = chartPoint(x/density-margin, y/density-margin)
                    }
                }
                func join(_ u: Int, _ v: Int) {
                    neighbors[u, default: []].append(v)
                    neighbors[v, default: []].append(u)
                }
                if crossings.count == 2 { join(crossings[0], crossings[1]) }
                else if crossings.count == 4 {
                    let center = (samples[a]+samples[b]+samples[c]+samples[d])*0.25
                    if (center <= threshold) != (samples[a] <= threshold) {
                        join(keys[0], keys[3]); join(keys[1], keys[2])
                    } else {
                        join(keys[0], keys[1]); join(keys[2], keys[3])
                    }
                }
            }
        }
        let path = CGMutablePath()
        var seen: Set<Int> = []
        for first in vertices.keys.sorted() where !seen.contains(first) {
            guard let point = vertices[first] else { continue }
            path.move(to: point)
            var key = first
            var previous = -1
            while seen.insert(key).inserted {
                guard let next = neighbors[key]?.first(where: { $0 != previous }),
                      let nextPoint = vertices[next] else { break }
                path.addLine(to: nextPoint)
                previous = key
                key = next
            }
            if key == first { path.closeSubpath() }
        }
        return path
    }
}
