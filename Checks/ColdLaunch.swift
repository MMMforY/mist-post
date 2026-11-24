import AppKit

/// Run the two phases in different processes against the same isolated file. The
/// reference path is reconstructed from the case number, independently of the save.
@MainActor
enum ColdLaunch {
    static func run(_ view: StationView, phase: String, number: Int) throws -> Never {
        guard ["write","resume"].contains(phase), number >= 0,
              ProcessInfo.processInfo.environment["MIST_POST_SAVE"] != nil else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let creating = phase == "write"
        let kind = number % 4
        let levels = MistCampaign.levels
        let level: MistLevel
        if creating {
            guard view.store.profile.winningRoutes.isEmpty else { throw CocoaError(.fileWriteFileExists) }
            // Populate prerequisites as actual completed voyages.
            let last = kind == 0 ? min(levels.count-1,(number/4)%levels.count) : 4
            for previous in levels.prefix(last) {
                var trip = MistVoyage(level:previous)
                for command in previous.guide { trip.perform(command) }
                view.store.save(trip)
            }
            view.store.update { p in p.lowMotion = number%3==0; p.trails = number%3==1; p.soundOn = false }
        }
        switch kind {
        case 0:
            level = levels[(number/4)%levels.count]
            if creating { view.start(level.id) }
            else { view.act(.depart) }
        case 1,2:
            let wire = MistChallenge.make(seed:UInt64(number)*9576769+148)
            view.act(.wire(.office))
            view.act(.wire(.open(wire.code)))
            view.act(.wire(.launch))
            level = wire.level
        default:
            let url = view.resourceFolder.appendingPathComponent("TideBridge.mistchart")
            let chart = try MistWorkshopChart.open(Data(contentsOf:url))
            if creating { view.receiveChart(from:url) }
            guard view.studio.volumes[chart.fingerprint] != nil else { throw CocoaError(.fileReadCorruptFile) }
            view.act(.studio(.select(chart.fingerprint)))
            view.act(.studio(.launch))
            level = chart.level
        }
        precondition(view.voyage.level.title == level.title && view.desk == .sailing)
        let cut = 1 + (number*19+3)%(level.guide.count-1)
        let prefix = Array(level.guide.prefix(cut))
        if creating {
            for move in prefix { view.operate(move) }
            precondition(view.voyage.history == prefix)
        } else {
            precondition(view.store.profile.lowMotion == (number%3==0))
            precondition(view.store.profile.trails == (number%3==1) && !view.store.profile.soundOn)
            precondition(view.voyage.history == prefix && !view.voyage.delivered)
            view.act(.undo)
            precondition(view.voyage.history == Array(prefix.dropLast()))
            view.operate(prefix.last!)
            for move in level.guide.dropFirst(cut) { view.operate(move) }
            precondition(view.voyage.delivered && view.voyage.history == level.guide)
            switch kind {
            case 0: precondition(view.desk == .letter(level.id))
            case 1,2: precondition(view.desk == .telegramReceipt)
            default: precondition(view.desk == .studioReceipt)
            }
        }
        precondition(view.store.notice == nil)
        print("PASS \(phase) case=\(number) chart=\(level.title) checkpoint=\(cut)/\(level.guide.count)")
        exit(0)
    }
}
