import AppKit

@MainActor
enum StudioCheck {
    static func run(resources: URL, folder: URL) throws {
        let base = folder.appendingPathComponent("studio-profile-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:base) }
        let save = base.appendingPathComponent("dispatch.json")
        let view = StationView(store:DispatchStore(file:save),resources:resources)
        view.frozenTime = 42
        view.act(.routes)
        view.studioAction(.editor)
        precondition(view.desk == .workshop)
        try checkMouseStrokes(view,save:save)
        let model = MistCampaign.levels[1]
        let studio = view.studio
        _ = try studio.draft.configure(title:"三月的短航",author:"潮表员",letter:"修好的雾钟已经挂回门口。",echoLimit:1,turnLimit:12)
        studio.edited()
        for (p,brush) in [(model.origin,CoastBrush.origin),(model.harbor,CoastBrush.harbor)] {
            view.act(.studio(.brush(brush)))
            view.act(.studio(.paint(p)))
        }
        for y in 0..<model.height {
            for x in 0..<model.width {
                let p = MistPoint(x:x,y:y), tile = model.tile(at:p)
                if tile == .origin || tile == .harbor { continue }
                guard let brush = CoastBrush.allCases.first(where:{ $0.tile == tile }) else { preconditionFailure("palette") }
                view.act(.studio(.brush(brush)))
                view.act(.studio(.paint(p)))
            }
        }
        try qaSnapshot(view,to:folder.appendingPathComponent("14-workshop.png"))
        let original = studio.draft.rows
        view.act(.studio(.newSheet))
        precondition(studio.draft.rows != original)
        view.act(.studio(.undo))
        precondition(studio.draft.rows == original)
        let before = studio.draft.rows
        view.act(.studio(.brush(.water)))
        view.act(.studio(.paint(.init(x:0,y:0))))
        view.act(.studio(.undo))
        precondition(studio.draft.rows == before)
        let round = StationView(store:DispatchStore(file:save),resources:resources)
        precondition(round.studio.draft.rows == before && round.studio.draft.canUndo)
        view.act(.studio(.trial))
        for command in model.guide.prefix(4) { view.operate(command) }
        view.act(.back)
        precondition(view.desk == .workshop)
        view.act(.studio(.trial))
        precondition(view.voyage.history == Array(model.guide.prefix(4)))
        for command in model.guide.dropFirst(4) { view.operate(command) }
        precondition(view.desk == .studioReceipt)
        guard let chart = studio.active else { preconditionFailure("unsealed chart") }
        precondition(chart.level.guide == model.guide && view.store.profile.records.isEmpty)
        try qaSnapshot(view,to:folder.appendingPathComponent("15-workshop-receipt.png"))
        let file = base.appendingPathComponent("trial.mistchart")
        try chart.encoded().write(to:file)
        let guest = StationView(store:DispatchStore(file:nil),resources:resources)
        guest.receiveChart(from:file)
        precondition(guest.desk == .chartCase && guest.studio.volumes.count == 1)
        guest.act(.studio(.launch))
        precondition(guest.voyage.level.id == -1 && !guest.studio.authoring)
        for cmd in model.guide { guest.operate(cmd) }
        precondition(guest.desk == .studioReceipt && guest.store.profile.records.isEmpty)
        guest.act(.studio(.replay))
        guest.seekReplay(guest.replayRoute.count)
        precondition(guest.replayTrip?.delivered == true)
        guest.act(.back)
        precondition(guest.desk == .studioReceipt)
        guest.act(.studio(.shelf))
        try qaSnapshot(guest,to:folder.appendingPathComponent("16-chartcase.png"))
        let bad = base.appendingPathComponent("incomplete.mistchart")
        try Data("{".utf8).write(to:bad)
        guest.receiveChart(from:bad)
        precondition(guest.studio.volumes.count == 1 && guest.studio.message.hasPrefix("无法打开"))
        print("PASS workshop editing, persisted undo, trial resume, sealing and file import, guest delivery and replay")
    }
    private static func checkMouseStrokes(_ view: StationView, save: URL) throws {
        let window = NSWindow(contentRect:R(0,0,960,600),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = view
        window.makeFirstResponder(view)
        defer { window.contentView = nil }
        let studio = view.studio
        let blank = studio.draft.board
        var captured: NSView?
        func mouse(_ type: NSEvent.EventType, _ x: Int, _ y: Int) {
            let point = view.chart.center(of:MistPoint(x:x,y:y),in:view.draftingRect,game:studio.paper)
            let local = view.viewRect(R(point.x,point.y,0,0)).origin
            let location = view.convert(local,to:nil)
            let event = NSEvent.mouseEvent(with:type,location:location,modifierFlags:[],
                                           timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,
                                           context:nil,eventNumber:1,clickCount:1,pressure:1)!
            // Hidden QA windows receive no window-server mouse routing. Capture
            // the hit NSResponder on down and send it the actual window-relative
            // drag/up NSEvents, matching AppKit's mouse capture behavior.
            switch type {
            case .leftMouseDown:
                let host = view.superview?.convert(location,from:nil) ?? location
                captured = view.hitTest(host)
                precondition(captured === view)
                captured?.mouseDown(with:event)
            case .leftMouseDragged: captured?.mouseDragged(with:event)
            case .leftMouseUp: captured?.mouseUp(with:event); captured = nil
            default: preconditionFailure("unexpected brush event")
            }
        }
        func key(_ code: UInt16, _ character: String) {
            let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],
                                         timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,
                                         context:nil,characters:character,charactersIgnoringModifiers:character,
                                         isARepeat:false,keyCode:code)!
            window.sendEvent(event)
        }

        // Exactly three native position samples. The last four cells are
        // only reported on mouse-up and the landing must survive the crossing.
        mouse(.leftMouseDown,0,0)
        mouse(.leftMouseDragged,6,0)
        mouse(.leftMouseUp,6,4)
        precondition(studio.draft.rows == ["#######","......#","S.....H","......#","......#"])
        precondition(view.hover.flatMap { view.chart.cell(at:$0,in:view.draftingRect,game:studio.paper) } == MistPoint(x:6,y:4))
        precondition(studio.draft.undoBoards == [blank] && !studio.draft.isDrawingTerrain)
        var recovered = Cartography(DispatchStore(file:save)).draft
        precondition(recovered.board == studio.draft.board && recovered.undo() && recovered.board == blank)
        key(6,"z")
        precondition(studio.draft.board == blank && !studio.draft.canUndo)

        mouse(.leftMouseDown,0,1)
        mouse(.leftMouseUp,6,1)
        let bank = studio.draft.board
        view.act(.studio(.brush(.water)))
        mouse(.leftMouseDown,0,1)
        mouse(.leftMouseDragged,4,1)
        mouse(.leftMouseUp,6,1)
        precondition(studio.draft.board == blank)
        key(6,"z")
        precondition(studio.draft.board == bank)
        key(6,"z")
        precondition(studio.draft.board == blank && !studio.draft.canUndo)

        // Markers stay single-click tools. Cursor + Space remains an
        // independent edit even immediately after a held marker press.
        view.act(.studio(.brush(.stamp)))
        mouse(.leftMouseDown,1,1)
        mouse(.leftMouseDragged,5,1)
        mouse(.leftMouseUp,5,1)
        precondition(studio.paper.level.stamps == [MistPoint(x:1,y:1)])
        key(124,"")
        key(49," ")
        precondition(studio.paper.level.stamps == [MistPoint(x:1,y:1),MistPoint(x:2,y:1)])
        key(6,"z")
        precondition(studio.paper.level.stamps.count == 1)
        key(6,"z")
        precondition(studio.draft.board == blank && !studio.draft.canUndo)
        view.act(.studio(.brush(.land)))
        print("PASS native sparse mouse drags, release sampling, persisted stroke undo and discrete marker/keyboard edits")
    }

}
