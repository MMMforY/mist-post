import Foundation

enum MistWorkshopSize: String, CaseIterable, Codable {
    case small, medium, large

    var width: Int {
        switch self {
        case .small: return 7
        case .medium: return 9
        case .large: return 11
        }
    }

    var height: Int {
        switch self {
        case .small: return 5
        case .medium: return 7
        case .large: return 9
        }
    }

    init?(width: Int, height: Int) {
        guard let size = Self.allCases.first(where: { $0.width == width && $0.height == height }) else {
            return nil
        }
        self = size
    }
}

enum MistWorkshopError: Error, LocalizedError {
    case unsupportedFormat, unsupportedVersion(Int), draftOnly, sealedOnly, tooLarge, malformed
    case dimensions, symbol, ports, outside, protectedPort, stamps, circuit
    case title, author, letter, echoLimit, turnLimit
    case routeCount, routeLength, routeSymbol, blocked(Int, String), undelivered

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "请选择雾信航局对应格式的文件。"
        case .draftOnly: return "这是一份制图草稿。请在制图室完成试航，再封存为可分享的航图。"
        case .sealedOnly: return "这份航图已经封存。请使用导入航图，再选择编辑副本。"
        case .unsupportedVersion(let version): return "这份文件使用第 \(version) 版格式。当前支持第 1 版。"
        case .tooLarge: return "文件超过自绘航图的大小上限。"
        case .malformed: return "航图数据不完整，请重新选择或导出文件。"
        case .dimensions: return "航图尺寸可选 7×5、9×7 或 11×9，每一行须等宽。"
        case .symbol: return "航图中含有无法识别的地形符号。"
        case .ports: return "航图须有一座出发港和一座收信灯塔。"
        case .outside: return "请选择航图范围内的水格。"
        case .protectedPort: return "选择出发港或收信灯塔画笔，即可移动港口。"
        case .stamps: return "每张航图最多设置两座邮戳站。"
        case .circuit: return "请选择一号、二号或三号回路。"
        case .title: return "请输入 1–28 字的单行航图名。"
        case .author: return "署名最多 20 字，可留空。"
        case .letter: return "信件最多 160 字，可换行或留空。"
        case .echoLimit: return "船影名额可设为 0、1 或 2 艘。"
        case .turnLimit: return "每轮潮限须在 5–48 拍之间。"
        case .routeCount: return "试航轮数超过航图的船影名额，或缺少试航航迹。"
        case .routeLength: return "每一轮都需航行至少一拍，并在潮限内结束。"
        case .routeSymbol: return "试航航迹中含有无法识别的操作。"
        case .blocked(let index, let reason): return "试航记录在第 \(index) 次操作中断。\(reason)"
        case .undelivered: return "请先在这张航图上把信送达，再封存航图。"
        }
    }
}

/// The wire representation remains private to the editor and codec. Only validated
/// boards are passed to the engine, including when restoring an older undo state.
struct MistWorkshopBoard: Codable, Equatable {
    var title: String
    var author: String
    var letter: String
    var rows: [String]
    var echoLimit: Int
    var turnLimit: Int

    private static let allowedBytes = Set(".#SH*abcABC".utf8)

    var size: MistWorkshopSize {
        // All callers hold validated rectangles. An empty/unrecognized raw board
        // never reaches trialLevel() through either document decoder.
        switch rows.count {
        case 7: return .medium
        case 9: return .large
        default: return .small
        }
    }

    init(size: MistWorkshopSize) {
        title = "未命名航图"
        author = ""
        letter = ""
        echoLimit = 1
        turnLimit = 18
        var grid = Array(repeating: Array(repeating: UInt8(ascii: "."), count: size.width), count: size.height)
        grid[size.height / 2][0] = UInt8(ascii: "S")
        grid[size.height / 2][size.width - 1] = UInt8(ascii: "H")
        rows = Self.strings(grid)
    }

    func validated() throws -> Self {
        guard let width = rows.first?.utf8.count,
              MistWorkshopSize(width: width, height: rows.count) != nil,
              rows.allSatisfy({ $0.utf8.count == width }) else { throw MistWorkshopError.dimensions }
        var origins = 0, harbors = 0, stamps = 0
        for row in rows {
            for byte in row.utf8 {
                guard Self.allowedBytes.contains(byte) else { throw MistWorkshopError.symbol }
                switch byte {
                case UInt8(ascii: "S"): origins += 1
                case UInt8(ascii: "H"): harbors += 1
                case UInt8(ascii: "*"): stamps += 1
                default: break
                }
            }
        }
        guard origins == 1, harbors == 1 else { throw MistWorkshopError.ports }
        guard stamps <= 2 else { throw MistWorkshopError.stamps }
        guard (0...2).contains(echoLimit) else { throw MistWorkshopError.echoLimit }
        guard (5...48).contains(turnLimit) else { throw MistWorkshopError.turnLimit }
        var clean = self
        clean.title = try Self.text(title, limit: 28, lineBreaks: false, issue: .title)
        if clean.title.isEmpty { throw MistWorkshopError.title }
        clean.author = try Self.text(author, limit: 20, lineBreaks: false, issue: .author)
        clean.letter = try Self.text(letter, limit: 160, lineBreaks: true, issue: .letter)
        return clean
    }

    private static func text(_ source: String, limit: Int, lineBreaks: Bool,
                             issue: MistWorkshopError) throws -> String {
        guard source.utf8.count <= limit * 32 else { throw issue }
        let value = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard value.count <= limit else { throw issue }
        for scalar in value.unicodeScalars {
            if scalar == "\n", lineBreaks { continue }
            let category = scalar.properties.generalCategory
            if category == .control || category == .lineSeparator || category == .paragraphSeparator {
                throw issue
            }
        }
        return value
    }

    static func isPort(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "S") || byte == UInt8(ascii: "H")
    }

    static func strings(_ grid: [[UInt8]]) -> [String] {
        grid.map { String(decoding: $0, as: UTF8.self) }
    }

    func contains(_ point: MistPoint) -> Bool {
        (0..<size.width).contains(point.x) && (0..<size.height).contains(point.y)
    }

    func tile(at point: MistPoint) -> MistTile {
        guard contains(point) else { return .land }
        let cell = Array(rows[point.y].utf8)[point.x]
        switch cell {
        case UInt8(ascii: "."): return .water
        case UInt8(ascii: "S"): return .origin
        case UInt8(ascii: "H"): return .harbor
        case UInt8(ascii: "*"): return .stamp
        case UInt8(ascii: "a")...UInt8(ascii: "c"): return .buoy(Int(cell - UInt8(ascii: "a")))
        case UInt8(ascii: "A")...UInt8(ascii: "C"): return .gate(Int(cell - UInt8(ascii: "A")))
        default: return .land
        }
    }

    static func byte(_ tile: MistTile) throws -> UInt8 {
        switch tile {
        case .water: return UInt8(ascii: ".")
        case .land: return UInt8(ascii: "#")
        case .origin: return UInt8(ascii: "S")
        case .harbor: return UInt8(ascii: "H")
        case .stamp: return UInt8(ascii: "*")
        case .buoy(let id):
            guard (0...2).contains(id) else { throw MistWorkshopError.circuit }
            return UInt8(ascii: "a") + UInt8(id)
        case .gate(let id):
            guard (0...2).contains(id) else { throw MistWorkshopError.circuit }
            return UInt8(ascii: "A") + UInt8(id)
        }
    }

    func level(routes: [String]) -> MistLevel {
        MistLevel(id: -1, title: title, district: "制图室", sender: author.isEmpty ? "制图员" : author,
                  recipient: "外海航员", postmark: "手绘",
                  letter: letter.isEmpty ? "你绘下的航道已有船驶过。收信灯塔亮了，这封信顺利靠岸。" : letter,
                  briefing: "沿制图员绘出的水道，把信送到收信灯塔。",
                  rows: rows, echoLimit: echoLimit, turnLimit: turnLimit, routes: routes)
    }
}

struct MistWorkshopDraft {
    static let undoLimit = 32

    private struct TerrainStroke {
        let mark: UInt8
        var previous: MistPoint?
        var changed = false
    }
    private var stroke: TerrainStroke?
    var isDrawingTerrain: Bool { stroke != nil }

    private(set) var board: MistWorkshopBoard
    private(set) var undoBoards: [MistWorkshopBoard]

    var size: MistWorkshopSize { board.size }
    var title: String { board.title }
    var author: String { board.author }
    var letter: String { board.letter }
    var echoLimit: Int { board.echoLimit }
    var turnLimit: Int { board.turnLimit }
    var rows: [String] { board.rows }
    var canUndo: Bool { !undoBoards.isEmpty }

    init(size: MistWorkshopSize = .small) {
        board = MistWorkshopBoard(size: size)
        undoBoards = []
    }

    init(chart: MistWorkshopChart) {
        board = chart.board
        undoBoards = []
    }

    init(restoring board: MistWorkshopBoard, undoBoards: [MistWorkshopBoard]) throws {
        self.board = try board.validated()
        // The current sheet survives a damaged older undo record. Only the
        // contiguous, validated recent history may become active again.
        var recent: [MistWorkshopBoard] = []
        for entry in undoBoards.suffix(Self.undoLimit).reversed() {
            guard let safe = try? entry.validated() else { break }
            recent.append(safe)
        }
        self.undoBoards = Array(recent.reversed())
    }

    func tile(at point: MistPoint) -> MistTile { board.tile(at: point) }
    func trialLevel() -> MistLevel { board.level(routes: []) }

    /// A transient gesture never enters the document. From the first actual
    /// edit onward the saved draft already contains the whole stroke's undo.
    mutating func beginTerrainStroke(_ tile: MistTile) -> Bool {
        endTerrainStroke()
        switch tile {
        case .land: stroke = TerrainStroke(mark: UInt8(ascii: "#"))
        case .water: stroke = TerrainStroke(mark: UInt8(ascii: "."))
        default: return false
        }
        return true
    }

    mutating func endTerrainStroke() { stroke = nil }

    @discardableResult
    mutating func extendTerrainStroke(to point: MistPoint?) -> Bool {
        guard var active = stroke else { return false }
        guard let point, board.contains(point) else {
            stroke?.previous = nil
            return false
        }
        guard active.previous != point else { return false }
        let start = active.previous ?? point
        active.previous = point
        var grid = rows.map { Array($0.utf8) }
        var changed = false
        for cell in Self.segment(from: start, to: point) {
            let old = grid[cell.y][cell.x]
            if old != active.mark && !MistWorkshopBoard.isPort(old) {
                grid[cell.y][cell.x] = active.mark
                changed = true
            }
        }
        if changed {
            if !active.changed { rememberBoard(); active.changed = true }
            board.rows = MistWorkshopBoard.strings(grid)
        }
        stroke = active
        return changed
    }

    /// Walk the tile borders crossed between two sampled centers. At an exact
    /// corner choose the same bridge cell in either direction. A diagonal
    /// water stroke thus forms a channel the four-directional boat can sail.
    private static func segment(from start: MistPoint, to end: MistPoint) -> [MistPoint] {
        let dx = end.x - start.x, dy = end.y - start.y
        let nx = abs(dx), ny = abs(dy)
        var x = start.x, y = start.y, ix = 0, iy = 0
        var cells = [start]
        while ix < nx || iy < ny {
            let crossX = (2 * ix + 1) * ny
            let crossY = (2 * iy + 1) * nx
            if crossX < crossY || (crossX == crossY && dx > 0) {
                x += dx.signum()
                ix += 1
            } else {
                y += dy.signum()
                iy += 1
            }
            cells.append(MistPoint(x:x,y:y))
        }
        return cells
    }

    @discardableResult
    mutating func paint(_ tile: MistTile, at point: MistPoint) throws -> Bool {
        endTerrainStroke()
        guard board.contains(point) else { throw MistWorkshopError.outside }
        let new = try MistWorkshopBoard.byte(tile)
        var grid = rows.map { Array($0.utf8) }
        let old = grid[point.y][point.x]
        if old == new { return false }
        if MistWorkshopBoard.isPort(new) {
            guard let former = Self.find(new, in: grid) else { throw MistWorkshopError.ports }
            grid[former.y][former.x] = MistWorkshopBoard.isPort(old) ? old : UInt8(ascii: ".")
        } else {
            guard !MistWorkshopBoard.isPort(old) else { throw MistWorkshopError.protectedPort }
            if tile == .stamp, grid.reduce(0, { $0 + $1.filter { $0 == UInt8(ascii: "*") }.count }) >= 2 {
                throw MistWorkshopError.stamps
            }
        }
        grid[point.y][point.x] = new
        var next = board
        next.rows = MistWorkshopBoard.strings(grid)
        return apply(next)
    }

    @discardableResult
    mutating func configure(title: String? = nil, author: String? = nil, letter: String? = nil,
                            echoLimit: Int? = nil, turnLimit: Int? = nil) throws -> Bool {
        var next = board
        if let title { next.title = title }
        if let author { next.author = author }
        if let letter { next.letter = letter }
        if let echoLimit { next.echoLimit = echoLimit }
        if let turnLimit { next.turnLimit = turnLimit }
        return apply(try next.validated())
    }

    @discardableResult
    mutating func resize(_ size: MistWorkshopSize) -> Bool {
        guard size != self.size else { return false }
        let old = rows.map { Array($0.utf8) }
        var grid = Array(repeating: Array(repeating: UInt8(ascii: "."), count: size.width), count: size.height)
        for y in 0..<min(old.count, size.height) {
            for x in 0..<min(old[y].count, size.width) { grid[y][x] = old[y][x] }
        }
        for port: UInt8 in [UInt8(ascii: "S"), UInt8(ascii: "H")] where Self.find(port, in: grid) == nil {
            guard let original = Self.find(port, in: old),
                  let berth = Self.berth(near: original, in: grid) else { return false }
            grid[berth.y][berth.x] = port
        }
        var next = board
        next.rows = MistWorkshopBoard.strings(grid)
        return apply(next)
    }

    @discardableResult
    mutating func newSheet() -> Bool { apply(MistWorkshopBoard(size:size)) }

    @discardableResult
    mutating func undo() -> Bool {
        endTerrainStroke()
        guard let previous = undoBoards.popLast() else { return false }
        board = previous
        return true
    }

    private mutating func rememberBoard() {
        if undoBoards.count >= Self.undoLimit { undoBoards.removeFirst() }
        undoBoards.append(board)
    }

    private mutating func apply(_ next: MistWorkshopBoard) -> Bool {
        endTerrainStroke()
        guard next != board else { return false }
        rememberBoard()
        board = next
        return true
    }

    private static func find(_ marker: UInt8, in grid: [[UInt8]]) -> MistPoint? {
        for (y, row) in grid.enumerated() {
            if let x = row.firstIndex(of: marker) { return MistPoint(x: x, y: y) }
        }
        return nil
    }

    private static func berth(near old: MistPoint, in grid: [[UInt8]]) -> MistPoint? {
        var best: MistPoint?
        var rank = (Int.max, Int.max)
        for (y, row) in grid.enumerated() {
            for (x, cell) in row.enumerated() where cell != UInt8(ascii: "S") && cell != UInt8(ascii: "H") {
                let tileRank: Int
                switch cell {
                case UInt8(ascii: "."): tileRank = 0
                case UInt8(ascii: "#"): tileRank = 1
                default: tileRank = 2
                }
                let candidate = (tileRank, abs(old.x - x) + abs(old.y - y))
                if candidate < rank {
                    rank = candidate
                    best = MistPoint(x: x, y: y)
                }
            }
        }
        return best
    }
}
