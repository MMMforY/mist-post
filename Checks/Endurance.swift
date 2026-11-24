import AppKit
import Darwin

/// Drives the same NSWindow event handlers as a normal session. Every profile is
/// local to the supplied test directory. Timers leave the UI thread idle between inputs.
@MainActor
final class HarborEndurance {
    private let station: StationView
    private let window: NSWindow
    private let until: Date
    private let directory: URL
    private let saveFile: URL
    private let start = Date()
    private var drawSurface: CGContext
    private var timer: Timer?
    private var actions = 0, deliveries = 0, voyages = 0, saves = 0
    private var index = 0, routeIndex = 0, iteration = 0
    private var nextReport = Date()
    private var lastReportActions = 0
    private var state: UInt64 = 0x4d495354
    private var peakMiB = 0
    private var nextResize = 29
    private var fullRound = false
    private var restartAt = -1
    private var replacementPending = false
    private static var keeper: HarborEndurance?

    init(station: StationView, until: Date, directory: URL, saveFile: URL) {
        self.station = station
        self.until = until
        self.directory = directory
        self.saveFile = saveFile
        window = NSWindow(contentRect:R(0,0,1200,750),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = station
        window.makeFirstResponder(station)
        drawSurface = Self.surface(1200,750)
    }
    private static func surface(_ w: Int,_ h: Int) -> CGContext {
        let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,
                            space:CGColorSpace(name:CGColorSpace.sRGB)!,
                            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x:0,y:CGFloat(h))
        ctx.scaleBy(x:1,y:-1)
        return ctx
    }
    static func run(_ view: StationView, until: Date, directory: URL, file: URL) {
        let test = HarborEndurance(station:view,until:until,directory:directory,saveFile:file)
        keeper = test
        test.station.frozenTime = 0
        test.station.audio.setActive(false)
        test.station.act(.home)
        test.render()
        test.require(test.press(.depart),"missing initial departure")
        test.begin()
        if let flag = CommandLine.arguments.firstIndex(of:"--exercise"),
           flag + 1 < CommandLine.arguments.count, let count = Int(CommandLine.arguments[flag+1]) {
            for _ in 0..<count { autoreleasepool { test.advance() } }
            test.report(done:true)
            exit(0)
        }
        let t = Timer(timeInterval:1.12,repeats:true) { [weak test] _ in
            MainActor.assumeIsolated { autoreleasepool { test?.advance() } }
        }
        t.tolerance = 0.11
        RunLoop.main.add(t,forMode:.common)
        test.timer = t
    }
    private func pick(_ max: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 29) % UInt64(max))
    }
    private func require(_ condition: @autoclosure ()->Bool, _ message: String) {
        guard condition() else {
            try? qaSnapshot(station,to:directory.appendingPathComponent("failure.png"))
            fputs("FAIL input=\(actions) level=\(station.voyage.level.id) step=\(index) \(message)\n",stderr)
            fflush(stderr)
            exit(1)
        }
    }
    private func render() {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext:drawSurface,flipped:true)
        station.draw(station.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    @discardableResult private func press(_ action: DeskAction) -> Bool {
        render()
        guard let item = station.targets.last(where:{ $0.action == action && $0.enabled }) else { return false }
        click(.init(x:item.rect.midX,y:item.rect.midY))
        return true
    }
    private func click(_ point: CGPoint) {
        let area = station.viewRect(R(point.x,point.y,0,0))
        let p = station.convert(area.origin,to:nil)
        if let event = NSEvent.mouseEvent(with:.leftMouseDown,location:p,modifierFlags:[],
                                         timestamp:ProcessInfo.processInfo.systemUptime,
                                         windowNumber:window.windowNumber,context:nil,eventNumber:actions,
                                         clickCount:1,pressure:1) {
            // A hidden offscreen window is excluded from the window server's mouse routing.
            // Use AppKit hit testing to deliver the original window-relative NSEvent.
            let host = station.superview?.convert(p,from:nil) ?? p
            let recipient = station.hitTest(host)
            require(recipient === station,"offscreen mouse hit test")
            recipient?.mouseDown(with:event)
            actions += 1
        }
    }
    private func key(_ code: UInt16, _ char: String) {
        guard let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],
                                          timestamp:ProcessInfo.processInfo.systemUptime,
                                          windowNumber:window.windowNumber,context:nil,characters:char,
                                          charactersIgnoringModifiers:char,isARepeat:false,keyCode:code) else { return }
        window.sendEvent(event)
        actions += 1
    }
    private func begin() {
        let levels = MistCampaign.levels
        if !fullRound {
            routeIndex = min(voyages,levels.count-1)
        } else {
            routeIndex = pick(levels.count)
        }
        let id = levels[routeIndex].id
        station.start(id)
        if station.voyage.canUndo {
            station.act(.restart)
            require(press(.confirmRestart),"could not restart")
        }
        require(station.desk == .sailing && station.voyage.level.id == id,"route launch")
        index = 0
        voyages += 1
        restartAt = (fullRound && voyages % 11 == 0) ? 1+pick(levels[routeIndex].guide.count-2) : -1
        replacementPending = false
    }
    private func advance() {
        if Date() >= until {
            report(done:true)
            timer?.invalidate()
            exit(0)
        }
        station.frozenTime = Date().timeIntervalSince(start) + 10
        iteration += 1
        if Date() >= nextReport {
            report(done:false)
            nextReport = Date().addingTimeInterval(180)
        }
        if actions >= nextResize {
            nextResize = actions+41+pick(70)
            let sizes = [(800,500),(960,600),(1200,750),(1376,860),(940,620)]
            let (w,h) = sizes[pick(sizes.count)]
            window.setContentSize(NSSize(width:w,height:h))
            station.setFrameSize(NSSize(width:w,height:h))
            drawSurface = Self.surface(w,h)
            render()
            require(station.targets.count > 4,"resize lost controls")
        }
        if station.desk == .letter(station.voyage.level.id) {
            let lvl = station.voyage.level
            require(station.store.profile.records[lvl.id] != nil,"delivery missing record")
            require(press(.replay(lvl.id)),"missing replay button")
            require(station.replayIndex == 0,"replay initial cursor")
            for _ in 0..<station.replayRoute.count { key(124,"") }
            require(station.replayTrip?.delivered == true,"replay lost delivery")
            key(123,"")
            require(station.replayTrip?.delivered == false,"replay failed to step back")
            key(53,"")
            require(station.desk == .letter(lvl.id),"replay exit")
            deliveries += 1
            if deliveries >= MistCampaign.levels.count { fullRound = true }
            if lvl.id == MistCampaign.levels.count && deliveries == MistCampaign.levels.count { require(press(.next),"missing finale") }
            begin()
            return
        }
        let lvl = station.voyage.level
        if index == restartAt {
            require(press(.restart),"missing restart")
            require(press(.confirmRestart),"missing restart confirmation")
            require(!station.voyage.canUndo,"restart retained moves")
            index = 0
            restartAt = -1
            return
        }
        if index > 0 && iteration % 33 == 0 && !replacementPending {
            require(press(.undo),"missing undo")
            index -= 1
            replacementPending = true
            return
        }
        if iteration % 19 == 0 {
            validateSave()
            require(press(.guide),"missing guide")
            require(press(.guidePage(1)),"missing guide next page")
            key(124,"")
            require(station.drawer == .guide(2),"guide next arrow")
            key(53,"")
            require(station.drawer == nil,"escape stayed in guide")
        }
        if iteration % 31 == 0 {
            require(press(.preferences),"missing prefs")
            require(press(.trails) && press(.contrast) && press(.motion),"prefs toggle")
            key(53,"")
            require(press(.routes),"missing route log")
            require(press(.back),"route log return")
            require(station.desk == .sailing,"return route state")
        }
        if iteration % 17 == 0 {
            require(press(.hint),"missing hint")
            require(station.hint != nil,"empty hint")
            let desired = (station.voyage.beat+1) % (lvl.turnLimit+1)
            require(press(.preview(desired)),"missing beat preview")
            require(station.previewBeat == desired,"beat selector")
            require(press(.live),"missing live")
        }
        require(index < lvl.guide.count,"guide exhausted before delivery")
        let cmd = lvl.guide[index]
        let before = station.voyage.history
        switch cmd {
        case .record:
            if pick(2) == 0 { require(press(.record),"record disabled") } else { key(14,"e") }
        case .move(let move):
            if pick(3) == 0 {
                let dest = station.voyage.position.moved(move)
                let p = station.chart.center(of:dest,in:station.chartRect,game:station.voyage)
                click(p)
            } else {
                let code: UInt16, char: String
                switch move {
                case .north: (code,char)=(126,"w")
                case .west: (code,char)=(123,"a")
                case .east: (code,char)=(124,"d")
                case .south: (code,char)=(125,"s")
                case .wait: (code,char)=(49," ")
                }
                key(code,char)
            }
        }
        require(station.voyage.level.id == lvl.id,"event changed current level")
        require(station.voyage.history == before+[cmd],"wrong action dispatch for \(cmd), position=\(station.voyage.position) desk=\(station.desk) msg=\(station.lastEvent)")
        index += 1
        replacementPending = false
        render()
        if iteration % 43 == 0 && !station.voyage.delivered {
            let before = station.voyage.history
            station.start(lvl.id)
            require(station.voyage.history == before,"journey restore")
        }
    }
    private func validateSave() {
        let fresh = DispatchStore(file:saveFile)
        require(fresh.notice == nil,"disk load warning")
        require(fresh.profile.records == station.store.profile.records,"record round trip")
        require(fresh.profile.journeys == station.store.profile.journeys,"journey round trip")
        saves += 1
    }
    private func report(done: Bool) {
        var info = mach_task_basic_info()
        var size = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let code = withUnsafeMutablePointer(to:&info) {
            $0.withMemoryRebound(to:integer_t.self,capacity:Int(size)) {
                task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&size)
            }
        }
        let mib = code == KERN_SUCCESS ? Int(info.resident_size/1048576) : 0
        peakMiB = max(peakMiB,mib)
        let msg = "\(done ? "PASS" : "RUN") elapsed=\(Int(Date().timeIntervalSince(start)))s inputs=\(actions) deliveries=\(deliveries) diskChecks=\(saves) rssMiB=\(mib) maxMiB=\(peakMiB)"
        print(msg)
        fflush(stdout)
        lastReportActions = actions
    }
}
