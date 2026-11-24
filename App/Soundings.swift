import AppKit

extension StationView {
    func chartCoordinate(_ point: MistPoint) -> String {
        let col = UnicodeScalar(65 + max(0,min(25,point.x)))!
        return String(col)+String(point.y+1)
    }
    func stationName(at p: MistPoint, game: MistVoyage) -> String {
        switch game.level.tile(at:p) {
        case .water: return "水道"
        case .land: return "陆岸"
        case .origin: return "出发港"
        case .harbor: return "收信灯塔"
        case .stamp: return game.stamped.contains(p) ? "已盖邮戳" : "邮戳站"
        case .buoy(let id): return MistLevel.signalName(id)+"铃标"
        case .gate(let id): return MistLevel.signalName(id)+"水闸"
        }
    }
    func inspectSignal(_ id: Int, game: MistVoyage) {
        guard (0..<3).contains(id) else { return }
        hint = nil
        inspectedPoint = nil
        let buoys = game.level.stations(of:.buoy(id))
        let gates = game.level.stations(of:.gate(id))
        let name = MistLevel.signalName(id)
        guard !buoys.isEmpty || !gates.isEmpty else {
            notice("本图没有"+name+"铃闸。")
            return
        }
        func coords(_ points: [MistPoint]) -> String {
            points.isEmpty ? "无" : points.map(chartCoordinate).joined(separator:"、")
        }
        let ranges = bellIntervals(id,game:game)
        let schedule = ranges.isEmpty ? "本程尚无开闸拍。" : "开闸拍 "+ranges.joined(separator:"、")+"。"
        notice(name+"铃 "+coords(buoys)+"，闸 "+coords(gates)+"。"+schedule)
        signalInspection = (id,buoys+gates)
    }

    func inspect(_ point: MistPoint, game: MistVoyage) {
        let description: String
        switch game.level.tile(at:point) {
        case .buoy(let id), .gate(let id):
            inspectSignal(id,game:game)
            return
        case .origin: description = "出发港。留影返航后从这里重走。"
        case .harbor: description = game.stamped == game.level.stamps ? "收信灯塔。驶入即可投递。" : "收信灯塔。先到剩余邮戳站盖戳。"
        case .stamp: description = game.stamped.contains(point) ? "这枚邮戳已经盖好。" : "驶入邮戳站，为本轮邮袋盖戳。"
        case .land: description = "陆岸无法航行，请沿海图上的水道前进。"
        case .water: description = "点击与邮船相邻的水格航行，点击船身候一拍。"
        }
        inspectedPoint = point
        hint = nil
        notice(chartCoordinate(point)+"  ·  "+description)
    }
    func bellIntervals(_ id: Int, game: MistVoyage) -> [String] {
        var ranges: [String] = []
        var start: Int?
        for i in 1...(game.level.turnLimit+1) {
            let rings = i<=game.level.turnLimit && game.gateOpen(id,at:i)
            if rings && start == nil { start = i }
            if !rings, let lower = start {
                ranges.append(lower == i-1 ? String(lower) : "\(lower)–\(i-1)")
                start = nil
            }
        }
        return ranges
    }
    func signalMark(_ id: Int, at p: CGPoint, size s: CGFloat, ink: NSColor) {
        switch id {
        case 0:
            P.ellipse(R(p.x-s,p.y-s,s*2,s*2),fill:ink)
        case 1:
            P.polygon([.init(x:p.x,y:p.y-s*1.3),.init(x:p.x+s*1.3,y:p.y),
                       .init(x:p.x,y:p.y+s*1.3),.init(x:p.x-s*1.3,y:p.y)],fill:ink)
        default:
            P.polygon([.init(x:p.x,y:p.y-s*1.3),.init(x:p.x+s*1.3,y:p.y+s),
                       .init(x:p.x-s*1.3,y:p.y+s)],fill:ink)
        }
    }
}
