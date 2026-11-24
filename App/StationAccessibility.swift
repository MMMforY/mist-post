import AppKit

/// Mirrors the drawn hit targets. A screen change replaces its tree; a tide beat only
/// changes what the existing elements say. Screen coordinates are resolved at query time.
@MainActor
final class StationAccessibility {
    fileprivate enum Item: Hashable {
        case reading, ship, atlas, landmarks, row(Int), tide, ports, neighbor(MistMove), control(DeskAction, Int)
    }
    private struct Scene: Equatable {
        let desk: Desk
        let drawer: Drawer?
        let chapter: Int
        let route: Int
        let wireCode: String?
        @MainActor init(_ view: StationView) {
            desk = view.desk
            drawer = view.drawer
            chapter = view.chapter
            route = view.shownTrip.level.id
            wireCode = view.desk == .telegraph ? view.selectedWire?.code : view.wireID
        }
    }
    private struct Tide: Equatable {
        let beat: Int
        let position: MistPoint
        let echoes: Int
        let stamps: Int
        let preview: Int?
    }

    fileprivate weak var host: StationView?
    private var scene: Scene?
    private var actions: [DeskAction] = []
    private var elements: [Item: StationAXNode] = [:]
    private var frontToBack: [StationAXNode] = []
    private var selected: Item?
    private var previousKeyFocus: DeskAction?
    private var lastTide: Tide?
    private var toggleBits = 0

    init(_ view: StationView) { host = view }

    /// On unchanged animation frames this compares the short action sequence and four integers.
    func didDraw() {
        guard let view = host else { return }
        let now = Scene(view)
        let differentScene = scene != now
        let differentActions = !view.targets.elementsEqual(actions, by: { $0.action == $1 })
        if differentScene || differentActions {
            let hadScene = scene != nil
            if differentScene {
                elements.removeAll()
                selected = nil
                previousKeyFocus = nil
                lastTide = nil
            }
            scene = now
            actions = view.targets.map(\.action)
            buildTree(view)
            if hadScene, view.window != nil { NSAccessibility.post(element: view, notification: .layoutChanged) }
        }
        let keyFocus = view.keyboardFocus ? view.focused : nil
        if keyFocus != previousKeyFocus {
            previousKeyFocus = keyFocus
            if let keyFocus, let node = frontToBack.first(where: { $0.action == keyFocus }) {
                selected = node.item
                if view.window != nil { NSAccessibility.post(element: node, notification: .focusedUIElementChanged) }
            }
        }
        if view.drawer == .preferences {
            let flags = preferenceBits(view)
            let changed = flags ^ toggleBits
            if changed != 0, !differentScene, view.window != nil {
                for (index, action) in [DeskAction.sound, .trails, .contrast, .motion].enumerated()
                where changed & (1 << index) != 0 {
                    if let node = elements[.control(action, 0)] { NSAccessibility.post(element: node, notification: .valueChanged) }
                }
            }
            toggleBits = flags
        }
        guard view.drawer == nil, view.desk == .sailing || view.desk == .replay else { return }
        let game = view.shownTrip
        let state = Tide(beat: game.beat, position: game.position, echoes: game.echoes.count, stamps: game.stamped.count, preview: view.previewBeat)
        guard state != lastTide else { return }
        let prior = lastTide
        lastTide = state
        guard let prior, view.window != nil, !view.replayRunning else { return }
        if let ship = elements[.ship] { NSAccessibility.post(element: ship, notification: .valueChanged) }
        if view.desk == .sailing, view.lastEvent.isEmpty, state.beat == prior.beat + 1,
           state.echoes == prior.echoes, NSWorkspace.shared.isVoiceOverEnabled {
            let choices = cardinal.filter { playable($0, game) }.map(\.direction).joined(separator: "、")
            let exits = choices.isEmpty ? "" : "。可向" + choices
            view.announce("第\(state.beat)拍，\(coordinate(state.position))，" + tile(game.position, in: game, at: state.beat) + exits)
        }
    }

    var focusedElement: Any? {
        guard let selected, let node = elements[selected], isCurrent(node) else { return nil }
        return node
    }

    func hitTest(_ screenPoint: NSPoint) -> Any? {
        frontToBack.first { isCurrent($0) && $0.accessibilityFrame().contains(screenPoint) }
    }

    private let cardinal: [MistMove] = [.north, .east, .south, .west]
    private let portMapFrame = NSRect(x: 30, y: 177, width: 797, height: 491)

    private func buildTree(_ view: StationView) {
        let chartVisible = view.drawer == nil && (view.desk == .sailing || view.desk == .replay)
        var previous = elements
        elements.removeAll(keepingCapacity: true)
        func node(_ item: Item, parent: StationAXNode? = nil) -> StationAXNode {
            let result: StationAXNode
            if let reused = previous.removeValue(forKey: item) { result = reused }
            else {
                switch item {
                case .neighbor, .control: result = StationAXButton(item, self)
                default: result = StationAXNode(item, self)
                }
            }
            result.setAccessibilityParent(parent as Any? ?? view)
            elements[item] = result
            return result
        }
        var primary = [node(.reading)], headers: [StationAXNode] = [], body: [StationAXNode] = []
        var ticks: [StationAXNode] = [], rows: [StationAXNode] = [], steps: [StationAXNode] = []
        var mapGroup: StationAXNode?, tideGroup: StationAXNode?
        let portsGroup = view.desk == .routes && view.drawer == nil ? node(.ports) : nil
        var ports: [StationAXNode] = []
        if chartVisible {
            primary.append(node(.ship))
            if view.desk == .sailing {
                for direction in cardinal where !actions.contains(.move(direction)) {
                    steps.append(node(.neighbor(direction)))
                }
                primary += steps
            }
            let atlas = node(.atlas)
            rows = [node(.landmarks, parent: atlas)] + (0..<view.shownTrip.level.height).map { node(.row($0), parent: atlas) }
            atlas.setAccessibilityChildren(rows)
            atlas.setAccessibilityChildrenInNavigationOrder(rows)
            mapGroup = atlas
            if actions.contains(where: { switch $0 { case .preview, .replaySeek: return true; default: return false } }) { tideGroup = node(.tide) }
        }
        var seen: [DeskAction: Int] = [:]
        var buttons: [StationAXNode] = []
        for (index, target) in view.targets.enumerated() {
            let occurrence = seen[target.action, default: 0]
            seen[target.action] = occurrence + 1
            let isTick: Bool
            switch target.action { case .preview, .live, .replaySeek: isTick = chartVisible; default: isTick = false }
            let isPort: Bool
            if case .port = target.action { isPort = portsGroup != nil && portMapFrame.intersects(target.rect) } else { isPort = false }
            let parent = isPort ? portsGroup : (isTick ? tideGroup : nil)
            let item = node(.control(target.action, occurrence), parent: parent)
            item.targetIndex = index
            buttons.append(item)
            if isPort { ports.append(item) }
            else if isTick { ticks.append(item) }
            else if (view.drawer == nil && target.rect.maxY <= 65) || (target.action == .dismiss && target.rect.minY < 175) { headers.append(item) }
            else { body.append(item) }
        }
        if let portsGroup {
            portsGroup.setAccessibilityChildren(ports)
            portsGroup.setAccessibilityChildrenInNavigationOrder(ports)
            primary.append(portsGroup)
        }
        primary += body
        if let mapGroup { primary.append(mapGroup) }
        if let tideGroup {
            tideGroup.setAccessibilityChildren(ticks)
            tideGroup.setAccessibilityChildrenInNavigationOrder(ticks)
            primary.append(tideGroup)
        }
        primary += headers
        view.setAccessibilityChildren(primary)
        view.setAccessibilityChildrenInNavigationOrder(primary)
        frontToBack = Array(buttons.reversed()) + steps
        if let ship = elements[.ship] { frontToBack.append(ship) }
        frontToBack += rows.filter { if case .row = $0.item { return true }; return false }
        for extra in [mapGroup, tideGroup, portsGroup, elements[.reading]].compactMap({ $0 }) { frontToBack.append(extra) }
        if let selected, elements[selected] == nil { self.selected = nil }
    }

    fileprivate func isCurrent(_ node: StationAXNode) -> Bool {
        guard let host, scene == Scene(host), elements[node.item] === node else { return false }
        if case .control(.route(let id), _) = node.item, host.desk == .routes { return id == host.selectedPort }
        return true
    }

    fileprivate func target(_ node: StationAXNode) -> DeskTarget? {
        guard let view = host, let index = node.targetIndex, view.targets.indices.contains(index),
              case .control(let action, _) = node.item, view.targets[index].action == action else { return nil }
        return view.targets[index]
    }

    fileprivate func enabled(_ node: StationAXNode) -> Bool {
        guard let view = host, isCurrent(node) else { return false }
        switch node.item {
        case .neighbor(let move): return playable(move, view.voyage)
        case .control(let action, _):
            guard let target = target(node), target.enabled else { return false }
            if case .move(let move) = action { return playable(move, view.voyage) }
            if action == .record { return view.voyage.canRecord }
            if action == .undo { return view.voyage.canUndo }
            return true
        default: return true
        }
    }

    private func playable(_ move: MistMove, _ game: MistVoyage) -> Bool {
        !game.delivered && game.obstruction(at: game.position.moved(move), arrivingAt: game.beat + 1, with: game.stamped) == nil
    }

    fileprivate func press(_ node: StationAXNode) -> Bool {
        guard let view = host, enabled(node), let action = node.action else { return false }
        view.act(action)
        return true
    }

    fileprivate func setFocus(_ value: Bool, on node: StationAXNode) {
        guard let view = host, isCurrent(node) else { return }
        if !value {
            if selected == node.item { selected = nil }
            return
        }
        let wasFocused = selected == node.item
        selected = node.item
        if let target = target(node), target.enabled {
            view.focused = target.action
            // The view's keyboard ring identifies an action; VoiceOver's ring can also
            // distinguish two controls that happen to perform the same action.
            view.keyboardFocus = view.targets.filter { $0.action == target.action }.count == 1
            previousKeyFocus = view.keyboardFocus ? target.action : nil
        } else {
            view.focused = nil
            view.keyboardFocus = false
            previousKeyFocus = nil
        }
        view.window?.makeFirstResponder(view)
        view.needsDisplay = true
        if !wasFocused, view.window?.isKeyWindow == true { NSAccessibility.post(element: node, notification: .focusedUIElementChanged) }
    }

    fileprivate func isFocused(_ node: StationAXNode) -> Bool { isCurrent(node) && selected == node.item }

    fileprivate func help(_ node: StationAXNode) -> String? {
        guard let view = host, isCurrent(node), let action = node.action else { return nil }
        let game = view.voyage
        switch action {
        case .move(let move):
            return game.obstruction(at: game.position.moved(move), arrivingAt: game.beat + 1, with: game.stamped)?.message
        case .record where !game.canRecord:
            if game.level.echoLimit == 0 { return "本航线无需船影。" }
            return game.echoes.count == game.level.echoLimit ? MistBlock.echoLimit.message : MistBlock.noRoute.message
        case .port(let id) where !view.store.unlocked(id): return "选取后可以查看这封信的航件。送达上一港后可以启航。"
        default: return nil
        }
    }

    fileprivate func chosen(_ node: StationAXNode) -> Bool {
        guard let view = host, isCurrent(node), let action = node.action else { return false }
        switch action {
        case .port(let id): return id == view.selectedPort && target(node).map { portMapFrame.intersects($0.rect) } == true
        case .replayLeg(let index): return index == view.shownTrip.echoes.count
        case .replaySeek(let step): return step == view.replayIndex
        case .chapter(let id): return id == view.chapter
        case .preview(let beat): return beat == (view.previewBeat ?? view.voyage.beat)
        default: return false
        }
    }

    private func preferenceBits(_ view: StationView) -> Int {
        let p = view.store.profile
        return (p.soundOn ? 1 : 0) | (p.trails ? 2 : 0) | (p.contrast ? 4 : 0) | (p.lowMotion ? 8 : 0)
    }

    fileprivate func role(_ item: Item) -> NSAccessibility.Role {
        switch item {
        case .atlas, .tide, .ports: return .group
        case .neighbor: return .button
        case .control(let action, _):
            if host?.drawer == .preferences && [.sound, .motion, .trails, .contrast].contains(action) { return .checkBox }
            return .button
        default: return .staticText
        }
    }

    fileprivate func name(_ node: StationAXNode) -> String? {
        guard let view = host, isCurrent(node) else { return nil }
        let game = view.shownTrip
        switch node.item {
        case .ports: return "群岛港口，选取一港查看航件"
        case .atlas: return "整幅海图，航标位置和逐行水道"
        case .tide: return "潮表，逐拍查看船影与闸门"
        case .neighbor(let move):
            let point = game.position.moved(move)
            let inside = (0..<game.level.width).contains(point.x) && (0..<game.level.height).contains(point.y)
            let destination = inside ? coordinate(point) + "，" + tile(point, in: game, at: game.beat + 1) : "海图边界"
            return "向" + move.direction + "，" + destination
        case .control(let action, _):
            guard let target = target(node) else { return nil }
            if view.drawer == .preferences {
                switch action {
                case .sound: return "港湾声景"
                case .trails: return "绘制航迹"
                case .contrast: return "高对比海图"
                case .motion: return "减少动态"
                default: break
                }
            }
            switch action {
            case .preview(let beat):
                let prefix = beat == game.beat ? "现在，第\(beat)拍" : "预览第\(beat)拍"
                return game.echoes.isEmpty ? prefix : prefix + "。" + echoText(game, at: beat)
            case .port(let id) where id == view.selectedPort && portMapFrame.intersects(target.rect): return target.label + "，当前选中"
            case .chapter(let number) where number == view.chapter: return target.label + "，当前航区"
            case .route(let id), .letter(let id): return "航线\(id)，" + target.label
            default: return target.label
            }
        default: return nil
        }
    }

    fileprivate func value(_ node: StationAXNode) -> Any? {
        guard let view = host, isCurrent(node) else { return nil }
        let game = view.shownTrip
        switch node.item {
        case .reading: return reading(view)
        case .ship:
            let stamps = game.level.stamps.isEmpty ? "" : "。邮戳\(game.stamped.count)枚，共\(game.level.stamps.count)枚"
            let echoes = game.level.echoLimit == 0 ? "" : "。船影\(game.echoes.count)艘，最多\(game.level.echoLimit)艘"
            let forecast = view.previewBeat.map { "。正在看第\($0)拍。" + echoText(game, at: $0) } ?? ""
            return "邮船\(coordinate(game.position))，\(tile(game.position, in: game, at: game.beat))。第\(game.beat)拍，共\(game.level.turnLimit)拍。灯塔\(coordinate(game.level.harbor))" + stamps + echoes + forecast
        case .landmarks:
            var points: [String] = []
            let beat = view.previewBeat ?? game.beat
            for y in 0..<game.level.height {
                for x in 0..<game.level.width {
                    let p = MistPoint(x: x, y: y)
                    let kind = game.level.tile(at: p)
                    if kind != .land && kind != .water { points.append(coordinate(p) + " " + tile(p, in: game, at: beat)) }
                }
            }
            return "海图\(game.level.width)列，\(game.level.height)行，北方朝上。" + points.joined(separator: "。")
        case .row(let y): return rowText(y, game: game, at: view.previewBeat ?? game.beat)
        case .control(let action, _) where view.drawer == .preferences:
            switch action {
            case .sound: return NSNumber(value: view.store.profile.soundOn)
            case .trails: return NSNumber(value: view.store.profile.trails)
            case .contrast: return NSNumber(value: view.store.profile.contrast)
            case .motion: return NSNumber(value: view.store.profile.lowMotion)
            default: return nil
            }
        default: return nil
        }
    }

    private func coordinate(_ point: MistPoint) -> String { column(point.x) + String(point.y + 1) }
    private func column(_ x: Int) -> String { String(UnicodeScalar(65 + max(0, x) % 26)!) }

    private func tile(_ point: MistPoint, in game: MistVoyage, at beat: Int) -> String {
        switch game.level.tile(at: point) {
        case .water: return "水道"
        case .land: return "陆地"
        case .origin: return "出发港"
        case .harbor: return game.stamped == game.level.stamps ? "收信灯塔" : "收信灯塔，尚缺邮戳"
        case .stamp: return game.stamped.contains(point) ? "已盖邮戳站" : "待盖邮戳站"
        case .buoy(let id): return MistLevel.signalName(id) + "铃标"
        case .gate(let id): return MistLevel.signalName(id) + "闸门，" + (game.gateOpen(id, at: beat) ? "开启" : "关闭")
        }
    }

    private func echoText(_ game: MistVoyage, at beat: Int) -> String {
        let echoes = game.echoPositions(at: beat).enumerated().map { "船影\($0.offset + 1)在\(coordinate($0.element))" }
        guard !echoes.isEmpty else { return "尚无船影" }
        let opened = (0..<3).filter { game.gateOpen($0, at: beat) }.map(MistLevel.signalName)
        return echoes.joined(separator: "，") + (opened.isEmpty ? "，没有闸门开启" : "，" + opened.joined(separator: "、") + "闸门开启")
    }

    private func rowText(_ y: Int, game: MistVoyage, at beat: Int) -> String {
        var pieces: [String] = []
        var left = 0
        while left < game.level.width {
            let text = tile(.init(x: left, y: y), in: game, at: beat)
            var right = left
            while right + 1 < game.level.width, tile(.init(x: right + 1, y: y), in: game, at: beat) == text { right += 1 }
            let range = right == left ? column(left) : column(left) + "到" + column(right)
            pieces.append(range + "，" + text)
            left = right + 1
        }
        return "第\(y + 1)行。" + pieces.joined(separator: "。")
    }

    private func reading(_ view: StationView) -> String {
        if let drawer = view.drawer {
            switch drawer {
            case .afterpost: return "港民来图。三位老寄件人送来了手绘航线，选一张收入海图匣即可启航。"
            case .lesson: return "港内演练。"+(view.lesson?.caption ?? "")
            case .preferences: return "航舱设置"
            case .restart: return "从第一拍重新启航？本航线的船影和进行中的航程会清空。已送达的信件和最佳航程记录会保留。"
            case .guide(let page):
                let pages = ["航行与投递。用方向键或WASD向北、东、南、西航行，每次一格。出发港的邮船载着信，驶入收信灯塔完成投递。陆地无法通行。有邮戳任务时，本轮须经过全部邮戳站。",
                             "把昨天的船留在海上。先驶上铃标，按E留影返航。上一程的船影逐拍重走原路，到达末格后停留。船影在铃标上的那一拍，你便能驶入对应水闸。一号铃敲一声，二号两声，三号三声。",
                             "读懂下一拍。按空格候一拍，船影继续前进。潮表可以预览任一拍的船影和闸门。按Z撤回上一步，刚留影也可撤回。按H获取下一步提示，重航可以重新规划。"]
                return "航员手册，第\(page + 1)页，共\(pages.count)页。" + (pages.indices.contains(page) ? pages[page] : "")
            }
        }
        switch view.desk {
        case .cover:
            return "雾信航局。用上一轮潮汐的船影，送达这一封信。已投递\(view.store.profile.records.count)封，共\(MistCampaign.levels.count)封。" + (view.store.notice ?? "")
        case .sailing, .replay:
            let g = view.shownTrip
            let replay = view.desk == .replay ? "航程回放，操作\(view.replayIndex)，共\(view.replayRoute.count)步。" : ""
            let hint = view.desk == .sailing ? view.hint.map { "。领航提示，" + $0.text } ?? "" : ""
            let event = view.desk == .sailing && !view.lastEvent.isEmpty && view.clock - view.lastEventTime < 4 ? "。" + view.lastEvent : ""
            let route = g.level.id < 0 ? "自绘海图，"+g.level.sender : g.level.id == 0 ? "远洋电报，" + (view.wireID ?? "") : "第\(g.level.id)航线，\(g.level.district)"
            return replay + route + "，\(g.level.title)。寄往\(g.level.recipient)。\(g.level.briefing)" + hint + event + (view.store.notice ?? "")
        case .letter(let id):
            guard let l = MistCampaign.levels.first(where: { $0.id == id }) else { return "收信册" }
            let beats = view.letterReturn == .sailing ? view.voyage.totalBeats : view.store.profile.records[id] ?? 0
            return "\(l.title)。致\(l.recipient)。\(l.letter)　\(l.sender)。航程\(beats)拍，参考航程\(l.par)拍。"
        case .telegraph:
            guard view.wireUnlocked else { return "电报台。外港联络尚待接通。送达盐风外港的四封信后，即可接收每日航线或输入电码。" }
            guard let wire = view.selectedWire else { return "电报台" }
            return "电报台。电码\(wire.code)。\(wire.motif)。\(wire.level.briefing)。船影最多\(wire.level.echoLimit)艘，潮限\(wire.level.turnLimit)拍，参考航程\(wire.level.par)拍。" + (view.wireNotice ?? "")
        case .workshop:
            let s = view.studio
            let p = s.cursor ?? s.paper.level.origin
            return "制图室。"+s.draft.title+"。画笔"+s.brush.label+"。光标"+view.chartCoordinate(p)+"，"+view.stationName(at:p,game:s.paper)+"。方向键移动光标，空格落笔，Z撤回编辑。"+s.message
        case .chartCase:
            let s = view.studio
            return "海图匣。已收存"+String(s.volumes.count)+"张海图。"+(s.selection.flatMap { s.volumes[$0]?.level.title } ?? "")+"。"+s.message
        case .studioReceipt:
            return "验航回执。"+(view.studio.active?.level.letter ?? "")+"。本次航程"+String(view.voyage.totalBeats)+"拍。"
        case .telegramReceipt:
            guard let wire = view.activeWire else { return "远洋电报已妥投" }
            return "远洋电报已妥投。\(wire.code)。\(wire.motif)。本次航程\(view.voyage.totalBeats)拍，留影\(view.voyage.echoes.count)艘。" + (view.wireNotice ?? "")
        case .finale: return "总局回函。致最后一位航员。今夜，十二扇窗都亮了。有人把邮戳压在枕下，有人开始修桥。你留在海上的船影还守着那些铃。下一次起雾，港里的人知道该听哪里。雾信航局谨上。"
        case .routes:
            guard let level = MistCampaign.levels.first(where: { $0.id == view.selectedPort }) else { return "群岛航路簿" }
            let condition: String
            if let score = view.store.profile.records[level.id] { condition = "已投递，最佳航程\(score)拍" }
            else if view.store.unlocked(level.id) { condition = "可启航，最多\(level.echoLimit)艘船影，每潮\(level.turnLimit)拍" }
            else { condition = "完成第\(level.id - 1)条航路后开启" }
            return "群岛航路簿。当前第\(level.id)港，\(level.district)，\(level.title)。收信人\(level.recipient)。\(level.briefing)　\(condition)。已投递\(view.store.profile.records.count)封，共\(MistCampaign.levels.count)封。"
        default:
            if view.desk == .album { return "收信册。已投递\(view.store.profile.records.count)封，共\(MistCampaign.levels.count)封。" }
            return "雾信航局"
        }
    }

    fileprivate func screenFrame(_ node: StationAXNode) -> NSRect {
        guard let view = host, let window = view.window, isCurrent(node) else { return .zero }
        let game = view.shownTrip
        let frame: NSRect
        switch node.item {
        case .control: guard let target = target(node) else { return .zero }; frame = target.rect
        case .ports: frame = portMapFrame
        case .tide: frame = R(28, 589, 808, 140)
        case .atlas, .landmarks: frame = view.chartRect
        case .ship: frame = cellFrame(game.position, in: view, game: game)
        case .neighbor(let dir): frame = cellFrame(game.position.moved(dir), in: view, game: game).intersection(view.chartRect)
        case .row(let row):
            frame = cellFrame(.init(x: 0, y: row), in: view, game: game).union(cellFrame(.init(x: game.level.width - 1, y: row), in: view, game: game))
        case .reading:
            if view.drawer != nil { frame = R(276, 203, 645, 330) }
            else if view.desk == .sailing || view.desk == .replay { frame = R(860, 93, 312, 480) }
            else if case .letter = view.desk { frame = R(150, 200, 568, 369) }
            else if view.desk == .finale { frame = R(136, 172, 547, 426) }
            else if view.desk == .telegramReceipt { frame = R(197, 161, 802, 348) }
            else if view.desk == .telegraph { frame = R(42, 267, 686, 341) }
            else if view.desk == .routes { frame = R(850, 177, 320, 403) }
            else if view.desk == .cover { frame = R(55, 209, 540, 260) }
            else { frame = R(42, 92, 768, 137) }
        }
        if frame.isNull || frame.isEmpty { return .zero }
        return window.convertToScreen(view.convert(view.viewRect(frame), to: nil))
    }

    private func cellFrame(_ p: MistPoint, in view: StationView, game: MistVoyage) -> NSRect {
        let center = view.chart.center(of: p, in: view.chartRect, game: game)
        let diagonal = view.chart.center(of: .init(x: p.x + 1, y: p.y + 1), in: view.chartRect, game: game)
        let size = NSSize(width: diagonal.x - center.x, height: diagonal.y - center.y)
        return NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

@MainActor
fileprivate class StationAXNode: NSAccessibilityElement, @preconcurrency NSAccessibilityElementProtocol {
    let item: StationAccessibility.Item
    weak var tree: StationAccessibility?
    var targetIndex: Int?
    var action: DeskAction? {
        switch item {
        case .control(let action, _): return action
        case .neighbor(let move): return .move(move)
        default: return nil
        }
    }

    init(_ item: StationAccessibility.Item, _ tree: StationAccessibility) {
        self.item = item
        self.tree = tree
        super.init()
        setAccessibilityElement(true)
        setAccessibilityRole(tree.role(item))
    }
    override func accessibilityIdentifier() -> String { "mistpost.\(item)" }
    override func accessibilityParent() -> Any? { super.accessibilityParent() }
    override func accessibilityWindow() -> Any? { tree?.host?.window }
    override func accessibilityTopLevelUIElement() -> Any? { tree?.host?.window }
    override func accessibilityFrame() -> NSRect { tree?.screenFrame(self) ?? .zero }
    override func accessibilityLabel() -> String? { tree?.name(self) }
    override func accessibilityValue() -> Any? { tree?.value(self) }
    override func accessibilityHelp() -> String? { tree?.help(self) }
    override func isAccessibilitySelected() -> Bool { tree?.chosen(self) == true }
    override func isAccessibilityEnabled() -> Bool { tree?.enabled(self) == true }
    override func isAccessibilityFocused() -> Bool { tree?.isFocused(self) == true }
    override func setAccessibilityFocused(_ focused: Bool) { tree?.setFocus(focused, on: self) }
}

@MainActor
fileprivate final class StationAXButton: StationAXNode {
    override func accessibilityPerformPress() -> Bool { tree?.press(self) == true }
}
