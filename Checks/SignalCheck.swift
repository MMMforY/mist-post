import AppKit

@MainActor
enum SignalCheck {
    static func run(_ view: StationView, folder: URL) throws {
        let level = MistCampaign.levels[1]
        view.start(level.id)
        view.handleKey(18,character:"1")
        let buoys = level.stations(of:.buoy(0)), gates = level.stations(of:.gate(0))
        precondition(!buoys.isEmpty && !gates.isEmpty && view.signalInspection?.points == buoys+gates)
        precondition(view.lastEvent.contains(view.chartCoordinate(gates[0])) && view.voyage.history.isEmpty)
        try qaSnapshot(view,to:folder.appendingPathComponent("signal-before.png"))
        precondition(view.targets.contains { $0.action == .signal(0) && $0.enabled })
        view.handleKey(20,character:"3")
        precondition(view.signalInspection == nil && view.lastEvent.contains("没有"))
        for command in level.guide {
            view.operate(command)
            if command == .record { break }
        }
        let before = view.voyage.history
        view.inspect(buoys[0],game:view.voyage)
        let schedule = view.bellIntervals(0,game:view.voyage)
        precondition(!schedule.isEmpty && view.lastEvent.contains(schedule[0]))
        precondition(view.voyage.history == before)
        try qaSnapshot(view,to:folder.appendingPathComponent("signal-after.png"))
        view.act(.undo)
        precondition(view.signalInspection == nil)
        view.start(1)
        precondition(view.signalInspection == nil && view.shownTrip.level.signalIDs.isEmpty)
        print("PASS paired signal positions, recorded tide windows, absent signal, undo and route change")
    }
}
