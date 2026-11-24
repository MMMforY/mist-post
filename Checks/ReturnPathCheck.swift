import AppKit

@MainActor
enum ReturnPathCheck {
    static func run(resources: URL) {
        let view = StationView(store:DispatchStore(file:nil),resources:resources)
        view.frozenTime = 0
        for level in MistCampaign.levels.prefix(4) {
            view.store.save(MistVoyage(level:level,replay:level.guide)!)
        }
        func back() { view.handleKey(53,character:"") }
        func visitTrial() {
            view.act(.routes)
            view.act(.studio(.editor))
            view.act(.studio(.trial))
            precondition(view.voyage.level.id == -1)
            back(); back(); back()
        }

        view.start(2)
        for step in MistCampaign.levels[1].guide.prefix(5) { view.operate(step) }
        let campaign = view.voyage.history
        visitTrial()
        precondition(view.desk == .sailing && view.voyage.level.id == 2 && view.voyage.history == campaign)
        view.act(.album)
        view.act(.letter(1))
        view.act(.replay(1))
        view.seekReplay(3)
        view.act(.album)
        view.act(.letter(2))
        view.act(.replay(2))
        view.seekReplay(5)
        back(); back(); back()
        precondition(view.desk == .replay && view.shownTrip.level.id == 1 && view.replayIndex == 3)
        back(); back(); back()
        precondition(view.desk == .sailing && view.voyage.level.id == 2 && view.voyage.history == campaign)
        precondition(view.store.profile.journeys[2] == campaign)

        let wire = MistChallenge.make(seed:0x2c1464)
        view.act(.wire(.office))
        view.setWire(wire)
        view.act(.wire(.launch))
        let count = wire.level.guide.firstIndex(of:.record)! + 2
        for step in wire.level.guide.prefix(count) { view.operate(step) }
        let before = view.voyage.history
        visitTrial()
        precondition(view.desk == .sailing && view.activeWire?.code == wire.code && view.voyage.level.id == 0)
        precondition(view.voyage.history == before && view.store.profile.telegrams?[wire.code]?.draft == before)
        for step in wire.level.guide.dropFirst(count) { view.operate(step) }
        precondition(view.desk == .telegramReceipt && view.store.profile.telegrams?[wire.code]?.best == wire.level.guide)
        print("PASS campaign and telegram return after workshop trials, nested replays and correct destination save")
    }
}
