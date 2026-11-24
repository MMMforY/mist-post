import CryptoKit
import Darwin
import Foundation

private enum LedgerError: Error { case unsupportedRevision }

/// Decode members independently so a broken replay cannot discard another harbor's mail.
private struct SavedEntries<Value: Decodable>: Decodable {
    struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { Int(stringValue) }
        init(stringValue: String) { self.stringValue = stringValue }
        init(intValue: Int) { stringValue = String(intValue) }
    }
    var values: [String: Value] = [:]
    var rejected = false
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: Key.self)
        for key in box.allKeys {
            if let value = try? box.decode(Value.self, forKey: key) { values[key.stringValue] = value }
            else { rejected = true }
        }
    }
}

private struct SavedTelegram: Decodable {
    enum Key: String, CodingKey { case draft, best, visited }
    let entry: TelegramEntry
    let rejected: Bool
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: Key.self)
        let draft = try? box.decode([MistCommand].self, forKey: .draft)
        let best = try? box.decode([MistCommand].self, forKey: .best)
        let visited = try? box.decode(Date.self, forKey: .visited)
        rejected = (box.contains(.draft) && draft == nil) || (box.contains(.best) && best == nil && (try? box.decodeNil(forKey: .best)) != true)
        entry = TelegramEntry(draft: draft ?? [], best: best, visited: visited ?? Date(timeIntervalSince1970: 0))
    }
}

struct StationProfile: Codable {
    var telegrams: [String: TelegramEntry]?
    var workshopDraft: Data?
    var workshopCharts: [String: Data]?
    var revision = 1
    var currentID = 1
    var journeys: [Int: [MistCommand]] = [:]
    var records: [Int: Int] = [:]
    var winningRoutes: [Int: [MistCommand]] = [:]
    var soundOn = true
    var lowMotion = false
    var trails = true
    var contrast = false
    fileprivate var legacyReceipts: [Int: Int]?
    fileprivate var needsRepair = false

    private enum CodingKeys: String, CodingKey {
        case revision, currentID, journeys, records, winningRoutes, soundOn, lowMotion, trails, contrast
        case telegrams, workshopDraft, workshopCharts, legacyReceipts
    }
    init() {}
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let version: Int
        if box.contains(.revision) {
            guard let declared = try? box.decode(Int.self, forKey: .revision), (0...1).contains(declared) else { throw LedgerError.unsupportedRevision }
            version = declared
        } else { version = 0 }
        var damage = false
        func values<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> [String: T] {
            guard box.contains(key), (try? box.decodeNil(forKey: key)) != true else { return [:] }
            guard let map = try? box.decode(SavedEntries<T>.self, forKey: key) else { damage = true; return [:] }
            if map.rejected { damage = true }
            return map.values
        }
        func numbered<T>(_ entries: [String: T]) -> [Int: T] {
            var result: [Int: T] = [:]
            for (key, value) in entries {
                if let id = Int(key), String(id) == key { result[id] = value } else { damage = true }
            }
            return result
        }
        currentID = (try? box.decode(Int.self, forKey: .currentID)) ?? 1
        soundOn = (try? box.decode(Bool.self, forKey: .soundOn)) ?? true
        lowMotion = (try? box.decode(Bool.self, forKey: .lowMotion)) ?? false
        trails = (try? box.decode(Bool.self, forKey: .trails)) ?? true
        contrast = (try? box.decode(Bool.self, forKey: .contrast)) ?? false
        workshopDraft = try? box.decode(Data.self, forKey: .workshopDraft)
        if box.contains(.workshopDraft), workshopDraft == nil, (try? box.decodeNil(forKey: .workshopDraft)) != true { damage = true }
        if box.contains(.workshopCharts), (try? box.decodeNil(forKey: .workshopCharts)) != true { workshopCharts = values(Data.self, .workshopCharts) }
        journeys = numbered(values([MistCommand].self, .journeys))
        winningRoutes = numbered(values([MistCommand].self, .winningRoutes))
        records = numbered(values(Int.self, .records))
        let legacy = version == 0 && !box.contains(.winningRoutes) ? records : numbered(values(Int.self, .legacyReceipts))
        legacyReceipts = legacy.isEmpty ? nil : legacy
        if box.contains(.telegrams), (try? box.decodeNil(forKey: .telegrams)) != true {
            let wires = values(SavedTelegram.self, .telegrams)
            telegrams = wires.mapValues(\.entry)
            damage = damage || wires.values.contains { $0.rejected }
        }
        needsRepair = damage
    }
}

private final class LedgerRules {
    private let levels = Dictionary(uniqueKeysWithValues: MistCampaign.levels.map { ($0.id, $0) })
    private var recentWire: MistChallenge?

    private func wire(_ code: String) -> MistChallenge? {
        if recentWire?.code == code { return recentWire }
        let result = MistChallenge.open(code: code)
        if let result { recentWire = result }
        return result
    }

    private func changed<K: Hashable, V: Equatable>(_ old: [K: V], _ new: [K: V]) -> Set<K> {
        Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }
    }

    private func accept(_ trip: MistVoyage, in result: inout StationProfile) {
        let id = trip.level.id
        if result.winningRoutes[id] == nil || trip.totalBeats < (result.records[id] ?? .max) {
            result.winningRoutes[id] = trip.history
            result.records[id] = trip.totalBeats
        }
        result.legacyReceipts?[id] = nil
    }

    private func best(_ candidate: [MistCommand]?, level: MistLevel, entry: inout TelegramEntry) -> Bool {
        guard let candidate else { return true }
        guard let incoming = MistVoyage(level: level, replay: candidate), incoming.delivered else { return false }
        if let route = entry.best, let saved = MistVoyage(level: level, replay: route), saved.delivered,
           saved.totalBeats <= incoming.totalBeats { return true }
        entry.best = candidate
        return true
    }

    private func wires(_ source: StationProfile, since base: StationProfile, into result: inout StationProfile) {
        let old = base.telegrams ?? [:], new = source.telegrams ?? [:]
        var merged = result.telegrams ?? [:]
        for key in Set(old.keys).union(new.keys).sorted() {
            let before = old[key], after = new[key]
            if before?.draft == after?.draft && before?.best == after?.best && before?.visited == after?.visited { continue }
            guard let after else {
                let latest = merged[key]
                if latest?.draft == before?.draft && latest?.best == before?.best && latest?.visited == before?.visited { merged[key] = nil }
                continue
            }
            guard let challenge = wire(key) else { result.needsRepair = true; continue }
            let code = challenge.code, level = challenge.level
            var entry = merged[code] ?? TelegramEntry(visited: Date(timeIntervalSince1970: 0))
            if after.best != before?.best, !best(after.best, level: level, entry: &entry) { result.needsRepair = true }
            if after.draft != before?.draft {
                if let trip = MistVoyage(level: level, replay: after.draft) {
                    if trip.delivered { _ = best(trip.history, level: level, entry: &entry) }
                    if merged[code] == nil || after.visited >= entry.visited {
                        entry.draft = trip.delivered ? [] : trip.history
                    }
                } else { result.needsRepair = true }
            }
            if after.visited.timeIntervalSinceReferenceDate.isFinite { entry.visited = max(entry.visited, after.visited) }
            merged[code] = entry
        }
        if !merged.isEmpty { result.telegrams = merged }
        else if source.telegrams != nil || !old.isEmpty { result.telegrams = source.telegrams == nil ? nil : [:] }
    }

    /// Apply only the caller's edits on top of the latest committed ledger. Receipts are
    /// monotonic, draft slots follow their edits, and every winning route must really deliver.
    func merge(_ source: StationProfile, since base: StationProfile, onto disk: StationProfile) -> StationProfile {
        var result = disk
        result.needsRepair = source.needsRepair
        if source.currentID != base.currentID { result.currentID = source.currentID }
        if source.soundOn != base.soundOn { result.soundOn = source.soundOn }
        if source.lowMotion != base.lowMotion { result.lowMotion = source.lowMotion }
        if source.trails != base.trails { result.trails = source.trails }
        if source.contrast != base.contrast { result.contrast = source.contrast }
        if source.workshopDraft != base.workshopDraft { result.workshopDraft = source.workshopDraft }
        if source.workshopCharts != base.workshopCharts {
            var charts = result.workshopCharts ?? [:]
            let new = source.workshopCharts ?? [:]
            for key in changed(base.workshopCharts ?? [:], new) { charts[key] = new[key] }
            result.workshopCharts = charts.isEmpty && source.workshopCharts == nil ? nil : charts
        }
        for (id, score) in source.legacyReceipts ?? [:] where result.winningRoutes[id] == nil {
            guard let level = levels[id] else { continue }
            let minimum = abs(level.origin.x - level.harbor.x) + abs(level.origin.y - level.harbor.y)
            guard (minimum...((level.echoLimit + 1) * level.turnLimit)).contains(score) else { continue }
            result.records[id] = min(result.records[id] ?? .max, score)
            var receipts = result.legacyReceipts ?? [:]
            receipts[id] = result.records[id]
            result.legacyReceipts = receipts
        }
        for id in changed(base.winningRoutes, source.winningRoutes) {
            guard let route = source.winningRoutes[id] else { continue }
            guard let level = levels[id], let trip = MistVoyage(level: level, replay: route), trip.delivered else { result.needsRepair = true; continue }
            accept(trip, in: &result)
        }
        for id in changed(base.journeys, source.journeys) {
            guard let route = source.journeys[id] else { result.journeys[id] = nil; continue }
            guard let level = levels[id], let trip = MistVoyage(level: level, replay: route) else { result.needsRepair = true; continue }
            if trip.delivered { accept(trip, in: &result); result.journeys[id] = nil }
            else { result.journeys[id] = route }
        }
        wires(source, since: base, into: &result)
        if levels[result.currentID] == nil || !Self.unlocked(result.currentID, profile: result) { result.currentID = Self.next(result) }
        if result.legacyReceipts?.isEmpty == true { result.legacyReceipts = nil }
        return result
    }

    static func next(_ profile: StationProfile) -> Int { MistCampaign.levels.first { profile.records[$0.id] == nil }?.id ?? 1 }
    static func unlocked(_ id: Int, profile: StationProfile) -> Bool {
        MistCampaign.levels.contains { $0.id == id } && (id == 1 || profile.records[id - 1] != nil || profile.records[id] != nil)
    }
}

/// Foundation's encoder cannot embed pre-encoded JSON. Assemble the two object
/// envelopes here, leaving all player values and keys to JSONEncoder. Only the
/// current telegram needs fresh command encoding during a voyage.
private final class LedgerEncoder {
    private struct Member {
        let entry: TelegramEntry
        let bytes: Data
    }
    private var members: [String: Member] = [:]
    private let json: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func encode(_ profile: StationProfile) throws -> Data {
        guard let telegrams = profile.telegrams else {
            members.removeAll()
            return try json.encode(profile)
        }
        var header = profile
        header.telegrams = nil
        var bytes = try json.encode(header)
        // Header always encodes at least the revision. Each member below is a
        // single-key object emitted by the same compact encoder.
        bytes.removeLast()
        bytes.append(contentsOf: #","telegrams":{"#.utf8)
        var next: [String: Member] = [:]
        next.reserveCapacity(telegrams.count)
        for (index, code) in telegrams.keys.sorted().enumerated() {
            guard let entry = telegrams[code] else { continue }
            let member: Member
            if let old = members[code], old.entry == entry {
                member = old
            } else {
                let object = try json.encode([code:entry])
                member = Member(entry:entry,bytes:Data(object.dropFirst().dropLast()))
            }
            next[code] = member
            if index > 0 { bytes.append(0x2c) }
            bytes.append(member.bytes)
        }
        bytes.append(contentsOf: "}}".utf8)
        members = next
        return bytes
    }
}

final class DispatchStore {
    private let mutex = NSRecursiveLock()
    private var current = StationProfile()
    private var message: String?
    private let destination: URL?
    private let rules = LedgerRules()
    private let encoder = LedgerEncoder()
    private var committed = StationProfile()
    private var committedData: Data?
    private var checkpointAtCommit: Data?
    var profile: StationProfile { mutex.withLock { current } }
    var notice: String? { mutex.withLock { message } }

    private enum Snapshot {
        case missing, clean(StationProfile, Data), damaged(StationProfile?, Data)
    }

    init(file: URL?) {
        destination = file?.standardizedFileURL.resolvingSymlinksInPath()
        guard let file = destination else { return }
        do {
            switch try inspect(file) {
            case .clean(let saved, let bytes):
                current = saved
                committedData = bytes
                checkpointAtCommit = try? contents(file.appendingPathExtension("previous"))
            case .missing:
                if let saved = previous(file) { current = saved; message = "已从上一版航簿恢复记录。" }
            case .damaged(let partial, let bytes):
                current = recover(partial, file: file)
                try archive(bytes, for: file)
                message = "航簿已恢复可读记录，原文件已另存。"
            }
        } catch LedgerError.unsupportedRevision {
            current = previous(file) ?? StationProfile()
            message = Self.versionMessage
        } catch { message = "航簿暂时无法读取，原文件已保留。" }
        committed = current
    }

    private static let versionMessage = "此航簿使用其他版本，本次进度暂存内存，原文件已保留。"
    static func defaultFile() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MistPost", isDirectory: true).appendingPathComponent("dispatch-v1.json")
    }
    var nextUndelivered: Int { LedgerRules.next(profile) }
    func unlocked(_ id: Int) -> Bool { LedgerRules.unlocked(id, profile: profile) }

    private func contents(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) { return nil }
    }
    private func inspect(_ url: URL) throws -> Snapshot {
        guard let bytes = try contents(url) else { return .missing }
        if bytes == committedData { return .clean(committed, bytes) }
        do {
            let raw = try JSONDecoder().decode(StationProfile.self, from: bytes)
            let clean = rules.merge(raw, since: StationProfile(), onto: StationProfile())
            return clean.needsRepair ? .damaged(clean, bytes) : .clean(clean, bytes)
        } catch LedgerError.unsupportedRevision { throw LedgerError.unsupportedRevision }
        catch { return .damaged(nil, bytes) }
    }
    private func previous(_ file: URL) -> StationProfile? {
        if case .clean(let saved, _) = try? inspect(file.appendingPathExtension("previous")) { return saved }
        return nil
    }
    private func recoveryBase(_ file: URL) -> StationProfile {
        guard case .clean(let saved, let bytes) = try? inspect(file.appendingPathExtension("previous")) else { return committed }
        // If the checkpoint still matches what this instance saw at its last commit,
        // its in-memory committed snapshot includes the more recent delivery or draft.
        if committedData != nil && (bytes == checkpointAtCommit || bytes == committedData) { return committed }
        return saved
    }
    private func recover(_ partial: StationProfile?, file: URL) -> StationProfile {
        let prior = recoveryBase(file)
        guard var partial else { return prior }
        // A damaged member may have been a previously verified delivery. Preserve those
        // receipts without restoring obsolete draft/settings fields over readable ones.
        var receipts = StationProfile()
        receipts.winningRoutes = prior.winningRoutes
        receipts.legacyReceipts = prior.legacyReceipts
        for (code, entry) in prior.telegrams ?? [:] where entry.best != nil {
            var wires = receipts.telegrams ?? [:]
            wires[code] = partial.telegrams?[code] == nil ? entry : TelegramEntry(draft: [], best: entry.best, visited: .distantPast)
            receipts.telegrams = wires
        }
        partial.needsRepair = false
        return rules.merge(receipts, since: StationProfile(), onto: partial)
    }
    private func archive(_ bytes: Data, for file: URL) throws {
        let digest = SHA256.hash(data: bytes).prefix(12).map { String(format: "%02x", $0) }.joined()
        let folder = file.deletingLastPathComponent()
        var backup = folder.appendingPathComponent("dispatch-recovery-" + digest + ".json")
        if let existing = try contents(backup) {
            if existing == bytes { return }
            backup = folder.appendingPathComponent("dispatch-recovery-" + UUID().uuidString + ".json")
        }
        do { try bytes.write(to: backup, options: .withoutOverwriting) }
        catch {
            // Two readers may discover the same damaged file at once.
            if (try? contents(backup)) != bytes { throw error }
        }
    }

    /// Lock the stable sidecar because atomic replacement changes the ledger's inode.
    private func coordinated<T>(at file: URL, _ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = Darwin.open(file.appendingPathExtension("lock").path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        return try operation()
    }
    func update(_ edit: (inout StationProfile) -> Void) {
        mutex.withLock {
            let before = current
            var submitted = before
            edit(&submitted)
            current = rules.merge(submitted, since: before, onto: current)
            current.needsRepair = false
            guard let file = destination else { return }
            do {
                try coordinated(at: file) {
                    var bytesBefore: Data?, recovery = false, missedCheckpoint = false
                    let combined: StationProfile
                    switch try inspect(file) {
                    case .clean(let disk, let bytes):
                        bytesBefore = bytes
                        combined = bytes == committedData ? current : rules.merge(current, since: committed, onto: disk)
                    case .missing:
                        combined = rules.merge(current, since: committed, onto: recoveryBase(file))
                    case .damaged(let partial, let bytes):
                        try archive(bytes, for: file)
                        combined = rules.merge(current, since: committed, onto: recover(partial, file: file))
                        recovery = true
                    }
                    let encoded = try encoder.encode(combined)
                    let backup = file.appendingPathExtension("previous")
                    var checkpoint: Data?
                    if encoded != bytesBefore {
                        if let bytesBefore {
                            do { try bytesBefore.write(to: backup, options: .atomic); checkpoint = bytesBefore }
                            catch { missedCheckpoint = true }
                        }
                        try encoded.write(to: file, options: .atomic)
                        if bytesBefore == nil, !FileManager.default.fileExists(atPath: backup.path) {
                            do { try encoded.write(to: backup, options: .atomic); checkpoint = encoded }
                            catch { missedCheckpoint = true }
                        }
                    }
                    current = combined
                    committed = combined
                    committedData = encoded
                    checkpointAtCommit = checkpoint ?? (try? contents(backup))
                    if missedCheckpoint { message = "航簿已保存，上一版备份暂未更新。" }
                    else { message = recovery ? "航簿已恢复可读记录，原文件已另存。" : nil }
                }
            } catch LedgerError.unsupportedRevision { message = Self.versionMessage }
            catch { message = "航簿暂未写入磁盘，本次进度仍在内存中。" }
        }
    }
    func save(_ trip: MistVoyage) {
        update { profile in
            let id = trip.level.id
            profile.currentID = id
            if trip.delivered {
                if profile.winningRoutes[id] == nil || trip.totalBeats < (profile.records[id] ?? .max) {
                    profile.records[id] = trip.totalBeats
                    profile.winningRoutes[id] = trip.history
                }
                profile.journeys.removeValue(forKey: id)
            } else { profile.journeys[id] = trip.history }
        }
    }
}
