import AppKit

@MainActor
enum WireCardCheck {
    static func run(resources: URL, folder: URL) throws {
        let base = folder.appendingPathComponent("wire-profile-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:base) }
        let save = base.appendingPathComponent("dispatch.json")
        let view = StationView(store:DispatchStore(file:save),resources:resources)
        view.frozenTime = 42
        for level in MistCampaign.levels.prefix(4) {
            view.store.save(MistVoyage(level:level,replay:level.guide)!)
        }
        let wire = MistChallenge.make(seed:0x2c1464)
        let blank = MistChallenge.make(seed:0x3ce1)
        let slower = wire.level.guide.prefix(upTo:wire.level.guide.count-1) + [.move(.wait),wire.level.guide.last!]
        guard let proof = MistVoyage(level:wire.level,replay:Array(slower)), proof.delivered,
              proof.echoes.count == 2 && proof.totalBeats == wire.level.par+1 else { throw CocoaError(.fileReadCorruptFile) }
        let action = DeskAction.wire(.printCard)
        func snapshot(_ v: StationView,_ name: String) throws {
            try qaSnapshot(v,to:folder.appendingPathComponent(name+".png"))
        }
        func hasButton(_ v: StationView) -> Bool { v.targets.contains { $0.action == action && $0.enabled } }
        func checkFocus(_ v: StationView) {
            for _ in 0...v.targets.count where v.focused != action { v.handleKey(48,character:"\t") }
            precondition(v.focused == action)
            let buttons = v.accessibilityChildren() as? [NSAccessibilityElement] ?? []
            precondition(buttons.contains {
                $0.accessibilityRole() == .button && $0.accessibilityLabel() == "印制航线明信片" && $0.isAccessibilityEnabled()
            })
        }
        view.act(.wire(.office))
        view.setWire(wire)
        precondition(WirePostcard(wire:wire,ledger:view.store.profile) == nil)
        try snapshot(view,"wire-before")
        precondition(!hasButton(view))
        view.act(.wire(.launch))
        for cmd in slower { view.operate(cmd) }
        precondition(view.desk == .telegramReceipt)
        try snapshot(view,"wire-receipt")
        precondition(hasButton(view))
        checkFocus(view)
        guard let card = WirePostcard(wire:wire,ledger:view.store.profile) else { throw CocoaError(.fileReadCorruptFile) }
        precondition(card.trip.history == Array(slower))
        let data = try view.keepsakePNG(.telegram(card))
        guard let bitmap = NSBitmapImageRep(data:data), bitmap.pixelsWide == 2400 && bitmap.pixelsHigh == 1500 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try data.write(to:folder.appendingPathComponent("wire-card.png"))
        let reopened = StationView(store:DispatchStore(file:save),resources:resources)
        reopened.frozenTime = 42
        reopened.act(.wire(.office))
        reopened.setWire(blank)
        reopened.act(.wire(.launch))
        reopened.operate(blank.level.guide[0])
        reopened.act(.wire(.office))
        reopened.setWire(blank)
        try snapshot(reopened,"wire-partial")
        precondition(!hasButton(reopened) && WirePostcard(wire:blank,ledger:reopened.store.profile) == nil)
        precondition(reopened.targets.contains { $0.action == .wire(.open(wire.code)) })
        reopened.act(.wire(.open(wire.code)))
        try snapshot(reopened,"wire-archive")
        precondition(hasButton(reopened))
        checkFocus(reopened)
        guard let selected = reopened.selectedWire,
              let archived = WirePostcard(wire:selected,ledger:reopened.store.profile) else { throw CocoaError(.fileReadCorruptFile) }
        precondition(archived.wire.code == wire.code && archived.trip.history == Array(slower))
        print("PASS printed 2400×1500 wire \(wire.code), \(proof.totalBeats) actual beats, \(proof.echoes.count) echoes, cold archive reprint, draft protection and native buttons")
    }
}
