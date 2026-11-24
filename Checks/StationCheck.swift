import AppKit

@MainActor
func qaSnapshot(_ view: StationView, to url: URL, size: NSSize = NSSize(width:1200,height:750)) throws {
    view.frame = NSRect(origin:.zero,size:size)
    let w = Int(size.width), h = Int(size.height)
    let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,
                        space:CGColorSpace(name:CGColorSpace.sRGB)!,
                        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x:0,y:CGFloat(h))
    ctx.scaleBy(x:1,y:-1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext:ctx,flipped:true)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    guard let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])
    else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to:url,options:.atomic)
}

@MainActor
private func qaFinaleReturn(_ view: StationView, phase: String, folder: URL) throws {
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain:"FinaleReturn",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    }
    func button(_ prefix: String) -> NSAccessibilityElement? {
        (view.accessibilityChildren() as? [NSAccessibilityElement])?.first {
            $0.accessibilityRole() == .button && $0.accessibilityLabel()?.hasPrefix(prefix) == true
        }
    }
    func snap(_ name: String) throws { try qaSnapshot(view,to:folder.appendingPathComponent(name+".png")) }
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    if phase == "prepare" {
        try require(view.store.profile.records.isEmpty,"Prepare requires an empty test profile")
        for level in MistCampaign.levels.dropLast() {
            guard let trip = MistVoyage(level:level,replay:level.guide), trip.delivered else { throw CocoaError(.fileReadCorruptFile) }
            view.store.save(trip)
        }
        view.act(.album)
        try snap("eleven-letters")
        try require(!view.hasFinalReceipt && button("重读结航回函") == nil && !view.targets.contains { $0.action == .readFinale },
                    "The incomplete collection exposed the finale")
        view.act(.readFinale)
        try require(view.desk == .album,"The incomplete collection entered the finale")
        if let last = MistCampaign.levels.last {
            view.start(last.id)
            for step in last.guide { view.operate(step) }
        }
        view.act(.next)
        try require(view.hasFinalReceipt && view.desk == .finale,"First delivery did not unlock the finale")
        print("PASS gated eleven-letter album and original first-delivery finale")
        return
    }
    try require(phase == "reopen" && view.hasFinalReceipt && view.desk == .cover,"Reopen requires the completed test profile")
    let window = NSWindow(contentRect:view.bounds,styleMask:.borderless,backing:.buffered,defer:false)
    window.contentView = view
    window.makeFirstResponder(view)
    func key(_ code: UInt16, _ characters: String) {
        if let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,
                                        windowNumber:window.windowNumber,context:nil,characters:characters,
                                        charactersIgnoringModifiers:characters,isARepeat:false,keyCode:code) { window.sendEvent(event) }
    }
    view.act(.album)
    view.act(.chapter(0))
    try snap("completed-album")
    for _ in 0..<view.targets.count where view.focused != .readFinale { key(48,"\t") }
    try require(view.focused == .readFinale,"Tab did not reach the archived finale")
    key(36,"\r")
    try require(view.desk == .finale,"Return did not open the archived finale")
    try snap("reopened-finale")
    try require(button("印制全港邮路图")?.isAccessibilityEnabled() == true,"The atlas printing control is unavailable")
    let atlas = try view.keepsakePNG(.atlas)
    let bitmap = NSBitmapImageRep(data:atlas)
    try require(bitmap?.pixelsWide == 2400 && bitmap?.pixelsHigh == 1500,"The printed atlas has the wrong dimensions")
    try atlas.write(to:folder.appendingPathComponent("reopened-atlas.png"),options:.atomic)
    key(53,"")
    try require(view.desk == .album && view.chapter == 0,"Escape lost the source album page")
    try require(view.keyboardFocus && view.focused == .readFinale,"Escape lost the album's keyboard focus")
    try snap("returned-album")
    try require(button("重读结航回函")?.accessibilityPerformPress() == true && view.desk == .finale,"AXPress could not reopen the finale")
    try snap("reopened-finale")
    try require(button("返回收信册")?.accessibilityPerformPress() == true && view.desk == .album && view.chapter == 0,
                "The return control lost the source album page")
    try snap("returned-album")
    guard let entry = view.targets.first(where:{ $0.action == .readFinale }) else { throw CocoaError(.fileReadCorruptFile) }
    let rect = view.viewRect(entry.rect)
    let center = view.convert(NSPoint(x:rect.midX,y:rect.midY),to:nil)
    if let event = NSEvent.mouseEvent(with:.leftMouseDown,location:center,modifierFlags:[],timestamp:0,
                                      windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1) {
        view.mouseDown(with:event)
    }
    try require(view.desk == .finale,"Clicking the archived finale did not open it")
    key(53,"")
    key(53,"")
    try require(view.desk == .cover,"Backing out of the album returned to the finale")
    print("PASS reopened completed ledger, mouse, Tab/Return, AXPress, album navigation and 2400×1500 atlas")
}

@MainActor
func qaEntry(_ view: StationView, arguments: [String]) {
    if let i = arguments.firstIndex(of:"--finale-return"), i + 2 < arguments.count {
        do {
            try qaFinaleReturn(view,phase:arguments[i+1],folder:URL(fileURLWithPath:arguments[i+2],isDirectory:true))
            exit(0)
        } catch { fputs("FAIL finale return: "+error.localizedDescription+"\n",stderr); exit(1) }
    }
    if let i = arguments.firstIndex(of:"--cold-launch"), i+2 < arguments.count, let number = Int(arguments[i+2]) {
        do { try ColdLaunch.run(view,phase:arguments[i+1],number:number) }
        catch { fputs("FAIL cold launch: "+error.localizedDescription+"\n",stderr); exit(1) }
    }
    if let i = arguments.firstIndex(of:"--film"), i+1 < arguments.count {
        let file = URL(fileURLWithPath:arguments[i+1])
        Task { @MainActor in
            do { try await FilmCapture.make(view:view,file:file); exit(0) }
            catch { fputs("FAIL film: "+error.localizedDescription+"\n",stderr); exit(1) }
        }
        return
    }
    if arguments.contains("--store") {
        do { try StoreCheck.run(); exit(0) }
        catch { fputs("FAIL store: "+String(describing:error)+"\n",stderr); exit(1) }
    }
    if arguments.contains("--accessibility") {
        let resources = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MIST_POST_RESOURCES"] ?? "Resources")
        Task { @MainActor in
            do { try await StationAccessCheck.run(resources:resources); exit(0) }
            catch { fputs("FAIL accessibility: "+String(describing:error)+"\n",stderr); exit(1) }
        }
        return
    }
    if arguments.contains("--render-audit") { RenderAudit.run(view) }
    if let flag = arguments.firstIndex(of:"--soak-until"), flag+2 < arguments.count,
       let end = TimeInterval(arguments[flag+1]), let path = ProcessInfo.processInfo.environment["MIST_POST_SAVE"] {
        let folder = URL(fileURLWithPath:arguments[flag+2],isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        HarborEndurance.run(view,until:Date(timeIntervalSince1970:end),directory:folder,file:URL(fileURLWithPath:path))
        return
    }
    guard let flag = arguments.firstIndex(of:"--snapshot"), flag+1 < arguments.count else {
        fputs("Pass --snapshot <directory>\n",stderr); exit(2)
    }
    let folder = URL(fileURLWithPath:arguments[flag+1],isDirectory:true)
    do {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        func snap(_ name: String) throws { try qaSnapshot(view,to:folder.appendingPathComponent(name+".png")) }
        try snap("00-cover")
        view.act(.routes)
        try snap("00-atlas")
        view.act(.back)
        view.act(.depart)
        try snap("01-voyage")
        view.act(.preferences)
        try snap("02-preferences")
        view.act(.dismiss)
        view.act(.guide)
        view.act(.guidePage(1))
        try snap("03-guide")
        let old = view.voyage.history
        view.act(.lesson(.open))
        for _ in BellLesson.level.guide { view.act(.lesson(.next)) }
        precondition(view.lesson?.game.delivered == true && view.voyage.history == old)
        try snap("03-lesson")
        view.act(.lesson(.previous))
        precondition(view.lesson?.game.delivered == false)
        view.act(.lesson(.back))
        view.act(.dismiss)
        let levels = MistCampaign.levels
        for level in levels {
            view.start(level.id)
            precondition(view.desk == .sailing && view.voyage.level.id == level.id)
            for (i,cmd) in level.guide.enumerated() {
                view.operate(cmd)
                if level.id == 8 && i == level.guide.count-4 { try snap("08-echo") }
            }
            precondition(view.desk == .letter(level.id))
            precondition(view.store.profile.records[level.id] == level.par)
            if level.id == 1 { try snap("04-letter") }
        }
        view.act(.next)
        try snap("09-finale")
        view.act(.album)
        try snap("10-album")
        precondition(view.targets.contains { $0.action == .readFinale && $0.enabled })
        view.act(.letter(12))
        view.act(.replay(12))
        view.seekReplay(view.replayRoute.count)
        precondition(view.replayTrip?.delivered == true)
        try snap("11-replay")
        ReplayCheck.run(view)
        try SignalCheck.run(view,folder:folder)
        try AfterpostCheck.run(view,folder:folder)
        view.act(.wire(.office))
        let wire = MistChallenge.make(seed:4936)
        view.setWire(wire)
        try snap("12-wire")
        view.act(.wire(.launch))
        precondition(view.desk == .sailing && view.voyage.level.id == 0)
        let campaignRecords = view.store.profile.records
        for cmd in wire.level.guide { view.operate(cmd) }
        precondition(view.desk == .telegramReceipt && view.store.profile.records == campaignRecords)
        precondition(view.store.profile.telegrams?[wire.code]?.best == wire.level.guide)
        try snap("13-telegram")
        view.act(.wire(.replay))
        view.seekReplay(view.replayRoute.count)
        precondition(view.replayTrip?.delivered == true)
        view.act(.back)
        precondition(view.desk == .telegramReceipt)
        let resources = URL(fileURLWithPath:ProcessInfo.processInfo.environment["MIST_POST_RESOURCES"] ?? "Resources")
        try StudioCheck.run(resources:resources,folder:folder)
        try WireCardCheck.run(resources:resources,folder:folder)
        ReturnPathCheck.run(resources:resources)
        let postcard = try view.keepsakePNG(.letter(12))
        let coastal = try view.keepsakePNG(.atlas)
        try postcard.write(to:folder.appendingPathComponent("17-postcard.png"))
        try coastal.write(to:folder.appendingPathComponent("18-mail-atlas.png"))
        for file in [postcard,coastal] {
            guard let bitmap = NSBitmapImageRep(data:file), bitmap.pixelsWide == 2400 && bitmap.pixelsHigh == 1500 else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        print("PASS native campaign, records, archive, finale, telegraph, postcard and full-route print")
        exit(0)
    } catch {
        fputs("QA failed: "+error.localizedDescription+"\n",stderr); exit(1)
    }
}
