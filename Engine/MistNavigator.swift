import Foundation

private struct RouteKey: Hashable {
    let point: MistPoint
    let stamps: Set<MistPoint>
    let tide: Int
}

private struct RouteNode {
    let point: MistPoint
    let stamps: Set<MistPoint>
    let beat: Int
    let parent: Int
    let move: MistMove
}

extension MistVoyage {
    /// Breadth-first search on position, postmarks and the time-dependent gate schedule.
    /// After the last echo stops moving, later arrivals at the same state add no routes.
    func routeToDelivery() -> [MistMove]? {
        route(to: level.harbor)
    }

    private func route(to target: MistPoint) -> [MistMove]? {
        if position == target { return [] }
        if delivered { return nil }
        let finalEchoBeat = echoes.map { $0.count - 1 }.max() ?? 0
        var queue = [RouteNode(point: position, stamps: stamped, beat: beat, parent: -1, move: .wait)]
        var visited: Set<RouteKey> = [RouteKey(point: position, stamps: stamped, tide: min(beat, finalEchoBeat))]
        var head = 0
        while head < queue.count {
            let index = head
            let state = queue[index]
            head += 1
            let arrival = state.beat + 1
            guard arrival <= level.turnLimit else { continue }
            for move in MistMove.allCases {
                let point = state.point.moved(move)
                guard obstruction(at: point, arrivingAt: arrival, with: state.stamps) == nil else { continue }
                if point == level.harbor && point != target { continue }
                var marks = state.stamps
                if level.stamps.contains(point) { marks.insert(point) }
                let key = RouteKey(point: point, stamps: marks, tide: min(arrival, finalEchoBeat))
                guard visited.insert(key).inserted else { continue }
                if point == target {
                    var route = [move]
                    var ancestor = index
                    while queue[ancestor].parent >= 0 {
                        route.append(queue[ancestor].move)
                        ancestor = queue[ancestor].parent
                    }
                    return route.reversed()
                }
                queue.append(RouteNode(point: point, stamps: marks, beat: arrival, parent: index, move: move))
            }
        }
        return nil
    }

    func hint() -> MistHint {
        if delivered { return MistHint(text: "信已送达，可以拆信了。", point: level.harbor, command: nil) }

        if let command = forwardInstruction() { return instruction(for: command) }

        // A missed turn on an otherwise usable echo arrangement can often be fixed
        // within this voyage. Look for a nearby recovery before returning to the guide.
        let guide = level.guide
        let shared = zip(history, guide).prefix { $0 == $1 }.count
        let divergence = history.count - shared
        var previous = self
        if divergence > 1 {
            for count in 1..<divergence {
                _ = previous.undo()
                let canFinish = previous.routeToDelivery() != nil
                let recentRecording = count <= 3 && previous.echoes.count < level.echoLimit
                if canFinish || (recentRecording && previous.recordingContinuation(in: guide) != nil) {
                    return MistHint(text: "撤回 \(count) 次操作，可以从那一拍重新安排后续航程。",
                                    point: nil, command: nil, undoCount: count)
                }
            }
        }
        return MistHint(text: "撤回 \(divergence) 次操作，就能接回这张航图的参考航线。",
                        point: nil, command: nil, undoCount: divergence)
    }

    private func forwardInstruction() -> MistCommand? {
        // A player's working echo arrangement can have a shorter route than the printed guide.
        if let move = routeToDelivery()?.first { return .move(move) }
        let guide = level.guide
        let shared = zip(history, guide).prefix { $0 == $1 }.count
        if shared == history.count, shared < guide.count { return guide[shared] }
        guard echoes.count < level.echoLimit else { return nil }
        return recordingContinuation(in: guide)
    }

    private func recordingContinuation(in guide: [MistCommand]) -> MistCommand? {
        let recordings = guide.indices.filter { guide[$0] == .record }
        guard echoes.count < recordings.count, let lastRecording = recordings.last else { return nil }
        let start = echoes.isEmpty ? guide.startIndex : recordings[echoes.count - 1] + 1
        let boundary = recordings[echoes.count]

        func finishes(from candidate: MistVoyage, tail: Int) -> Bool {
            var future = candidate
            for command in guide[tail...lastRecording] {
                if case .blocked = future.perform(command) { return false }
            }
            return future.routeToDelivery() != nil
        }

        // Stopping now might already have captured the right bell schedule.
        for index in (start...boundary).reversed() {
            if finishes(from: self, tail: index) { return guide[index] }
        }

        // Rejoin an intended recording at a physical mooring from an alternate
        // approach. Validate the entire future before suggesting its first move.
        var mooring = level.origin
        var moorings = [mooring]
        for command in guide[start..<boundary] {
            guard case .move(let move) = command else { continue }
            mooring = mooring.moved(move)
            moorings.append(mooring)
        }
        for index in (start...boundary).reversed() {
            let intendedBeat = index - start
            guard let approach = route(to: moorings[intendedBeat]) else { continue }
            var candidate = self
            for move in approach { _ = candidate.step(move) }
            if let first = approach.first, finishes(from: candidate, tail: index) { return .move(first) }
            if candidate.beat < intendedBeat {
                let delay = intendedBeat - candidate.beat
                var allowed = true
                for _ in 0..<delay {
                    if case .blocked = candidate.step(.wait) { allowed = false; break }
                }
                if allowed && finishes(from: candidate, tail: index) {
                    return .move(approach.first ?? .wait)
                }
            }
        }
        return nil
    }

    private func instruction(for command: MistCommand) -> MistHint {
        switch command {
        case .record:
            let ending = level.tile(at: position)
            let message: String
            if case .buoy(let id) = ending {
                message = "在\(MistLevel.signalName(id))铃标上留影返航。下一轮的船影会照原路划来，并停在这里。"
            } else {
                message = "选择「留影返航」。下一轮从出发港出发，船影会沿这段航迹重走。"
            }
            return MistHint(text: message, point: position, command: command)
        case .move(.wait):
            return MistHint(text: "选择「候一拍」，让船影和水闸的节拍对齐。",
                            point: position, command: command)
        case .move(let move):
            let next = position.moved(move)
            let text: String
            switch level.tile(at: next) {
            case .gate(let id): text = "下一拍\(MistLevel.signalName(id))钟会响。向\(move.direction)穿过水闸。"
            case .buoy(let id): text = "向\(move.direction)划一格，经过\(MistLevel.signalName(id))铃标。"
            case .stamp where !stamped.contains(next): text = "向\(move.direction)靠岸，盖下中转戳。"
            case .harbor: text = "向\(move.direction)划向收信灯塔，投递这封信。"
            default: text = "沿水道向\(move.direction)划一格。"
            }
            return MistHint(text: text, point: next, command: command)
        }
    }
}
