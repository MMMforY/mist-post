import Foundation

enum MistPattern: CaseIterable {
    case offset, returnBell, stampCove, twinInlets
    case harborPair, relay, chimes, beaconLoop

    var name: String {
        switch self {
        case .offset: return "错拍渡口"
        case .returnBell: return "折铃水巷"
        case .stampCove: return "回头采印"
        case .twinInlets: return "双湾换戳"
        case .harborPair: return "对钟双门"
        case .relay: return "内闸接班"
        case .chimes: return "三渠合拍"
        case .beaconLoop: return "环灯长航"
        }
    }

    var referenceIndex: Int {
        switch self {
        case .offset: return 3
        case .returnBell: return 8
        case .stampCove: return 10
        case .twinInlets: return 2
        case .harborPair: return 6
        case .relay: return 7
        case .chimes: return 9
        case .beaconLoop: return 11
        }
    }

    private var briefing: String {
        switch self {
        case .offset: return "两条水道长短不同。留意船影从出发港到铃标需要几拍。"
        case .returnBell: return "同一只铃标管着两道水闸。让船影折返，为最后一段水路报时。"
        case .stampCove: return "邮戳站在支流尽头。进出支流时都要有人鸣铃。"
        case .twinInlets: return "两座邮戳站各在一条小湾里。为两处湾口找一艘守铃的船影。"
        case .harborPair: return "并排的水闸需要两声钟。让两艘船影分头前往铃标。"
        case .relay: return "内渠也有一只铃标。先替下一艘船影打开去内渠的水闸。"
        case .chimes: return "三条水道共用三只铃标。一次铃响能同时照顾两条水道。"
        case .beaconLoop: return "这条航线要三种钟声。留影返航前，看看收信灯塔前的最后一道水闸。"
        }
    }

    fileprivate func level(rows: [String], routes: [String], limit: Int) -> MistLevel {
        MistLevel(id: 0, title: name, district: "外海试航", sender: "外海测绘员", recipient: "雾信航局",
                  postmark: "潮尺", letter: "试航回执已随船抵达。航图上的这段水路，终于有了第一道铅笔划下的航迹。",
                  briefing: briefing, rows: rows, echoLimit: routes.count - 1, turnLimit: limit,
                  routes: routes)
    }

    func fallback(copying reference: MistLevel) -> MistLevel {
        let rows = (0..<reference.height).map { y in
            String((0..<reference.width).map { x in
                switch reference.tile(at: MistPoint(x: x, y: y)) {
                case .water: return Character(".")
                case .land: return Character("#")
                case .origin: return Character("S")
                case .harbor: return Character("H")
                case .stamp: return Character("*")
                case .buoy(let id): return Array("abc")[id]
                case .gate(let id): return Array("ABC")[id]
                }
            })
        }
        let routes = reference.guide.split(separator: .record).map { commands in
            String(commands.compactMap { command in
                guard case .move(let move) = command else { return nil }
                return move.chartLetter
            })
        }
        return level(rows: rows, routes: routes, limit: reference.turnLimit)
    }

    func build(using random: inout MistChartRandom) throws -> MistLevel {
        let topHeight = random.pick(2...3)
        let lowerHeight = random.pick(2...3)
        let top = channel(side: -1, height: topHeight, reach: random.pick(7...9), using: &random)
        let lower = channel(side: 1, height: lowerHeight, reach: random.pick(8...10), using: &random)
        let a = topHeight + random.pick(1...2)
        let b = a + random.pick(2...3)
        let first = lowerHeight + 1
        let second = first + random.pick(2...3)
        let third = second + random.pick(2...3)
        var chart: ChartBlueprint
        switch self {
        case .offset:
            let signal = a + random.pick(1...2)
            let echo = Array(top[...signal])
            var live = lower
            var marks: [(Character, MistPoint)] = [("a", echo[signal]), ("A", lower[first])]
            if random.coin() { addPostmark(to: &live, marks: &marks, using: &random) }
            chart = try ChartBlueprint(paths: [echo, live], marks: marks)
            try chart.align([(0, signal), (1, first)])
        case .returnBell:
            let echo = Array(top[...b]) + top[a..<b].reversed()
            let marks: [(Character, MistPoint)] = [
                ("a", top[a]), ("b", top[b]), ("A", lower[first]),
                ("B", lower[second]), ("A", lower[third])
            ]
            chart = try ChartBlueprint(paths: [echo, lower], marks: marks)
            try chart.align([(0, a), (1, first)])
            try chart.align([(0, b), (1, second)])
            try chart.align([(0, echo.count - 1), (1, third)])
        case .stampCove:
            let junction = random.pick(2...4)
            let depth = random.pick(2...3)
            let secondGate = junction + random.pick(2...3)
            let far = secondGate + random.pick(2...3)
            let live = line([(0, 0), (junction, 0), (junction, depth), (junction, 0), (far, 0)])
            let entry = junction + 1
            let exit = junction + 2 * depth - 1
            let finalGate = secondGate + 2 * depth
            let marks: [(Character, MistPoint)] = [
                ("a", top[a]), ("b", top[b]), ("A", live[entry]),
                ("*", MistPoint(x: junction, y: depth)), ("B", live[finalGate])
            ]
            chart = try ChartBlueprint(paths: [Array(top[...b]), live], marks: marks)
            try chart.align([(0, a), (1, entry)])
            try chart.align([(0, a), (1, exit)])
            try chart.align([(0, b), (1, finalGate)])
        case .twinInlets:
            let one = random.pick(2...3)
            let two = one + random.pick(3...4)
            let nearDepth = random.pick(2...3)
            let farDepth = random.pick(2...3) * (random.coin() ? -1 : 1)
            let end = two + random.pick(2...3)
            let live = line([(0, 0), (one, 0), (one, nearDepth), (one, 0),
                             (two, 0), (two, farDepth), (two, 0), (end, 0)])
            let echo = Array(top[...a])
            let marks: [(Character, MistPoint)] = [
                ("a", top[a]), ("A", MistPoint(x: one, y: 1)),
                ("A", MistPoint(x: two, y: farDepth > 0 ? 1 : -1)),
                ("*", MistPoint(x: one, y: nearDepth)), ("*", MistPoint(x: two, y: farDepth))
            ]
            chart = try ChartBlueprint(paths: [echo, live], marks: marks)
            try chart.align([(0, a), (1, one + 1)])
        case .harborPair:
            let firstSignal = a + random.pick(0...2)
            let secondSignal = lowerHeight + random.pick(2...4)
            let gate = random.pick(2...4)
            let live = line([(0, 0), (gate + random.pick(3...5), 0)])
            let marks: [(Character, MistPoint)] = [
                ("a", top[firstSignal]), ("b", lower[secondSignal]), ("A", live[gate]), ("B", live[gate + 1])
            ]
            chart = try ChartBlueprint(paths: [Array(top[...firstSignal]), Array(lower[...secondSignal]), live],
                                       marks: marks)
            try chart.align([(0, firstSignal), (1, secondSignal), (2, gate)])
        case .relay:
            let gate = random.pick(2...3)
            let fork = gate + random.pick(1...2)
            let secondGate = fork + random.pick(1...2)
            let branch = random.pick(1...2) * (random.coin() ? -1 : 1)
            let height = random.pick(2...3)
            let middle = line([(0, 0), (fork, 0), (fork, -height), (fork + branch, -height)])
            let live = line([(0, 0), (secondGate + random.pick(2...3), 0)])
            let signal = lowerHeight + random.pick(1...3)
            let marks: [(Character, MistPoint)] = [
                ("a", lower[signal]), ("A", live[gate]), ("b", middle[middle.count - 1]),
                ("B", live[secondGate])
            ]
            chart = try ChartBlueprint(paths: [Array(lower[...signal]), middle, live], marks: marks)
            try chart.align([(0, signal), (1, gate), (2, gate)])
            try chart.align([(1, middle.count - 1), (2, secondGate)])
        case .chimes, .beaconLoop:
            let gate = random.pick(2...4)
            let middle = line([(0, 0), (gate + random.pick(2...4), 0)])
            let loops = self == .beaconLoop
            let echo = Array(top[...b]) + (loops ? Array(top[a..<b].reversed()) : [])
            var live = lower
            var marks: [(Character, MistPoint)] = [
                ("a", top[a]), ("c", top[b]), ("A", middle[gate]), ("b", middle[middle.count - 1]),
                (loops ? "B" : "A", lower[first]), ("C", lower[second]), (loops ? "A" : "B", lower[third])
            ]
            // The spur is after the three timed crossings so its return trip does
            // not change the indexed rendezvous below.
            if lower.count - 3 > third, random.coin() {
                addPostmark(to: &live, marks: &marks, using: &random)
            }
            chart = try ChartBlueprint(paths: [echo, middle, live], marks: marks)
            if loops {
                try chart.align([(0, a), (1, gate)])
                try chart.align([(1, middle.count - 1), (2, first)])
                try chart.align([(0, b), (2, second)])
                try chart.align([(0, echo.count - 1), (2, third)])
            } else {
                try chart.align([(0, a), (1, gate), (2, first)])
                try chart.align([(0, b), (2, second)])
                try chart.align([(1, middle.count - 1), (2, third)])
            }
        }
        return try chart.complete(pattern: self, using: &random)
    }

    private func channel(side: Int, height: Int, reach: Int, using random: inout MistChartRandom) -> [MistPoint] {
        let bend = random.pick(2...4)
        let rise = random.pick(0...1)
        return line([(0, 0), (0, side * height), (bend, side * height),
                     (bend, side * (height + rise)), (reach, side * (height + rise))])
    }

    private func line(_ corners: [(Int, Int)]) -> [MistPoint] {
        var result = [MistPoint(x: corners[0].0, y: corners[0].1)]
        for (x, y) in corners.dropFirst() {
            var point = result[result.count - 1]
            let dx = (x - point.x).signum()
            let dy = (y - point.y).signum()
            assert(dx == 0 || dy == 0)
            while point.x != x || point.y != y {
                point = MistPoint(x: point.x + dx, y: point.y + dy)
                result.append(point)
            }
        }
        return result
    }

    private func addPostmark(to path: inout [MistPoint], marks: inout [(Character, MistPoint)],
                             using random: inout MistChartRandom) {
        let index = path.count - 3
        let anchor = path[index]
        let depth = random.pick(1...2)
        let bay = line([(anchor.x, anchor.y), (anchor.x, anchor.y + depth), (anchor.x, anchor.y)])
        marks.append(("*", bay[depth]))
        path.insert(contentsOf: bay.dropFirst(), at: index + 1)
    }
}

private enum ChartError: Error { case invalidGeometry }

private struct ChartBlueprint {
    let paths: [[MistPoint]]
    var tiles: [MistPoint: Character]
    var tracks: [[MistPoint]]
    var cursors: [Int]

    init(paths: [[MistPoint]], marks: [(Character, MistPoint)]) throws {
        guard let start = paths.first?.first, let harbor = paths.last?.last else { throw ChartError.invalidGeometry }
        var tiles: [MistPoint: Character] = [:]
        for path in paths {
            guard path.first == start else { throw ChartError.invalidGeometry }
            for point in path { tiles[point] = "." }
        }
        for (symbol, point) in marks + [("S", start), ("H", harbor)] {
            guard tiles[point] == "." else { throw ChartError.invalidGeometry }
            tiles[point] = symbol
        }
        self.paths = paths
        self.tiles = tiles
        self.tracks = Array(repeating: [start], count: paths.count)
        self.cursors = Array(repeating: 0, count: paths.count)
    }

    // Synchronize arrivals at a gate and its bell. Bell keepers may wait on the
    // destination. Gate crossers wait at a preceding safe mooring.
    mutating func align(_ arrivals: [(actor: Int, index: Int)]) throws {
        let time = arrivals.map { tracks[$0.actor].count - 1 + $0.index - cursors[$0.actor] }.max() ?? 0
        for (actor, index) in arrivals {
            let cursor = cursors[actor]
            guard index >= cursor, index < paths[actor].count else { throw ChartError.invalidGeometry }
            var section = Array(paths[actor][cursor...index])
            let lag = time - (tracks[actor].count - 1 + index - cursor)
            if lag > 0 {
                let goal = section[section.count - 1]
                if let tile = tiles[goal], "abc".contains(tile) {
                    section += Array(repeating: goal, count: lag)
                } else {
                    guard let pause = section.indices.dropLast().last(where: { offset in
                        guard let tile = tiles[section[offset]] else { return false }
                        return !"ABC".contains(tile)
                    }) else { throw ChartError.invalidGeometry }
                    section.insert(contentsOf: Array(repeating: section[pause], count: lag), at: pause + 1)
                }
            }
            tracks[actor].append(contentsOf: section.dropFirst())
            cursors[actor] = index
        }
    }

    mutating func complete(pattern: MistPattern, using random: inout MistChartRandom) throws -> MistLevel {
        for actor in paths.indices {
            tracks[actor].append(contentsOf: paths[actor].dropFirst(cursors[actor] + 1))
            while tracks[actor].count > 1, tracks[actor].last == tracks[actor].dropLast().last {
                tracks[actor].removeLast()
            }
        }
        expandWater(using: &random)
        let orientation = random.pick(0...7)
        func orient(_ point: MistPoint) -> MistPoint {
            let x = orientation & 1 == 0 ? point.x : -point.x
            let y = orientation & 2 == 0 ? point.y : -point.y
            return orientation & 4 == 0 ? MistPoint(x: x, y: y) : MistPoint(x: y, y: x)
        }
        var signals = Array("abc".filter { tiles.values.contains($0) })
        if signals.count > 1 {
            for end in (1..<signals.count).reversed() {
                let other = random.pick(0...end)
                signals.swapAt(end, other)
            }
        }
        var relabel: [Character: Character] = [:]
        for (original, new) in zip("abc", signals) {
            relabel[original] = new
            relabel[Character(original.uppercased())] = Character(new.uppercased())
        }
        var mapped: [MistPoint: Character] = [:]
        for (point, symbol) in tiles { mapped[orient(point)] = relabel[symbol] ?? symbol }
        let xs = mapped.keys.map(\.x)
        let ys = mapped.keys.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              maxX - minX < 13, maxY - minY < 13 else { throw ChartError.invalidGeometry }
        let rows = (minY...maxY).map { y in
            String((minX...maxX).map { x in mapped[MistPoint(x: x, y: y)] ?? "#" })
        }
        let routes: [String] = try tracks.map { track in
            let points = track.map(orient)
            let letters: [Character] = try zip(points, points.dropFirst()).map { from, to in
                guard let move = MistMove.allCases.first(where: { from.moved($0) == to }) else {
                    throw ChartError.invalidGeometry
                }
                return move.chartLetter
            }
            return String(letters)
        }
        let longest = routes.map(\.count).max() ?? 0
        return pattern.level(rows: rows, routes: routes, limit: longest + random.pick(1...5))
    }

    // Enlarge bays within existing open-water components. Every new cell avoids
    // gate neighbors, so the expansion cannot introduce a way around a barrier.
    private mutating func expandWater(using random: inout MistChartRandom) {
        let cards: [MistMove] = [.north, .east, .south, .west]
        let keys = tiles.keys.sorted { left, right in
            left.y == right.y ? left.x < right.x : left.y < right.y
        }
        var components: [MistPoint: Int] = [:]
        for (island, point) in keys.enumerated() {
            guard components[point] == nil, let symbol = tiles[point], !"ABC".contains(symbol) else { continue }
            var queue = [point]
            components[point] = island
            var cursor = 0
            while cursor < queue.count {
                let cell = queue[cursor]
                cursor += 1
                for move in cards {
                    let other = cell.moved(move)
                    if components[other] == nil, let tile = tiles[other], !"ABC".contains(tile) {
                        components[other] = island
                        queue.append(other)
                    }
                }
            }
        }
        let xs = keys.map(\.x), ys = keys.map(\.y)
        guard let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max() else { return }
        let count = random.pick(3...9)
        for _ in 0..<count {
            var choices: [(MistPoint, Int)] = []
            for y in top...bottom {
                for x in left...right {
                    let point = MistPoint(x: x, y: y)
                    guard tiles[point] == nil else { continue }
                    let wet = cards.map { point.moved($0) }.filter { tiles[$0] != nil }
                    guard wet.count > 0, wet.count <= 3, let component = components[wet[0]],
                          wet.allSatisfy({ components[$0] == component }) else { continue }
                    choices.append((point, component))
                }
            }
            if choices.isEmpty { break }
            let (point, component) = choices[random.pick(0...(choices.count - 1))]
            tiles[point] = "."
            components[point] = component
        }
    }
}

private extension MistMove {
    var chartLetter: Character {
        switch self {
        case .north: return "N"
        case .east: return "E"
        case .south: return "S"
        case .west: return "W"
        case .wait: return "."
        }
    }
}
