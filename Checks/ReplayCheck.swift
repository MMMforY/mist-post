import AppKit

@MainActor
enum ReplayCheck {
    static func run(_ view: StationView) {
        let campaignBefore = view.store.profile.journeys
        for level in MistCampaign.levels {
            view.act(.replay(level.id))
            // A recorded command separates two different moments: the old ship
            // is on its final square before it, and the new ship is at beat 0 after it.
            var departure = 0
            for (leg, range) in view.replayLegs.enumerated() {
                view.act(.replayLeg(leg))
                precondition(view.replayIndex == departure && view.replayTrip?.beat == 0)
                precondition(view.replayTrip?.echoes.count == leg)
                for index in range.reversed() {
                    view.act(.replaySeek(index))
                    let expected = MistVoyage(level:level,replay:Array(level.guide.prefix(index)))
                    let actual = view.shownTrip
                    precondition(expected?.position == actual.position && expected?.stamped == actual.stamped)
                    precondition(actual.beat == index-departure && actual.echoes.count == leg)
                }
                departure = range.upperBound+1
            }
            precondition(departure == level.guide.count+1)
            view.act(.replaySeek(level.guide.count))
            precondition(view.shownTrip.delivered)
            view.handleKey(126,character:"")
            precondition(view.shownTrip.beat == 0)
            view.handleKey(125,character:"")
            precondition(view.shownTrip.echoes.count == view.replayLegs.count-1)
        }
        let oldClock = view.frozenTime
        view.frozenTime = 100
        view.seekReplay(0)
        view.act(.replayPlay)
        view.frozenTime = 100.22
        view.handleKey(9,character:"v")
        precondition(view.replayRunning && view.replayIndex == 0 && view.replaySpeed == .fast)
        let expectedTick = view.replayClock+view.replaySpeed.interval
        precondition(abs(expectedTick-100.385) < 0.00001)
        view.frozenTime = expectedTick-0.01
        view.tick()
        precondition(view.replayIndex == 0)
        view.frozenTime = expectedTick+0.01
        view.tick()
        precondition(view.replayIndex == 1)
        view.act(.replayPlay)
        view.act(.replaySpeed)
        precondition(!view.replayRunning && view.replayIndex == 1 && view.replaySpeed == .slow)
        view.handleKey(9,character:"v",repeated:true)
        precondition(view.replaySpeed == .slow)
        view.act(.replaySpeed)
        precondition(view.replaySpeed == .normal)
        view.frozenTime = oldClock
        print("PASS replay pace, fractional timing, paused cursor and repeated key suppression")
        precondition(view.store.profile.journeys == campaignBefore)
        print("PASS replay seek at every beat of 12 routes, before and after each recording")
    }
}
