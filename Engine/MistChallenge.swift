import Foundation

/// Versioned, offline route codes. M1 identifiers reproduce the same chart across runs.
struct MistChallenge {
    let code: String
    let level: MistLevel
    let motif: String
    let usedFallback: Bool

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let seedMask: UInt64 = (1 << 30) - 1

    static func make(seed: UInt64) -> MistChallenge {
        let payload = seed & seedMask
        let code = printedCode(payload)
        var random = MistChartRandom(seed: payload)
        let pattern = MistPattern.allCases[Int(payload % UInt64(MistPattern.allCases.count))]
        if let level = try? pattern.build(using: &random),
           let proof = MistVoyage(level: level, replay: level.guide), proof.delivered {
            return Self(code: code, level: level, motif: pattern.name, usedFallback: false)
        }
        // A known-good chart keeps old printed codes playable if a future rules change
        // invalidates a construction. Current v1 construction is tested without this path.
        let reference = MistCampaign.levels[pattern.referenceIndex]
        let level = pattern.fallback(copying: reference)
        return Self(code: code, level: level, motif: pattern.name, usedFallback: true)
    }

    static func open(code: String) -> MistChallenge? {
        guard code.utf8.count <= 128 else { return nil }
        let input = code.precomposedStringWithCompatibilityMapping.uppercased()
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-‐‑‒–—"))
        let letters = String(input.unicodeScalars.filter { !separators.contains($0) })
            .map { character -> Character in
                switch character {
                case "O": return "0"
                case "I", "L": return "1"
                default: return character
                }
            }
        guard letters.count == 9, letters[0] == "M", letters[1] == "1" else { return nil }
        var value: UInt64 = 0
        for letter in letters[2..<8] {
            guard let digit = alphabet.firstIndex(of: letter) else { return nil }
            value = (value << 5) | UInt64(digit)
        }
        guard letters[8] == alphabet[checksum(value)] else { return nil }
        return make(seed: value)
    }

    private static func printedCode(_ seed: UInt64) -> String {
        let payload = (0..<6).reversed().map { alphabet[Int((seed >> ($0 * 5)) & 31)] }
        return "M1-" + String(payload.prefix(3)) + "-" + String(payload.suffix(3)) + "-" + String(alphabet[checksum(seed)])
    }

    // Five-bit CRC on the payload detects substitutions of a single printed symbol.
    private static func checksum(_ seed: UInt64) -> Int {
        var remainder = 31
        for bit in (0..<30).reversed() {
            let carry = ((remainder >> 4) & 1) ^ Int((seed >> bit) & 1)
            remainder = (remainder << 1) & 31
            if carry == 1 { remainder ^= 5 }
        }
        return remainder
    }
}

struct MistChartRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed ^ 0x4d495354504f5354 }

    mutating func pick(_ range: ClosedRange<Int>) -> Int {
        state &+= 0x9e3779b97f4a7c15
        var word = state
        word = (word ^ (word >> 30)) &* 0xbf58476d1ce4e5b9
        word = (word ^ (word >> 27)) &* 0x94d049bb133111eb
        let count = range.upperBound - range.lowerBound + 1
        return range.lowerBound + Int((word ^ (word >> 31)) % UInt64(count))
    }

    mutating func coin() -> Bool { pick(0...1) == 0 }
}
