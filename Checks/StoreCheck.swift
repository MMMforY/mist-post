import Foundation

/// Two worker processes use the same on-disk path. All fixtures live under a fresh temporary directory.
enum StoreCheck {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static func check(_ test: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !test() { throw Failure(description: message) }
    }
    private static func trip(_ id: Int, _ commands: [MistCommand]? = nil) throws -> MistVoyage {
        let level = MistCampaign.levels[id - 1]
        guard let result = MistVoyage(level: level, replay: commands ?? level.guide) else { throw Failure(description: "Fixture voyage \(id) is invalid") }
        return result
    }
    private static func JSON(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: .sortedKeys) }
    private static func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    private static func slowRoute(_ l: MistLevel) throws -> [MistCommand] {
        for index in l.guide.indices {
            var commands = l.guide
            commands.insert(.move(.wait), at: index)
            if MistVoyage(level: l, replay: commands)?.delivered == true { return commands }
        }
        throw Failure(description: "Fixture has no slower delivery")
    }

    static func run() throws {
        let env = ProcessInfo.processInfo.environment
        if let role = env["MIST_POST_TEST_PEER"], let directory = env["MIST_POST_TEST_DIRECTORY"], let number = Int(role) {
            guard (1...2).contains(number) else { throw Failure(description: "Unknown peer number") }
            try peer(number, directory: URL(fileURLWithPath: directory, isDirectory: true))
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mistpost-store-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try archiveEncoding(folder)
        try migrationAndDamage(folder)
        try recoverAndRetry(folder)
        try competingCopies(folder)
        print("PASS clean and legacy ledgers, independent malformed fields/proofs, future-format protection, corrupt-file recovery, disk-failure retry, opaque workshop data and concurrent process saves")
    }

    private static func archiveEncoding(_ folder: URL) throws {
        let file = folder.appendingPathComponent("season.json")
        let store = DispatchStore(file:file)
        let a = MistChallenge.make(seed:27), b = MistChallenge.make(seed:76)
        let stamp = Date(timeIntervalSinceReferenceDate:777)
        func compare() throws {
            let written = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? NSDictionary
            let reference = try object(store.profile) as? NSDictionary
            try check(written != nil && written == reference,"archive JSON differs from Codable representation")
            try check(DispatchStore(file:file).profile.telegrams == store.profile.telegrams,"reopen changed a cached replay")
        }
        store.update { $0.trails = false }
        try compare()
        store.update { $0.telegrams = [:] }
        try compare()
        store.update { $0.telegrams = [
            a.code:TelegramEntry(draft:[],best:a.level.guide,visited:stamp),
            b.code:TelegramEntry(draft:[],best:b.level.guide,visited:stamp)
        ] }
        try compare()
        store.update { $0.contrast = true }
        try compare()
        store.update { $0.telegrams?[b.code]?.draft = Array(b.level.guide.prefix(2)) }
        try compare()
        store.update { $0.telegrams?.removeValue(forKey:a.code) }
        try compare()
        store.update { $0.telegrams = nil }
        try compare()
    }

    private static func migrationAndDamage(_ folder: URL) throws {
        let file = folder.appendingPathComponent("partial.json")
        let one = try trip(1), two = try trip(2), first = Array(MistCampaign.levels[2].guide.prefix(1))
        let wire = MistChallenge.make(seed: 17)
        let raw: [String: Any] = [
            "currentID": 9, "soundOn": false,
            "records": ["1": 999, "5": 1],
            "winningRoutes": ["1": try object(one.history), "2": [["bad": 7]], "5": try object(first)],
            "journeys": ["2": try object(two.history), "3": try object(first), "8": [["bad": 7]]],
            "workshopDraft": Data([0, 255, 23]).base64EncodedString(),
            "workshopCharts": ["a": Data([3, 8]).base64EncodedString(), "broken": "???!"],
            "telegrams": [wire.code.lowercased(): ["best": try object(wire.level.guide), "draft": [["bad": 7]], "visited": 42],
                          "wrong code": ["best": try object(wire.level.guide), "draft": [], "visited": 40]]
        ]
        try JSON(raw).write(to: file)
        let store = DispatchStore(file: file), p = store.profile
        try check(p.records == [1: one.totalBeats, 2: two.totalBeats], "bad numeric score or lost valid proof")
        try check(p.winningRoutes[1] == one.history && p.winningRoutes[2] == two.history, "valid delivered draft not recovered")
        try check(p.journeys == [3: first] && p.currentID == 3, "partial draft recovery or invalid continuation")
        try check(!p.soundOn && p.trails && !p.lowMotion && !p.contrast, "missing-field defaults")
        try check(p.workshopDraft == Data([0, 255, 23]) && p.workshopCharts == ["a": Data([3, 8])], "opaque workshop data")
        try check(p.telegrams?.count == 1 && p.telegrams?[wire.code]?.best == wire.level.guide && p.telegrams?[wire.code]?.draft == [], "wire member isolation/canonical code")
        store.update { $0.contrast = true }
        try check(DispatchStore(file: file).profile.records == p.records, "partial repair not durable")
        try check(!store.unlocked(0) && !store.unlocked(13) && !store.unlocked(Int.min), "unknown harbor marked unlocked")
        let scoreFile = folder.appendingPathComponent("legacy.json")
        try JSON(["records": ["1": one.totalBeats + 1], "currentID": 2]).write(to: scoreFile)
        let old = DispatchStore(file: scoreFile)
        try check(old.profile.records[1] == one.totalBeats + 1 && old.profile.winningRoutes[1] == nil, "legacy letter lost or replay invented")
        old.update { $0.trails = false }
        try check(DispatchStore(file: scoreFile).profile.records == old.profile.records, "legacy receipt failed migration round trip")
        old.save(one)
        try check(DispatchStore(file: scoreFile).profile.winningRoutes[1] == one.history, "real replay did not replace legacy receipt")
        let phantom = folder.appendingPathComponent("phantom.json")
        try JSON(["revision": 1, "records": ["1": one.totalBeats]]).write(to: phantom)
        try check(DispatchStore(file: phantom).profile.records.isEmpty, "current-format unverified score unlocked a letter")
    }

    private static func recoverAndRetry(_ folder: URL) throws {
        let file = folder.appendingPathComponent("recovery.json")
        let original = DispatchStore(file: file), one = try trip(1), two = try trip(2)
        original.save(one)
        original.save(two)
        original.update { $0.contrast = true }
        let broken = Data("{partial".utf8)
        try broken.write(to: file, options: .atomic)
        let recovered = DispatchStore(file: file)
        try check(recovered.profile.records == original.profile.records && recovered.notice != nil, "prior valid snapshot not restored")
        try check(try Data(contentsOf: file) == broken, "damaged source replaced on read")
        let rawBackups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("dispatch-recovery-") }
        try check(rawBackups.contains { (try? Data(contentsOf: $0)) == broken }, "exact damaged source unavailable")
        recovered.update { $0.workshopDraft = Data([42]) }
        try check(DispatchStore(file: file).profile.workshopDraft == Data([42]), "failed to resume from recovered state")
        let known = try Data(contentsOf: file)
        let future = Data("{\"revision\":9,\"futureReceipts\":[41]}".utf8)
        try future.write(to: file, options: .atomic)
        let oldApp = DispatchStore(file: file)
        oldApp.update { $0.workshopCharts = ["local": Data([8])] }
        original.update { $0.lowMotion = true }
        try check(try Data(contentsOf: file) == future && oldApp.notice != nil && original.notice != nil, "a future save was overwritten")
        try known.write(to: file, options: .atomic)
        oldApp.update { $0.lowMotion = true }
        let resumed = DispatchStore(file: file).profile
        try check(resumed.workshopCharts?["local"] == Data([8]) && resumed.records == original.profile.records && resumed.lowMotion, "pending edits not recovered after compatible file returned")

        let liveFile = folder.appendingPathComponent("live.json")
        let live = DispatchStore(file: liveFile)
        live.save(one)
        live.save(two)
        try broken.write(to: liveFile, options: .atomic)
        live.update { $0.workshopDraft = Data([51]) }
        try check(DispatchStore(file: liveFile).profile.winningRoutes[2] == two.history, "running copy rolled its latest letter back to the older checkpoint")
        try FileManager.default.removeItem(at: liveFile)
        live.update { $0.lowMotion = true }
        try check(DispatchStore(file: liveFile).profile.workshopDraft == Data([51]), "known current workshop draft lost when primary went missing")

        let obstacle = folder.appendingPathComponent("unavailable")
        try Data([1]).write(to: obstacle)
        let blocked = obstacle.appendingPathComponent("state.json")
        let pending = DispatchStore(file: blocked)
        pending.save(one)
        try check(pending.notice != nil && pending.profile.winningRoutes[1] == one.history, "disk failure lost in-memory progress")
        try FileManager.default.removeItem(at: obstacle)
        let remote = DispatchStore(file: blocked)
        remote.save(two)
        pending.update { $0.trails = false }
        let joint = DispatchStore(file: blocked).profile
        try check(pending.notice == nil && joint.winningRoutes[1] == one.history && joint.winningRoutes[2] == two.history && !joint.trails, "retry lost the other copy's delivery")
    }

    private static func peer(_ number: Int, directory: URL) throws {
        let store = DispatchStore(file: directory.appendingPathComponent("shared.json"))
        try Data().write(to: directory.appendingPathComponent("ready-\(number)"))
        let deadline = Date(timeIntervalSinceNow: 25), go = directory.appendingPathComponent("go")
        while !FileManager.default.fileExists(atPath: go.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        try check(FileManager.default.fileExists(atPath: go.path), "peer barrier timed out")
        for i in 0..<16 {
            store.update { p in
                var charts = p.workshopCharts ?? [:]
                charts["peer-\(number)-\(i)"] = Data([UInt8(number), UInt8(i)])
                p.workshopCharts = charts
            }
        }
        let wire = MistChallenge.make(seed: UInt64(17 + number)), shared = MistChallenge.make(seed: 17)
        let best = number == 1 ? try slowRoute(shared.level) : shared.level.guide
        let sharedDate = Date(timeIntervalSinceReferenceDate: Double(100 + number))
        store.update { profile in
            var wires = profile.telegrams ?? [:]
            wires[wire.code] = TelegramEntry(draft: Array(wire.level.guide.prefix(1)), best: wire.level.guide, visited: sharedDate)
            wires[shared.code] = TelegramEntry(draft: Array(shared.level.guide.prefix(number)), best: best, visited: sharedDate)
            profile.telegrams = wires
            if number == 1 { profile.soundOn = false } else { profile.trails = false }
        }
        let first = MistCampaign.levels[0]
        store.save(try trip(1, number == 1 ? slowRoute(first) : first.guide))
        store.save(try trip(number + 1))
        let partial = Array(MistCampaign.levels[number + 2].guide.prefix(1))
        store.save(try trip(number + 3, partial))
        try check(store.notice == nil, "peer could not write")
    }

    private static func competingCopies(_ folder: URL) throws {
        let file = folder.appendingPathComponent("shared.json")
        let seed = DispatchStore(file: file)
        seed.update { $0.workshopCharts = ["delete": Data([7])]; $0.workshopDraft = Data([9]) }
        let stale = DispatchStore(file: file)
        var children: [Process] = []
        defer { for child in children where child.isRunning { child.terminate(); child.waitUntilExit() } }
        for index in 1...2 {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            child.arguments = Array(CommandLine.arguments.dropFirst())
            var environment = ProcessInfo.processInfo.environment
            environment["MIST_POST_TEST_PEER"] = String(index)
            environment["MIST_POST_TEST_DIRECTORY"] = folder.path
            environment["MIST_POST_SAVE"] = folder.appendingPathComponent("isolated-\(index).json").path
            child.environment = environment
            try child.run()
            children.append(child)
        }
        let ready = (1...2).map { folder.appendingPathComponent("ready-\($0)").path }
        let deadline = Date(timeIntervalSinceNow: 25)
        while !ready.allSatisfy(FileManager.default.fileExists(atPath:)), Date() < deadline, children.allSatisfy(\.isRunning) { Thread.sleep(forTimeInterval: 0.02) }
        try check(ready.allSatisfy(FileManager.default.fileExists(atPath:)), "worker startup failed")
        try Data().write(to: folder.appendingPathComponent("go"))
        for child in children { child.waitUntilExit(); try check(child.terminationStatus == 0, "worker failed") }
        // Submit an edit derived from a pre-fork dictionary, including deletion of a known key.
        stale.update { $0.workshopCharts = ["after": Data([4])]; $0.workshopDraft = nil; $0.contrast = true }
        let final = DispatchStore(file: file).profile
        try check(final.workshopCharts?.count == 33 && final.workshopCharts?["delete"] == nil && final.workshopDraft == nil, "chart merge lost independent additions or tombstones")
        try check(final.winningRoutes[1] == MistCampaign.levels[0].guide && final.records.count == 3 && final.journeys[4] != nil && final.journeys[5] != nil, "per-route drafts or fastest campaign proof lost")
        let shared = MistChallenge.make(seed: 17)
        try check(final.telegrams?.count == 3 && final.telegrams?[shared.code]?.best == shared.level.guide && final.telegrams?[shared.code]?.draft == Array(shared.level.guide.prefix(2)), "per-code drafts or fastest wire proof lost")
        try check(!final.soundOn && !final.trails && final.contrast, "independent preference edits lost")
    }
}
