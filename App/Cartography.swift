import AppKit
import UniformTypeIdentifiers

enum CoastBrush: Int, CaseIterable, Hashable {
    case water, land, origin, harbor, stamp, buoy1, buoy2, buoy3, gate1, gate2, gate3
    var tile: MistTile {
        switch self {
        case .water: return .water
        case .land: return .land
        case .origin: return .origin
        case .harbor: return .harbor
        case .stamp: return .stamp
        case .buoy1,.buoy2,.buoy3: return .buoy(rawValue-CoastBrush.buoy1.rawValue)
        case .gate1,.gate2,.gate3: return .gate(rawValue-CoastBrush.gate1.rawValue)
        }
    }
    var label: String {
        switch self {
        case .water: return "水道"
        case .land: return "陆岸"
        case .origin: return "出发港"
        case .harbor: return "收信塔"
        case .stamp: return "邮戳站"
        case .buoy1,.buoy2,.buoy3: return "\(rawValue-CoastBrush.buoy1.rawValue+1) 号铃"
        case .gate1,.gate2,.gate3: return "\(rawValue-CoastBrush.gate1.rawValue+1) 号闸"
        }
    }
}
enum StudioAction: Hashable {
    case mailbag, takeMail(Int), editor, shelf, brush(CoastBrush), undo, newSheet, configure, trial
    case sample, importChart, export, select(String), launch, remix, replay, turnPage(Int)
    case paint(MistPoint), cursor(MistMove)
}

private struct DraftLog: Codable {
    var revision = 1
    var document: Data
    var authorRoute: [MistCommand] = []
    var trials: [String:[MistCommand]] = [:]
    var bests: [String:[MistCommand]] = [:]
}

@MainActor
final class Cartography {
    let store: DispatchStore
    var draft: MistWorkshopDraft
    var paper: MistVoyage
    var brush = CoastBrush.land
    var cursor: MistPoint?
    var page = 0
    var message = ""
    var authoring = false
    var fromAfterpost = false
    var active: MistWorkshopChart?
    var selection: String?
    var volumes: [String:MistWorkshopChart] = [:]
    private var log: DraftLog

    init(_ store: DispatchStore) {
        self.store = store
        let raw = store.profile.workshopDraft
        let saved = raw.flatMap { try? JSONDecoder().decode(DraftLog.self,from:$0) }
        let doc = saved?.document ?? raw
        let restored = doc.flatMap { try? MistWorkshopDraft.restoreDraft($0) }
        draft = restored ?? MistWorkshopDraft(size:.small)
        paper = MistVoyage(level:draft.trialLevel())
        log = saved ?? DraftLog(document:(try? draft.encodedDraft()) ?? Data())
        if raw != nil && restored == nil {
            message = "草图无法读取，已打开空白海图。"
        }
        for (key,bytes) in store.profile.workshopCharts ?? [:] {
            if let c = try? MistWorkshopChart.open(bytes), c.fingerprint == key { volumes[key] = c }
        }
        selection = sortedKeys.first
    }
    var sortedKeys: [String] {
        volumes.keys.sorted { a,b in
            let x = volumes[a]!.level.title, y = volumes[b]!.level.title
            return x == y ? a < b : x < y
        }
    }
    var authorRoute: [MistCommand] { log.authorRoute }
    func edited() {
        paper = MistVoyage(level:draft.trialLevel())
        log.authorRoute = []
        persist()
    }
    func persist() {
        do {
            log.document = try draft.encodedDraft()
            let bytes = try JSONEncoder().encode(log)
            store.update { $0.workshopDraft = bytes }
        } catch { message = "草图暂未保存。"+error.localizedDescription }
    }
    func add(_ c: MistWorkshopChart) throws {
        let data = try c.encoded()
        store.update { profile in
            var collection = profile.workshopCharts ?? [:]
            collection[c.fingerprint] = data
            profile.workshopCharts = collection
        }
        volumes[c.fingerprint] = c
        selection = c.fingerprint
        if let whereAt = sortedKeys.firstIndex(of:c.fingerprint) { page = whereAt/5 }
    }
    func begin(author: Bool) -> MistVoyage? {
        authoring = author
        var record: [MistCommand] = []
        let level: MistLevel
        if author {
            level = draft.trialLevel()
            record = log.authorRoute
            active = nil
        } else {
            guard let selection, let chart = volumes[selection] else { return nil }
            active = chart
            level = chart.level
            record = log.trials[selection] ?? []
        }
        if let game = MistVoyage(level:level,replay:record), !game.delivered { return game }
        return MistVoyage(level:level)
    }
    func saveTrial(_ v: MistVoyage) throws {
        if v.delivered {
            if authoring {
                let c = try draft.seal(proof:v.history)
                try add(c)
                active = c
                log.authorRoute = []
            }
            if let c = active {
                let id = c.fingerprint
                let previous = log.bests[id].flatMap { MistVoyage(level:c.level,replay:$0) }
                if previous?.delivered != true || v.totalBeats < (previous?.totalBeats ?? .max) { log.bests[id] = v.history }
                log.trials.removeValue(forKey:id)
            }
        } else if authoring { log.authorRoute = v.history }
        else if let active { log.trials[active.fingerprint] = v.history }
        persist()
    }
    func bestRoute(for c: MistWorkshopChart) -> [MistCommand] { log.bests[c.fingerprint] ?? c.level.guide }
}

extension StationView {
    var draftingRect: NSRect { R(30,161,785,439) }
    func beginPainting(at point: MistPoint) {
        guard studio.draft.beginTerrainStroke(studio.brush.tile) else {
            studioAction(.paint(point))
            return
        }
        studio.message = ""
        let tile = studio.draft.tile(at:point)
        if tile == .origin || tile == .harbor {
            studio.message = MistWorkshopError.protectedPort.localizedDescription
            announce(studio.message)
        }
        continuePainting(at:point)
        needsDisplay = true
    }

    func continuePainting(at point: MistPoint?) {
        let former = studio.cursor
        if let point { studio.cursor = point }
        let changed = studio.draft.extendTerrainStroke(to:point)
        if changed {
            studio.message = ""
            studio.edited()
            audio.play(.select)
        }
        if changed || studio.cursor != former { needsDisplay = true }
    }

    func studioAction(_ a: StudioAction) {
        let s = studio
        // A keyboard or accessibility action can interrupt a held mouse drag.
        s.draft.endTerrainStroke()
        s.message = ""
        switch a {
        case .mailbag:
            guard desk == .finale, hasFinalReceipt else { return }
            drawer = .afterpost
            resetFocus()
        case .takeMail(let index):
            guard drawer == .afterpost, hasFinalReceipt, afterpost.indices.contains(index) else { return }
            do {
                let c = afterpost[index]
                try s.add(c)
                s.fromAfterpost = true
                s.message = "已收图。"+c.level.title+"现可启航。"
                drawer = nil
                desk = .chartCase
                resetFocus()
                announce(s.message)
            } catch { notice(error.localizedDescription) }
        case .editor:
            s.fromAfterpost = false
            switchTo(.workshop)
        case .shelf:
            if desk == .workshop { s.fromAfterpost = false }
            desk = .chartCase
            drawer = nil
            resetFocus()
        case .brush(let brush):
            s.brush = brush
            announce("画笔，"+brush.label)
        case .cursor(let move):
            let p = (s.cursor ?? s.paper.level.origin).moved(move)
            if (0..<s.paper.level.width).contains(p.x) && (0..<s.paper.level.height).contains(p.y) { s.cursor = p }
        case .paint(let p):
            s.cursor = p
            do {
                if try s.draft.paint(s.brush.tile,at:p) {
                    s.edited()
                    audio.play(.select)
                }
            } catch { s.message = error.localizedDescription; announce(s.message) }
        case .undo:
            if s.draft.undo() { s.edited(); s.cursor = nil; audio.play(.undo) }
        case .newSheet:
            if s.draft.newSheet() {
                s.edited()
                s.cursor = nil
                s.message = "新草图已铺开。按 Z 可以恢复刚才的草图。"
            }
        case .configure: configureDraft()
        case .trial,.launch:
            guard let trip = s.begin(author:a != .launch) else { return }
            voyage = trip
            activeWire = nil
            hint = nil
            lastEvent = ""
            motionAt = nil
            desk = .sailing
            resetFocus()
            announce("海图试航。"+trip.level.title)
        case .select(let key): s.selection = key; resetFocus()
        case .turnPage(let p): s.page = max(0,p); resetFocus()
        case .sample:
            receiveChart(from:resourceFolder.appendingPathComponent("TideBridge.mistchart"))
        case .importChart:
            let panel = NSOpenPanel()
            panel.title = "打开自制海图"
            panel.allowedContentTypes = [UTType(filenameExtension:"mistchart") ?? .data,.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            guard panel.runModal() == .OK, let url = panel.url else { break }
            receiveChart(from:url)
        case .export:
            let c = desk == .studioReceipt ? s.active : s.selection.flatMap { s.volumes[$0] }
            guard let c else { return }
            let panel = NSSavePanel()
            panel.title = "保存已验航的海图"
            panel.allowedContentTypes = [UTType(filenameExtension:"mistchart") ?? .data]
            panel.canCreateDirectories = true
            let name = c.level.title.replacingOccurrences(of:"/",with:"－").replacingOccurrences(of:":",with:"－")
            panel.nameFieldStringValue = name+".mistchart"
            if panel.runModal() == .OK, let file = panel.url {
                do { try c.encoded().write(to:file,options:.atomic); s.message = "已保存海图文件。" }
                catch { s.message = "海图暂未写入磁盘。"+error.localizedDescription }
                announce(s.message)
            }
        case .remix:
            guard let key = s.selection, let c = s.volumes[key] else { return }
            let alert = NSAlert()
            alert.messageText = "以这张海图开始改绘？"
            alert.informativeText = "当前草图将由《"+c.level.title+"》的副本替换。已封存的海图会保留。"
            alert.addButton(withTitle:"开始改绘")
            alert.addButton(withTitle:"取消")
            if alert.runModal() == .alertFirstButtonReturn {
                s.draft = MistWorkshopDraft(chart:c)
                s.edited()
                s.cursor = nil
                desk = .workshop
                resetFocus()
            }
        case .replay:
            guard let c = s.active else { return }
            openReplay(level:c.level,route:s.bestRoute(for:c))
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
    func receiveChart(from url: URL) {
        let s = studio
        s.fromAfterpost = false
        do {
            guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
            let file = try FileHandle(forReadingFrom:url)
            defer { try? file.close() }
            let bytes = try file.read(upToCount:MistWorkshopChart.maximumFileBytes+1) ?? Data()
            guard bytes.count <= MistWorkshopChart.maximumFileBytes else { throw CocoaError(.fileReadTooLarge) }
            let c = try MistWorkshopChart.open(bytes)
            try s.add(c)
            s.message = "已验明航线并收入海图匣。"
        } catch { s.message = "无法打开海图。"+error.localizedDescription }
        desk = .chartCase
        drawer = nil
        resetFocus()
        announce(s.message)
    }
    private func configureDraft() {
        let field = NSTextField(string:studio.draft.title)
        let author = NSTextField(string:studio.draft.author)
        let letter = NSTextField(wrappingLabelWithString:"")
        letter.isEditable = true
        letter.isSelectable = true
        letter.isBordered = true
        letter.drawsBackground = true
        letter.backgroundColor = .textBackgroundColor
        letter.stringValue = studio.draft.letter
        letter.maximumNumberOfLines = 4
        let size = NSPopUpButton()
        size.addItems(withTitles:["7 × 5", "9 × 7", "11 × 9"])
        let sizes: [MistWorkshopSize] = [.small,.medium,.large]
        size.selectItem(at:sizes.firstIndex(of:studio.draft.size) ?? 0)
        let echoes = NSPopUpButton()
        echoes.addItems(withTitles:["0 艘","1 艘","2 艘"])
        echoes.selectItem(at:studio.draft.echoLimit)
        let beats = NSPopUpButton()
        beats.addItems(withTitles:(5...48).map { "\($0) 拍" })
        beats.selectItem(at:studio.draft.turnLimit-5)
        let grid = NSGridView(views:[
            [NSTextField(labelWithString:"航线名"),field],
            [NSTextField(labelWithString:"署名"),author],
            [NSTextField(labelWithString:"收船回信"),letter],
            [NSTextField(labelWithString:"海图大小"),size],
            [NSTextField(labelWithString:"船影上限"),echoes],
            [NSTextField(labelWithString:"每潮拍数"),beats]
        ])
        grid.column(at:1).width = 275
        grid.rowSpacing = 9
        grid.row(at:2).height = 69
        grid.frame = R(0,0,365,244)
        let panel = NSAlert()
        panel.messageText = "编辑航单"
        panel.informativeText = "回信会在玩家抵达收信灯塔时拆开。"
        panel.addButton(withTitle:"应用")
        panel.addButton(withTitle:"取消")
        panel.accessoryView = grid
        panel.window.initialFirstResponder = field
        guard panel.runModal() == .alertFirstButtonReturn else { return }
        do {
            // Validate metadata before changing dimensions, keeping a failed edit atomic.
            var next = studio.draft
            let modified = try next.configure(title:field.stringValue,author:author.stringValue,letter:letter.stringValue,
                                              echoLimit:echoes.indexOfSelectedItem,turnLimit:beats.indexOfSelectedItem+5)
            let resized = next.resize(sizes[size.indexOfSelectedItem])
            if modified || resized { studio.draft = next; studio.edited(); studio.cursor = nil }
        } catch { studio.message = error.localizedDescription; announce(studio.message) }
    }
}
