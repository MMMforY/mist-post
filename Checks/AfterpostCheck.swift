import AppKit

@MainActor
enum AfterpostCheck {
    static func run(_ view: StationView, folder: URL) throws {
        let locked = StationView(store:DispatchStore(file:nil),resources:view.resourceFolder)
        locked.desk = .finale
        locked.act(.studio(.mailbag))
        precondition(locked.drawer == nil && locked.studio.volumes.isEmpty)
        view.act(.album)
        view.act(.readFinale)
        view.act(.studio(.mailbag))
        precondition(view.drawer == .afterpost && view.afterpost.count == 3)
        try qaSnapshot(view,to:folder.appendingPathComponent("afterpost-envelopes.png"))
        let receipts = view.store.profile.records
        for (index,chart) in view.afterpost.enumerated() {
            precondition(view.targets.contains { $0.action == .studio(.takeMail(index)) && $0.enabled })
            view.act(.studio(.takeMail(index)))
            precondition(view.desk == .chartCase && view.studio.selection == chart.fingerprint)
            view.act(.studio(.launch))
            precondition(view.desk == .sailing && view.voyage.level.title == chart.level.title)
            for move in chart.level.guide { view.operate(move) }
            precondition(view.desk == .studioReceipt && view.voyage.delivered && view.voyage.level.letter == chart.level.letter)
            view.act(.studio(.shelf))
            view.act(.back)
            precondition(view.drawer == .afterpost && view.desk == .finale)
            try qaSnapshot(view,to:folder.appendingPathComponent("afterpost-envelopes.png"))
        }
        precondition(view.store.profile.records == receipts)
        view.act(.studio(.takeMail(0)))
        precondition(view.studio.volumes.count >= 3)
        view.act(.back)
        view.act(.dismiss)
        print("PASS three proven post-campaign charts, gate, delivery, reimport and return")
    }
}
