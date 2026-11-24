import Foundation

struct MistPoint: Hashable, Codable {
    let x: Int
    let y: Int

    func moved(_ move: MistMove) -> Self {
        switch move {
        case .north: return MistPoint(x: x, y: y - 1)
        case .east:  return MistPoint(x: x + 1, y: y)
        case .south: return MistPoint(x: x, y: y + 1)
        case .west:  return MistPoint(x: x - 1, y: y)
        case .wait:  return self
        }
    }
}

enum MistMove: String, CaseIterable, Codable {
    case north, east, south, west, wait

    var direction: String {
        switch self {
        case .north: return "北"
        case .east:  return "东"
        case .south: return "南"
        case .west:  return "西"
        case .wait:  return "原地"
        }
    }
}

enum MistTile: Equatable {
    case water, land, origin, harbor, stamp
    case buoy(Int), gate(Int)
}

enum MistCommand: Equatable, Codable {
    case move(MistMove)
    case record
}

enum MistBlock: Equatable {
    case land, gate(Int), missingStamps, outOfTime, finished, noRoute, echoLimit

    var message: String {
        switch self {
        case .land: return "浅滩搁桨，换一条水道。"
        case .gate(let id): return "下一拍，\(MistLevel.signalName(id))铃标需要一艘船影。"
        case .missingStamps: return "邮袋还缺中转戳。先到邮戳站盖戳。"
        case .outOfTime: return "本轮潮时已尽。撤回可以返回上一拍。"
        case .finished: return "信已送达。"
        case .noRoute: return "先航行一拍，再留影返航。"
        case .echoLimit: return "航线的船影名额已满。撤回可以收回航迹。"
        }
    }
}

enum MistOutcome: Equatable {
    case sailed, stamped, delivered
    case blocked(MistBlock)
}

struct MistHint {
    let text: String
    let point: MistPoint?
    let command: MistCommand?
    let undoCount: Int

    init(text: String, point: MistPoint?, command: MistCommand?, undoCount: Int = 0) {
        self.text = text
        self.point = point
        self.command = command
        self.undoCount = undoCount
    }
}

struct MistLevel {
    let id: Int
    let title: String
    let district: String
    let sender: String
    let recipient: String
    let postmark: String
    let letter: String
    let briefing: String
    let width: Int
    let height: Int
    let echoLimit: Int
    let turnLimit: Int
    let origin: MistPoint
    let harbor: MistPoint
    let stamps: Set<MistPoint>
    let par: Int

    // This is an executable route, so the same commands power scoring, hints and QA.
    let guide: [MistCommand]
    private let tiles: [MistTile]

    init(id: Int, title: String, district: String, sender: String, recipient: String,
         postmark: String, letter: String, briefing: String,
         rows: [String], echoLimit: Int, turnLimit: Int, routes: [String]) {
        precondition(!rows.isEmpty && !(rows[0].isEmpty))
        let width = rows[0].count
        var origin: MistPoint?
        var harbor: MistPoint?
        var tiles: [MistTile] = []
        var stamps: Set<MistPoint> = []
        for (y, row) in rows.enumerated() {
            precondition(row.count == width, "Inconsistent row width in level \(id)")
            for (x, symbol) in row.enumerated() {
                let point = MistPoint(x: x, y: y)
                switch symbol {
                case ".": tiles.append(.water)
                case "#": tiles.append(.land)
                case "S":
                    precondition(origin == nil)
                    origin = point
                    tiles.append(.origin)
                case "H":
                    precondition(harbor == nil)
                    harbor = point
                    tiles.append(.harbor)
                case "*":
                    stamps.insert(point)
                    tiles.append(.stamp)
                case "a", "b", "c": tiles.append(.buoy(Int(symbol.asciiValue! - 97)))
                case "A", "B", "C": tiles.append(.gate(Int(symbol.asciiValue! - 65)))
                default: preconditionFailure("Unrecognized map symbol in level \(id)")
                }
            }
        }
        guard let origin, let harbor else { preconditionFailure("Missing dock in level \(id)") }
        precondition((0...2).contains(echoLimit) && turnLimit > 0)
        var guide: [MistCommand] = []
        let moves: [Character: MistMove] = ["N": .north, "E": .east, "S": .south,
                                             "W": .west, ".": .wait]
        for (index, route) in routes.enumerated() {
            if index > 0 { guide.append(.record) }
            for symbol in route {
                guard let move = moves[symbol] else { preconditionFailure("Invalid route") }
                guide.append(.move(move))
            }
        }
        self.id = id
        self.title = title
        self.district = district
        self.sender = sender
        self.recipient = recipient
        self.postmark = postmark
        self.letter = letter
        self.briefing = briefing
        self.width = width
        self.height = rows.count
        self.echoLimit = echoLimit
        self.turnLimit = turnLimit
        self.origin = origin
        self.harbor = harbor
        self.tiles = tiles
        signalIDs = (0..<3).filter { tiles.contains(.buoy($0)) || tiles.contains(.gate($0)) }
        self.stamps = stamps
        self.guide = guide
        self.par = routes.reduce(0) { $0 + $1.count }
    }

    func tile(at point: MistPoint) -> MistTile {
        guard (0..<width).contains(point.x), (0..<height).contains(point.y) else { return .land }
        return tiles[point.y * width + point.x]
    }

    func stations(of tile: MistTile) -> [MistPoint] {
        tiles.indices.compactMap { index in
            tiles[index] == tile ? MistPoint(x:index % width,y:index / width) : nil
        }
    }

    let signalIDs: [Int]

    static func signalName(_ id: Int) -> String {
        switch id {
        case 0: return "一号"
        case 1: return "二号"
        default: return "三号"
        }
    }
}

struct MistVoyage {
    let level: MistLevel
    private(set) var path: [MistPoint]
    private(set) var echoes: [[MistPoint]] = []
    private(set) var stamped: Set<MistPoint> = []
    private(set) var history: [MistCommand] = []

    var position: MistPoint { path[path.count - 1] }
    var beat: Int { path.count - 1 }
    var delivered: Bool { position == level.harbor }
    var canRecord: Bool { !delivered && beat > 0 && echoes.count < level.echoLimit }
    var canUndo: Bool { !history.isEmpty }
    var totalBeats: Int { echoes.reduce(beat) { $0 + $1.count - 1 } }

    init(level: MistLevel) {
        self.level = level
        self.path = [level.origin]
    }

    init?(level: MistLevel, replay: [MistCommand]) {
        self.init(level: level)
        // A legal replay contains at most echoLimit + 1 bounded journeys.
        guard replay.count <= (level.echoLimit + 1) * level.turnLimit + level.echoLimit else {
            return nil
        }
        for command in replay {
            if case .blocked = perform(command) { return nil }
        }
    }

    @discardableResult
    mutating func perform(_ command: MistCommand) -> MistOutcome {
        switch command {
        case .move(let move): return step(move)
        case .record: return record()
        }
    }

    func echoPositions(at beat: Int) -> [MistPoint] {
        echoes.map { $0[min(max(0, beat), $0.count - 1)] }
    }

    func gateOpen(_ id: Int, at beat: Int) -> Bool {
        echoes.contains { path in
            let point = path[min(max(0, beat), path.count - 1)]
            return level.tile(at: point) == .buoy(id)
        }
    }

    /// The same arrival rule powers player input, hints and route verification.
    func obstruction(at destination: MistPoint, arrivingAt arrival: Int,
                     with stamps: Set<MistPoint>) -> MistBlock? {
        if arrival > level.turnLimit { return .outOfTime }
        switch level.tile(at: destination) {
        case .land: return .land
        case .gate(let id) where !gateOpen(id, at: arrival): return .gate(id)
        case .harbor where stamps != level.stamps: return .missingStamps
        default: return nil
        }
    }

    @discardableResult
    mutating func step(_ move: MistMove) -> MistOutcome {
        guard !delivered else { return .blocked(.finished) }
        let next = position.moved(move)
        if let reason = obstruction(at: next, arrivingAt: beat + 1, with: stamped) {
            return .blocked(reason)
        }
        path.append(next)
        history.append(.move(move))
        if delivered { return .delivered }
        if level.stamps.contains(next), stamped.insert(next).inserted { return .stamped }
        return .sailed
    }

    @discardableResult
    mutating func record() -> MistOutcome {
        guard !delivered else { return .blocked(.finished) }
        guard echoes.count < level.echoLimit else { return .blocked(.echoLimit) }
        guard beat > 0 else { return .blocked(.noRoute) }
        echoes.append(path)
        path = [level.origin]
        stamped.removeAll()
        history.append(.record)
        return .sailed
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let command = history.popLast() else { return false }
        switch command {
        case .move: path.removeLast()
        case .record: path = echoes.removeLast()
        }
        stamped = level.stamps.intersection(path)
        return true
    }

    mutating func restart() {
        self = Self(level: level)
    }
}
