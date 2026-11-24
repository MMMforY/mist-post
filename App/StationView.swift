import AppKit

enum Desk: Equatable { case cover, sailing, routes, album, letter(Int), finale, replay, telegraph, telegramReceipt, workshop, chartCase, studioReceipt }
enum Drawer: Equatable { case guide(Int), lesson, afterpost, preferences, restart }
enum DeskAction: Hashable {
    case home, depart, routes, album, back, guide, preferences, sound, dismiss
    case route(Int), chapter(Int), letter(Int), next, readFinale, replay(Int)
    case move(MistMove), undo, record, hint, restart, confirmRestart, signal(Int)
    case guidePage(Int), trails, contrast, motion, fullscreen
    case lesson(LessonAction), studio(StudioAction)
    case printLetter(Int), printAtlas, port(Int), wire(WireAction)
    case preview(Int), live, replayPlay, replaySpeed, replayPrevious, replayNext, replayLeg(Int), replaySeek(Int)
}
struct DeskTarget {
    var rect: NSRect
    var action: DeskAction
    var label: String
    var enabled: Bool
}
enum ReplaySpeed: CaseIterable {
    case normal, fast, slow

    var interval: TimeInterval {
        switch self { case .normal: return 0.55; case .fast: return 0.275; case .slow: return 1.1 }
    }
    var label: String {
        switch self { case .normal: return "1×"; case .fast: return "2×"; case .slow: return "0.5×" }
    }
    var next: Self {
        switch self { case .normal: return .fast; case .fast: return .slow; case .slow: return .normal }
    }
}

enum ButtonInk { case primary, paper, dark, clear, selected }

@MainActor
final class StationView: NSView {
    let worldSize = NSSize(width: 1200, height: 750)
    let store: DispatchStore
    lazy var accessDeck = StationAccessibility(self)
    lazy var studio = Cartography(store)
    let chart = HarborChart()
    let audio = HarborAudio()
    let atlasImage: NSImage?
    var selectedPort = 1
    let coverImage: NSImage?
    let stampImages: [NSImage]
    let resourceFolder: URL
    lazy var afterpost: [MistWorkshopChart] = (1...3).compactMap { index in
        let file = resourceFolder.appendingPathComponent("Afterpost").appendingPathComponent(String(index)+".mistchart")
        return (try? Data(contentsOf:file)).flatMap { try? MistWorkshopChart.open($0) }
    }
    var desk = Desk.cover
    var lesson: BellLesson?
    var drawer: Drawer?
    var catalogReturns: [CatalogReturn] = []
    var letterReturn = Desk.album
    var finaleFromAlbum = false
    var chapter = 0
    var activeWire: MistChallenge?
    var selectedWire: MistChallenge?
    var wirePage = 0
    var wireNotice: String?
    var voyage: MistVoyage
    var inspectedPoint: MistPoint?
    var signalInspection: (id:Int, points:[MistPoint])?
    var hint: MistHint?
    var lastEvent = ""
    var lastEventTime: TimeInterval = -100
    private var lastWaterFrame = -1.0
    var motionAt: TimeInterval?
    var hover: NSPoint?
    var targets: [DeskTarget] = []
    var focused: DeskAction?
    var keyboardFocus = false
    var previewBeat: Int?
    var replayRoute: [MistCommand] = []
    private(set) var replayLegs: [ClosedRange<Int>] = []
    var replayIndex = 0
    var replayRunning = false
    var replayClock: TimeInterval = 0
    var replaySpeed = ReplaySpeed.normal
    var replayTrip: MistVoyage?
    var frozenTime: TimeInterval?
    var onDrawError: ((String) -> Void)?
    private var tracking: NSTrackingArea?
    private var refresh: Timer?
    var clock: TimeInterval { frozenTime ?? ProcessInfo.processInfo.systemUptime }
    var scale: CGFloat { min(bounds.width / worldSize.width, bounds.height / worldSize.height) }
    var pad: NSPoint { .init(x:(bounds.width - worldSize.width * scale)/2, y:(bounds.height - worldSize.height * scale)/2) }
    var chartRect: NSRect { R(28,148,808,426) }
    var shownTrip: MistVoyage { desk == .replay ? replayTrip ?? voyage : voyage }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(store: DispatchStore, resources: URL) {
        self.store = store
        resourceFolder = resources
        atlasImage = PressImages.photo(resources.appendingPathComponent("Archipelago.jpg"))
        coverImage = PressImages.photo(resources.appendingPathComponent("FogHarbor.jpg"))
        stampImages = PressImages.stamps(resources.appendingPathComponent("Postage.jpg"))
        let level = MistCampaign.levels.first { $0.id == store.profile.currentID } ?? MistCampaign.levels[0]
        voyage = MistVoyage(level: level, replay: store.profile.journeys[level.id] ?? []) ?? MistVoyage(level: level)
        super.init(frame: R(0,0,1200,750))
        audio.setEnabled(store.profile.soundOn)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("雾信航局")
    }
    required init?(coder: NSCoder) { nil }

    func setRunning(_ active: Bool) {
        audio.setActive(active && frozenTime == nil)
        refresh?.invalidate()
        refresh = nil
        if active && frozenTime == nil {
            let timer = Timer(timeInterval: 1/24, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.008
            RunLoop.main.add(timer, forMode: .common)
            refresh = timer
        } else {
            replayRunning = false
        }
        needsDisplay = true
    }
    func tick() {
        guard window?.occlusionState.contains(.visible) != false, !inLiveResize else { return }
        if desk == .replay && drawer == nil && replayRunning && clock - replayClock >= replaySpeed.interval {
            seekReplay(replayIndex + 1)
        }
        guard (desk == .sailing || desk == .replay), drawer == nil else { return }
        let now = clock
        if !lastEvent.isEmpty && now-lastEventTime >= 4 {
            lastEvent = ""
            inspectedPoint = nil
            signalInspection = nil
            needsDisplay = true
            return
        }
        guard !store.profile.lowMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let gliding = motionAt.map { now-$0 < 0.24 } ?? false
        if gliding || now-lastWaterFrame >= 0.115 {
            lastWaterFrame = now
            setNeedsDisplay(viewRect(chartRect))
        }
    }
    func scenePoint(_ p: NSPoint) -> NSPoint {
        NSPoint(x:(p.x-pad.x)/scale, y:(p.y-pad.y)/scale)
    }
    func viewRect(_ r: NSRect) -> NSRect {
        R(pad.x + r.minX*scale, pad.y + r.minY*scale, r.width*scale, r.height*scale)
    }
    override func draw(_ dirtyRect: NSRect) {
        let pixel = 1 / max(1,window?.backingScaleFactor ?? 1)
        let chartOnly = drawer == nil && (desk == .sailing || desk == .replay) && !targets.isEmpty
            && viewRect(chartRect).insetBy(dx:-pixel,dy:-pixel).contains(dirtyRect)
        P.rect(chartOnly ? dirtyRect : bounds, chartOnly ? P.paper : P.night)
        guard let cg = NSGraphicsContext.current?.cgContext, scale > 0 else { return }
        cg.saveGState()
        cg.translateBy(x: pad.x, y: pad.y)
        cg.scaleBy(x: scale, y: scale)
        cg.clip(to: R(0,0,1200,750))
        if chartOnly {
            drawSeaChart(shownTrip,replay:desk == .replay)
            cg.restoreGState()
            return
        }
        targets.removeAll(keepingCapacity: true)
        switch desk {
        case .workshop: drawChartRoom()
        case .chartCase: drawChartCase()
        case .studioReceipt: drawStudioReceipt()
        case .telegraph: drawWire()
        case .telegramReceipt: drawWireReceipt()
        case .cover: drawCover()
        case .sailing, .replay: drawSailing()
        case .routes: drawRouteAtlas()
        case .album: drawCatalog()
        case .letter(let id): drawLetter(id: id)
        case .finale: drawFinale()
        }
        if let drawer {
            targets.removeAll(keepingCapacity: true)
            drawDrawer(drawer)
        }
        if keyboardFocus, let rect = targets.first(where: { $0.action == focused && $0.enabled })?.rect {
            P.frame(rect.insetBy(dx: -2, dy: -2), P.ochre, 2)
            P.frame(rect.insetBy(dx: -4, dy: -4), P.deep, 1)
        }
        cg.restoreGState()
        accessDeck.didDraw()
    }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        accessDeck.hitTest(point) ?? super.accessibilityHitTest(point)
    }
    override var accessibilityFocusedUIElement: Any? {
        accessDeck.focusedElement ?? super.accessibilityFocusedUIElement
    }
    func target(_ r: NSRect, _ action: DeskAction, _ label: String, _ enabled: Bool = true) {
        targets.append(.init(rect: r, action: action, label: label, enabled: enabled))
    }
    func hoverOn(_ r: NSRect) -> Bool { hover.map(r.contains) == true }
    func button(_ r: NSRect, _ action: DeskAction, _ label: String, style: ButtonInk = .paper,
                key: String? = nil, enabled: Bool = true, fontSize: CGFloat = 15) {
        let hot = hoverOn(r) && enabled && (drawer == nil || renderingDrawer)
        let fill, fg, border: NSColor
        switch style {
        case .primary: fill = hot ? P.cream : P.ochre; fg = P.night; border = P.ochre
        case .paper: fill = hot ? P.cream : P.paper; fg = P.graphite; border = P.rule
        case .dark: fill = hot ? P.sea : P.deep; fg = P.cream; border = P.foam.withAlphaComponent(0.55)
        case .clear: fill = hot ? P.sea : .clear; fg = P.cream; border = .clear
        case .selected: fill = P.sea; fg = P.cream; border = P.sea
        }
        P.rect(r, fill)
        P.frame(r, border)
        let ink = enabled ? fg : fg.withAlphaComponent(0.42)
        let keyW: CGFloat = key == nil ? 0 : 40
        P.text(label, R(r.minX+8,r.minY,r.width-16-keyW,r.height),
               P.sans(fontSize, .semibold), ink, align: key == nil ? .center : .left, centerY:true)
        if let key {
            let k = R(r.maxX-38,r.midY-10,30,20)
            P.frame(k, ink.withAlphaComponent(0.4))
            P.text(key,k,P.mono(11,.medium),ink,align:.center,centerY:true)
        }
        target(r, action, label, enabled)
    }
    var renderingDrawer = false
    func resetFocus() {
        targets.removeAll(keepingCapacity:true)
        focused = nil
        signalInspection = nil
        inspectedPoint = nil
        hover = nil
        previewBeat = nil
        needsDisplay = true
    }
    func announce(_ message: String) {
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    func notice(_ message: String) {
        signalInspection = nil
        lastEvent = message
        lastEventTime = clock
        announce(message)
        needsDisplay = true
    }
    func start(_ id: Int) {
        guard let level = MistCampaign.levels.first(where: { $0.id == id }), store.unlocked(id) else { return }
        catalogReturns.removeAll()
        activeWire = nil
        voyage = MistVoyage(level: level, replay: store.profile.journeys[id] ?? []) ?? MistVoyage(level: level)
        store.update { $0.currentID = id }
        desk = .sailing
        drawer = nil
        hint = nil
        motionAt = nil
        lastEvent = ""
        lastEventTime = -100
        replayRunning = false
        resetFocus()
        announce("第"+String(id)+"条航路，"+level.title+"。"+level.briefing)
    }
    func switchTo(_ destination: Desk) {
        let returningToAlbum = desk == .finale && finaleFromAlbum && destination == .album
        if destination == .cover {
            catalogReturns.removeAll()
        } else if destination == .routes || destination == .album || destination == .telegraph {
            switch desk {
            case .sailing, .workshop, .chartCase, .studioReceipt, .telegramReceipt, .replay:
                catalogReturns.append(CatalogReturn(self))
            case .cover:
                catalogReturns.removeAll()
            case .finale where !returningToAlbum:
                catalogReturns.removeAll()
            case .letter where letterReturn == .sailing:
                catalogReturns.removeAll()
            default: break
            }
        }
        if (destination == .routes || destination == .album) && !returningToAlbum {
            selectedPort = voyage.level.id > 0 && !voyage.delivered ? voyage.level.id : store.nextUndelivered
            chapter = (selectedPort - 1) / 4
        }
        desk = destination
        replayRunning = false
        drawer = nil
        resetFocus()
        if returningToAlbum && keyboardFocus { focused = .readFinale }
    }
    func operate(_ command: MistCommand) {
        guard desk == .sailing, drawer == nil else { return }
        previewBeat = nil
        signalInspection = nil
        inspectedPoint = nil
        let previous = voyage.beat
        let result: MistOutcome
        switch command {
        case .move(let move): result = voyage.step(move)
        case .record: result = voyage.record()
        }
        if case .blocked(let why) = result {
            audio.play(.blocked)
            notice(why.message)
            return
        }
        hint = nil
        motionAt = clock
        persistVoyage()
        switch result {
        case .delivered:
            audio.play(.delivered)
            if voyage.level.id < 0 { desk = studio.active == nil ? .workshop : .studioReceipt }
            else { desk = voyage.level.id == 0 ? .telegramReceipt : .letter(voyage.level.id) }
            wireNotice = nil
            letterReturn = .sailing
            resetFocus()
            announce("投递成功。"+voyage.level.letter)
        case .stamped:
            audio.play(.stamp)
            notice("已盖邮戳  "+String(voyage.stamped.count)+" / "+String(voyage.level.stamps.count))
        case .sailed:
            switch command {
            case .record:
                audio.play(.rewind)
                notice("第 "+String(voyage.echoes.count)+" 艘船影已出发。")
            case .move(let move):
                let opened = (0..<3).filter { !voyage.gateOpen($0, at: previous) && voyage.gateOpen($0, at: voyage.beat) }
                if opened.isEmpty { audio.play(move == .wait ? .wait : .move) }
                else { opened.forEach { audio.ringBuoy($0) } }
                lastEvent = ""
                if voyage.beat == voyage.level.turnLimit {
                    notice("本潮已尽。可以留影返航或撤回一拍。")
                }
            }
        case .blocked: break
        }
        needsDisplay = true
    }
    func openReplay(level: MistLevel, route: [MistCommand]) {
        replayRoute = route
        replayLegs.removeAll(keepingCapacity:true)
        var departure = 0
        for (index, command) in route.enumerated() where command == .record {
            replayLegs.append(departure...index)
            departure = index + 1
        }
        replayLegs.append(departure...route.count)
        replayTrip = MistVoyage(level:level)
        replayIndex = 0
        replayRunning = false
        motionAt = nil
        desk = .replay
        resetFocus()
    }
    func seekReplay(_ index: Int) {
        guard let previous = replayTrip else { return }
        let next = max(0, min(index, replayRoute.count))
        guard let new = MistVoyage(level: previous.level, replay: Array(replayRoute.prefix(next))) else { return }
        motionAt = next == replayIndex+1 && new.beat > 0 ? clock : nil
        replayTrip = new
        replayIndex = next
        replayClock = clock
        if next == replayRoute.count { replayRunning = false }
        needsDisplay = true
    }
    func act(_ a: DeskAction) {
        if a != .replayPlay && a != .replaySpeed { replayRunning = false }
        switch a {
        case .lesson(let action): lessonAction(action); return
        case .studio(let command): studioAction(command); return
        case .printLetter(let id): offerPrint(.letter(id))
        case .printAtlas: offerPrint(.atlas)
        case .port(let id):
            guard MistCampaign.levels.contains(where: { $0.id == id }) else { return }
            selectedPort = id
            resetFocus()
        case .wire(let command): wireAction(command); return
        case .home: switchTo(.cover)
        case .depart:
            var id = store.profile.currentID
            if store.profile.records[id] != nil && store.profile.journeys[id] == nil { id = store.nextUndelivered }
            start(id)
        case .routes: switchTo(.routes)
        case .album: switchTo(.album)
        case .back:
            if drawer == nil, desk == .finale, finaleFromAlbum {
                switchTo(.album)
                break
            }
            if drawer != nil { drawer = nil }
            else {
                switch desk {
                case .routes, .album, .telegraph:
                    if let origin = catalogReturns.popLast() { origin.restore(self) }
                    else { desk = .cover }
                case .telegramReceipt: desk = .telegraph
                case .workshop: desk = .routes
                case .chartCase:
                    if studio.fromAfterpost {
                        studio.fromAfterpost = false
                        desk = .finale
                        drawer = .afterpost
                    } else { desk = .workshop }
                case .studioReceipt: desk = .chartCase
                case .letter: desk = letterReturn == .sailing ? .routes : .album
                case .replay:
                    if let id = replayTrip?.level.id { desk = id < 0 ? .studioReceipt : (id == 0 ? .telegramReceipt : .letter(id)) }
                case .sailing: desk = voyage.level.id < 0 ? (studio.authoring ? .workshop : .chartCase) : .cover
                case .finale: desk = .cover
                case .cover: return
                }
                if desk == .sailing && voyage.delivered { desk = .cover }
            }
            resetFocus()
        case .guide: drawer = .guide(0); resetFocus()
        case .preferences: drawer = .preferences; resetFocus()
        case .dismiss: drawer = nil; resetFocus()
        case .sound:
            store.update { $0.soundOn.toggle() }
            audio.setEnabled(store.profile.soundOn)
            if store.profile.soundOn { audio.play(.select) }
        case .chapter(let i): chapter = i; resetFocus()
        case .route(let id): start(id)
        case .letter(let id):
            guard store.profile.records[id] != nil else { return }
            desk = .letter(id)
            letterReturn = .album
            resetFocus()
        case .readFinale:
            guard desk == .album, hasFinalReceipt else { return }
            finaleFromAlbum = true
            desk = .finale
            resetFocus()
        case .next:
            guard case .letter(let id) = desk else { return }
            if id == MistCampaign.levels.last?.id {
                guard hasFinalReceipt else { start(store.nextUndelivered); return }
                finaleFromAlbum = false
                desk = .finale
                audio.play(.ending)
                resetFocus()
            }
            else { start(id+1) }
        case .replay(let id):
            guard let record = store.profile.winningRoutes[id],
                  let level = MistCampaign.levels.first(where: { $0.id == id }) else { return }
            openReplay(level:level,route:record)
        case .move(let move): operate(.move(move)); return
        case .record: operate(.record); return
        case .undo:
            guard desk == .sailing, voyage.undo() else { return }
            hint = nil
            motionAt = nil
            previewBeat = nil
            persistVoyage()
            notice("已撤回上一个操作。")
            audio.play(.undo)
            return
        case .restart: drawer = .restart; resetFocus()
        case .confirmRestart:
            voyage.restart()
            hint = nil
            motionAt = nil
            persistVoyage()
            drawer = nil
            resetFocus()
            notice("回到出发港。")
        case .signal(let id):
            guard desk == .sailing, drawer == nil else { return }
            inspectSignal(id, game:voyage)
        case .hint:
            signalInspection = nil
            guard desk == .sailing, voyage.level.id >= 0 || !studio.authoring else { return }
            hint = voyage.hint()
            lastEvent = ""
            previewBeat = nil
            if let hint { announce(hint.text) }
        case .guidePage(let i): drawer = .guide(i); resetFocus()
        case .trails: store.update { $0.trails.toggle() }
        case .contrast: store.update { $0.contrast.toggle() }
        case .motion: store.update { $0.lowMotion.toggle() }
        case .fullscreen: window?.toggleFullScreen(nil)
        case .preview(let beat): previewBeat = beat == voyage.beat ? nil : beat
        case .live: previewBeat = nil
        case .replayPlay:
            if replayIndex == replayRoute.count { seekReplay(0) }
            replayRunning.toggle()
            replayClock = clock
        case .replaySpeed:
            guard desk == .replay else { return }
            let fraction = min(1,max(0,(clock-replayClock)/replaySpeed.interval))
            replaySpeed = replaySpeed.next
            if replayRunning { replayClock = clock-fraction*replaySpeed.interval }
            announce("回放速度 "+replaySpeed.label)
        case .replayPrevious: seekReplay(replayIndex-1)
        case .replayNext: seekReplay(replayIndex+1)
        case .replayLeg(let leg):
            guard desk == .replay, replayLegs.indices.contains(leg) else { return }
            seekReplay(replayLegs[leg].lowerBound)
        case .replaySeek(let step):
            guard desk == .replay else { return }
            seekReplay(step)
        }
        if a != .sound && a != .next && a != .replayNext && a != .replayPrevious { audio.play(.select) }
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options:[.inVisibleRect,.activeInKeyWindow,.mouseMoved,.mouseEnteredAndExited], owner:self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseMoved(with event: NSEvent) {
        let p = scenePoint(convert(event.locationInWindow, from:nil))
        let oldHit = hover.flatMap { old in targets.last { $0.rect.contains(old) }?.action }
        let oldCell = drawer == nil && desk == .sailing ? hover.flatMap { chart.cell(at:$0,in:chartRect,game:voyage) } : nil
        let hadFocus = keyboardFocus
        hover = p
        keyboardFocus = false
        let hit = targets.last { $0.rect.contains(p) }
        let cell = drawer == nil && desk == .sailing ? chart.cell(at:p,in:chartRect,game:voyage) : nil
        if hit?.enabled == true || (cell != nil && isAdjacent(p)) { NSCursor.pointingHand.set() }
        else { NSCursor.arrow.set() }
        if hadFocus || hit?.action != oldHit || cell != oldCell || desk == .workshop { needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; NSCursor.arrow.set(); needsDisplay = true }
    func isAdjacent(_ p: NSPoint) -> Bool {
        guard let cell = chart.cell(at:p,in:chartRect,game:voyage) else { return false }
        return abs(cell.x-voyage.position.x)+abs(cell.y-voyage.position.y) == 1
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        keyboardFocus = false
        if desk == .workshop { studio.draft.endTerrainStroke() }
        let p = scenePoint(convert(event.locationInWindow,from:nil))
        if let target = targets.reversed().first(where: { $0.rect.contains(p) }) {
            if target.enabled { act(target.action) }
            return
        }
        if drawer == nil && desk == .workshop, let cell = chart.cell(at:p,in:draftingRect,game:studio.paper) {
            hover = p
            beginPainting(at:cell)
            return
        }
        guard drawer == nil, desk == .sailing, let point = chart.cell(at:p,in:chartRect,game:voyage) else { return }
        if let move = MistMove.allCases.first(where: { $0 != .wait && voyage.position.moved($0) == point }) {
            operate(.move(move))
        } else if point == voyage.position {
            operate(.move(.wait))
        } else { inspect(point,game:voyage) }
    }
    override func rightMouseDown(with event: NSEvent) {
        let point = scenePoint(convert(event.locationInWindow,from:nil))
        if desk == .sailing, drawer == nil, let cell = chart.cell(at:point,in:chartRect,game:voyage) {
            inspect(cell,game:voyage)
        } else { super.rightMouseDown(with:event) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard desk == .workshop, drawer == nil, studio.draft.isDrawingTerrain else { return }
        let p = scenePoint(convert(event.locationInWindow,from:nil))
        hover = p
        continuePainting(at:chart.cell(at:p,in:draftingRect,game:studio.paper))
    }
    override func mouseUp(with event: NSEvent) {
        guard desk == .workshop, studio.draft.isDrawingTerrain else { return }
        if drawer == nil {
            // The release may be the first event at the final sampled cell.
            let p = scenePoint(convert(event.locationInWindow,from:nil))
            hover = p
            continuePainting(at:chart.cell(at:p,in:draftingRect,game:studio.paper))
        }
        studio.draft.endTerrainStroke()
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { super.keyDown(with:event); return }
        handleKey(event.keyCode, character:event.charactersIgnoringModifiers?.lowercased() ?? "",
                  shift:event.modifierFlags.contains(.shift), repeated:event.isARepeat)
    }
    func handleKey(_ code: UInt16, character: String, shift: Bool = false, repeated: Bool = false) {
        if code == 48 {
            var seen = Set<DeskAction>()
            let items = targets.filter { $0.enabled && seen.insert($0.action).inserted }
            guard !items.isEmpty else { return }
            let current = items.firstIndex { $0.action == focused } ?? (shift ? 0 : -1)
            focused = items[(current + (shift ? -1 : 1) + items.count) % items.count].action
            keyboardFocus = true
            needsDisplay = true
            return
        }
        if code == 53 { act(.back); return }
        if (code == 36 || code == 76) && keyboardFocus, let focused,
           targets.contains(where: { $0.action == focused && $0.enabled }) {
            if !repeated { act(focused) }
            return
        }
        if character == "?" || character == "h" && desk != .sailing {
            if drawer == nil { act(.guide) }
            else if case .guide = drawer { act(.dismiss) }
            return
        }
        if let drawer {
            if drawer == .lesson {
                if code == 124 || code == 36 || code == 49 { act(.lesson(.next)) }
                else if code == 123 { act(.lesson(.previous)) }
                return
            }
            if case .guide(let page) = drawer {
                if code == 124 && page < 2 { act(.guidePage(page+1)) }
                if code == 123 && page > 0 { act(.guidePage(page-1)) }
            }
            return
        }
        if character == "m" { if !repeated { act(.sound) }; return }
        keyboardFocus = false
        switch desk {
        case .cover:
            if code == 36 || code == 76 { act(.depart) }
        case .sailing:
            if ["1","2","3"].contains(character), let number = Int(character) {
                if !repeated { act(.signal(number-1)) }
                return
            }
            switch (code,character) {
            case (126,_),(_,"w"): operate(.move(.north))
            case (125,_),(_,"s"): operate(.move(.south))
            case (123,_),(_,"a"): operate(.move(.west))
            case (124,_),(_,"d"): operate(.move(.east))
            case (49,_): operate(.move(.wait))
            case (36,_),(76,_),(_,"e"): if !repeated { operate(.record) }
            case (_,"z"),(51,_): act(.undo)
            case (_,"h"): if !repeated { act(.hint) }
            case (_,"r"): if !repeated { act(.restart) }
            default: break
            }
        case .letter:
            if (code == 36 || code == 76) && !repeated { act(letterReturn == .sailing ? .next : .back) }
        case .replay:
            if code == 49 && !repeated { act(.replayPlay) }
            if character == "v" && !repeated { act(.replaySpeed) }
            if code == 126 { act(.replayLeg(max(0,shownTrip.echoes.count-1))) }
            if code == 125 { act(.replayLeg(min(replayLegs.count-1,shownTrip.echoes.count+1))) }
            if code == 123 { act(.replayPrevious) }
            if code == 124 { act(.replayNext) }
        case .routes:
            if code == 123 && selectedPort > 1 { act(.port(selectedPort-1)) }
            if code == 124 && selectedPort < MistCampaign.levels.count { act(.port(selectedPort+1)) }
            if code == 36 { act(.route(selectedPort)) }
        case .album:
            if code == 123 && chapter > 0 { act(.chapter(chapter-1)) }
            if code == 124 && chapter < 2 { act(.chapter(chapter+1)) }
        case .workshop:
            let directions: [UInt16:MistMove] = [126:.north,124:.east,125:.south,123:.west]
            if let m = directions[code] { act(.studio(.cursor(m))) }
            else if code == 49 { act(.studio(.paint(studio.cursor ?? studio.paper.level.origin))) }
            else if character == "z" { act(.studio(.undo)) }
        case .chartCase: if code == 36 { act(.studio(.launch)) }
        case .studioReceipt: if code == 36 { act(.studio(.shelf)) }
        case .telegraph:
            if code == 36 && wireUnlocked { act(.wire(.launch)) }
        case .telegramReceipt:
            if code == 36 { act(.wire(.listenAgain)) }
        case .finale:
            if code == 36 { act(.album) }
        }
    }
}
