import CryptoKit
import Foundation

struct MistWorkshopChart {
    let level: MistLevel
    let fingerprint: String
    let board: MistWorkshopBoard
    private let routes: [String]

    init(validating rawBoard: MistWorkshopBoard, routes: [String]) throws {
        let board = try rawBoard.validated()
        let commands = try WorkshopProof.commands(from: routes, board: board)
        let level = board.level(routes: routes)
        var replay = MistVoyage(level: level)
        for (index, command) in commands.enumerated() {
            if case .blocked(let reason) = replay.perform(command) {
                throw MistWorkshopError.blocked(index + 1, reason.message)
            }
        }
        guard replay.delivered else { throw MistWorkshopError.undelivered }
        self.board = board
        self.routes = routes
        self.level = level
        self.fingerprint = Self.digest(board: board, routes: routes)
    }

    func encoded() throws -> Data {
        let document = WorkshopChartDocument(format: WorkshopFile.chart, version: WorkshopFile.version,
                                             board: board, proof: routes)
        return try WorkshopFile.encode(document, limit: Self.maximumFileBytes)
    }

    static let maximumFileBytes = 16 * 1024

    static func open(_ data: Data) throws -> Self {
        let document: WorkshopChartDocument = try WorkshopFile.read(data, format: WorkshopFile.chart,
                                                                    limit: maximumFileBytes)
        return try Self(validating: document.board, routes: document.proof)
    }

    private static func digest(board: MistWorkshopBoard, routes: [String]) -> String {
        // Length-prefix UTF-8 fields in a fixed order. A content identifier therefore
        // survives JSON whitespace, key reordering and encoder changes.
        var canonical = Data()
        let prefix = ["mistpost-chart/1", board.title, board.author, board.letter, String(board.echoLimit),
                      String(board.turnLimit), String(board.rows.count)]
        for field in prefix + board.rows + [String(routes.count)] + routes {
            let bytes = field.utf8
            let length = UInt32(bytes.count)
            for shift in [24, 16, 8, 0] { canonical.append(UInt8(truncatingIfNeeded: length >> shift)) }
            canonical.append(contentsOf: bytes)
        }
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }
}

extension MistWorkshopDraft {
    func seal(proof: [MistCommand]) throws -> MistWorkshopChart {
        guard !proof.isEmpty else { throw MistWorkshopError.undelivered }
        guard proof.count <= (echoLimit + 1) * turnLimit + echoLimit else { throw MistWorkshopError.routeLength }
        var routes: [String] = []
        var route = ""
        for command in proof {
            switch command {
            case .record:
                guard !route.isEmpty else { throw MistWorkshopError.routeLength }
                routes.append(route)
                route = ""
            case .move(let move): route.append(WorkshopProof.symbol(move))
            }
        }
        routes.append(route)
        return try MistWorkshopChart(validating: board, routes: routes)
    }

    static let maximumDraftBytes = 256 * 1024

    func encodedDraft() throws -> Data {
        let document = WorkshopDraftDocument(format: WorkshopFile.draft, version: WorkshopFile.version,
                                             board: board, undo: undoBoards)
        return try WorkshopFile.encode(document, limit: Self.maximumDraftBytes)
    }

    static func restoreDraft(_ data: Data) throws -> Self {
        let document: WorkshopDraftDocument = try WorkshopFile.read(data, format: WorkshopFile.draft,
                                                                    limit: maximumDraftBytes)
        return try Self(restoring: document.board, undoBoards: document.undo ?? [])
    }
}

private enum WorkshopProof {
    static func symbol(_ move: MistMove) -> Character {
        switch move {
        case .north: return "N"
        case .east: return "E"
        case .south: return "S"
        case .west: return "W"
        case .wait: return "."
        }
    }

    static func commands(from routes: [String], board: MistWorkshopBoard) throws -> [MistCommand] {
        guard !routes.isEmpty, routes.count <= board.echoLimit + 1 else { throw MistWorkshopError.routeCount }
        var commands: [MistCommand] = []
        for (index, route) in routes.enumerated() {
            guard (1...board.turnLimit).contains(route.utf8.count) else { throw MistWorkshopError.routeLength }
            if index > 0 { commands.append(.record) }
            for byte in route.utf8 {
                let move: MistMove
                switch byte {
                case UInt8(ascii: "N"): move = .north
                case UInt8(ascii: "E"): move = .east
                case UInt8(ascii: "S"): move = .south
                case UInt8(ascii: "W"): move = .west
                case UInt8(ascii: "."): move = .wait
                default: throw MistWorkshopError.routeSymbol
                }
                commands.append(.move(move))
            }
        }
        return commands
    }
}

private struct WorkshopHeader: Decodable {
    let format: String
    let version: Int
}

private struct WorkshopChartDocument: Codable {
    let format: String
    let version: Int
    let board: MistWorkshopBoard
    let proof: [String]
}

private struct WorkshopDraftDocument: Codable {
    let format: String
    let version: Int
    let board: MistWorkshopBoard
    let undo: [MistWorkshopBoard]?

    init(format: String, version: Int, board: MistWorkshopBoard, undo: [MistWorkshopBoard]) {
        self.format = format
        self.version = version
        self.board = board
        self.undo = undo
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        format = try fields.decode(String.self, forKey: .format)
        version = try fields.decode(Int.self, forKey: .version)
        board = try fields.decode(MistWorkshopBoard.self, forKey: .board)
        undo = try? fields.decode([MistWorkshopBoard].self, forKey: .undo)
    }
}

private enum WorkshopFile {
    static let chart = "mistpost-chart"
    static let draft = "mistpost-draft"
    static let version = 1

    static func read<T: Decodable>(_ data: Data, format: String, limit: Int) throws -> T {
        guard data.count <= limit else { throw MistWorkshopError.tooLarge }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(WorkshopHeader.self, from: data) else {
            throw MistWorkshopError.malformed
        }
        guard header.format == format else {
            if format == chart && header.format == draft { throw MistWorkshopError.draftOnly }
            if format == draft && header.format == chart { throw MistWorkshopError.sealedOnly }
            throw MistWorkshopError.unsupportedFormat
        }
        guard header.version == version else { throw MistWorkshopError.unsupportedVersion(header.version) }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw MistWorkshopError.malformed }
    }

    static func encode<T: Encodable>(_ document: T, limit: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= limit else { throw MistWorkshopError.tooLarge }
        return data
    }
}
