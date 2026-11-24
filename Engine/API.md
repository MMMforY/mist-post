# 雾信航局 · Engine contract

Pure Swift / Foundation. All types are module-internal and compile into the application target. Coordinates have origin at the top-left. One beat is one successful move or wait.

- `MistPoint(x: Int, y: Int)` is Hashable and Codable.
- `enum MistMove: String, CaseIterable, Codable` has cases `.north, .east, .south, .west, .wait`. `point.moved(move)` returns the attempted destination.
- `enum MistTile: Equatable` has cases `.water, .land, .origin, .harbor, .stamp, .buoy(Int), .gate(Int)`. IDs are zero-based. A buoy opens all gates of its ID when occupied by a prior echo on the arrival beat. The live boat cannot ring buoys for itself. A closed gate can be left. Out-of-bounds reads return land.
- `MistLevel` has `id: Int` (1-based), `title, district, sender, recipient, postmark, letter, briefing: String` (Chinese), `width, height, echoLimit, turnLimit: Int`, `origin, harbor: MistPoint`, `stamps: Set<MistPoint>`, and `tile(at: MistPoint) -> MistTile`. The title names the route. The letter is opened upon delivery. The briefing describes the current task. `par: Int` is the total beats in a verified route.
- `MistCampaign.levels: [MistLevel]` stores levels in play order.
- `struct MistVoyage` starts with `init(level: MistLevel)`. Read `level: MistLevel`, `position: MistPoint`, `beat: Int`, `path: [MistPoint]` (current route incl. origin), `echoes: [[MistPoint]]` (chronological recorded paths incl. origin), `stamped: Set<MistPoint>` (only current route), `delivered, canRecord, canUndo: Bool`, `totalBeats: Int`. `echoPositions(at beat: Int) -> [MistPoint]` holds each echo at its last position once its path ends. `gateOpen(_ id: Int, at beat: Int) -> Bool` supports previews as well as current state.
- `mutating func step(_ move: MistMove) -> MistOutcome`, where `enum MistOutcome: Equatable` has cases `.sailed, .stamped, .delivered, .blocked(MistBlock)`. `enum MistBlock: Equatable` has cases `.land, .gate(Int), .missingStamps, .outOfTime, .finished, .noRoute, .echoLimit` and `message: String`. Blocks leave the entire state intact. The harbor can be entered only after collecting all stamps. Reaching the turn limit prevents more movement. Recording and undo stay available when otherwise legal.
- `mutating func record() -> MistOutcome` returns `.sailed` on success. The new voyage starts at origin on beat 0 with its stamps cleared. Records must be nonempty and below the level's echo limit. `mutating func undo() -> Bool` reverses one accepted move or recording across the voyage boundary. `mutating func restart()` clears all journeys for this level.
- `enum MistCommand: Equatable, Codable` has `.move(MistMove)` and `.record`. `history: [MistCommand]` contains accepted commands. `init?(level: MistLevel, replay: [MistCommand])` strictly validates saved state and solutions.
- `func hint() -> MistHint` returns `MistHint(text: String, point: MistPoint?, command: MistCommand?)` with a suggested action or recovery. Its synchronous search is bounded by the chart size and time limit. A delivered level's hint has no command. A recovery hint has a positive `undoCount` and names the number of actions to undo.


## Printed challenges

`MistChallenge.make(seed: UInt64)` builds from the low 30 seed bits. `MistChallenge.open(code: String)` validates and decodes a printed code. Both return a chart containing `code`, `motif`, and `level`. Code parsing returns nil for an invalid version, symbol, or checksum.

A printed M1 code contains six Crockford-style Base32 symbols and a check symbol, grouped as `M1-XXX-XXX-X`. Parsing accepts lower-case letters, whitespace, hyphen variants, and the usual O/0 and I/L/1 substitutions. Persist the canonical code alongside move history. A generated `MistLevel` uses ID 0. Its `par` is the cost of a verified construction route. Campaign levels 1–12 use certified minimum total costs.

The generator carves eight families of temporal puzzles, coordinates arrivals at each bell and water gate, grows bays within their connected components, and applies a chart orientation and signal permutation. Replaying the complete reference route is part of generation. Seeded generation uses sorted cell iteration and its own fixed pseudo-random number generator.
