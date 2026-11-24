import AppKit

struct TelegramEntry: Codable, Equatable {
    var draft: [MistCommand] = []
    var best: [MistCommand]?
    var visited: Date
}
enum WireAction: Hashable {
    case office, daily, tune, enterCode, open(String), page(Int), launch, copyCode, listenAgain, replay, printCard
}

extension StationView {
    var wireUnlocked: Bool { store.profile.records[4] != nil }
    var wireID: String? { activeWire?.code }
    func dailyWire(date: Date = Date()) -> MistChallenge {
        let parts = Calendar(identifier:.gregorian).dateComponents(in:.current,from:date)
        let key = UInt64((parts.year ?? 2000)*10000 + (parts.month ?? 1)*100 + (parts.day ?? 1))
        var value = key &+ 0x9e3779b97f4a7c15
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return MistChallenge.make(seed:value ^ (value >> 31))
    }
    func setWire(_ wire: MistChallenge) {
        selectedWire = wire
        wireNotice = nil
        resetFocus()
    }
    func wireAction(_ action: WireAction) {
        switch action {
        case .office:
            if selectedWire == nil { setWire(dailyWire()) }
            switchTo(.telegraph)
        case .page(let n): wirePage = max(0,n); resetFocus()
        case .daily: setWire(dailyWire())
        case .tune: setWire(MistChallenge.make(seed:UInt64.random(in:0..<(1<<30))))
        case .open(let code):
            guard let c = MistChallenge.open(code:code) else { return }
            setWire(c)
        case .enterCode:
            let alert = NSAlert()
            alert.messageText = "接收航线电码"
            alert.informativeText = "输入电报台印出的 M1 电码，即可重现同一张海图。"
            alert.addButton(withTitle:"接收")
            alert.addButton(withTitle:"取消")
            let field = NSTextField(frame:R(0,0,300,28))
            field.placeholderString = "M1-…"
            field.font = P.mono(17)
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            if alert.runModal() == .alertFirstButtonReturn {
                if let c = MistChallenge.open(code:field.stringValue) { setWire(c) }
                else { wireNotice = "电码未通过校验，请核对字母和数字。"; announce(wireNotice!) }
            }
            window?.makeFirstResponder(self)
        case .launch:
            guard wireUnlocked, let c = selectedWire else { return }
            catalogReturns.removeAll()
            activeWire = c
            wirePage = 0
            voyage = MistVoyage(level:c.level,replay:store.profile.telegrams?[c.code]?.draft ?? []) ?? MistVoyage(level:c.level)
            if voyage.delivered { voyage = MistVoyage(level:c.level) }
            desk = .sailing
            drawer = nil
            motionAt = nil
            hint = nil
            lastEvent = ""
            lastEventTime = -100
            persistVoyage()
            resetFocus()
            announce("远洋电报，"+c.motif+"。"+c.level.briefing)
        case .copyCode:
            guard let c = (desk == .telegraph ? selectedWire : activeWire) else { return }
            let board = NSPasteboard.general
            board.clearContents()
            if board.setString(c.code,forType:.string) {
                wireNotice = "已复制电码 "+c.code
                announce(wireNotice!)
            }
        case .printCard:
            let wire = desk == .telegramReceipt ? activeWire : (desk == .telegraph ? selectedWire : nil)
            guard let wire, let card = WirePostcard(wire:wire,ledger:store.profile) else { return }
            offerPrint(.telegram(card))
        case .listenAgain:
            if let c = activeWire { setWire(c); desk = .telegraph }
            resetFocus()
        case .replay:
            guard let c = activeWire, let route = store.profile.telegrams?[c.code]?.best else { return }
            openReplay(level:c.level,route:route)
        }
        audio.play(.select)
        needsDisplay = true
    }
    func persistVoyage() {
        if voyage.level.id == -1 {
            do { try studio.saveTrial(voyage) }
            catch { studio.message = error.localizedDescription; announce(studio.message) }
            return
        }
        guard voyage.level.id == 0, let wireID else { store.save(voyage); return }
        store.update { profile in
            var entries = profile.telegrams ?? [:]
            var entry = entries[wireID] ?? TelegramEntry(visited:Date())
            entry.visited = Date()
            if voyage.delivered {
                let old = entry.best.flatMap { MistVoyage(level:voyage.level,replay:$0) }
                if old?.delivered != true || voyage.totalBeats < (old?.totalBeats ?? .max) {
                    entry.best = voyage.history
                }
                entry.draft = []
            } else {
                entry.draft = voyage.history
            }
            entries[wireID] = entry
            profile.telegrams = entries
        }
    }

    func drawWire() {
        P.rect(R(0,0,1200,750),P.paper)
        masthead()
        P.text("远洋班次  /  WIRE SERVICE",R(43,96,810,25),P.mono(13,.semibold),P.teal,kern:1)
        P.text("电报台",R(39,127,680,67),P.serif(49,heavy:true),P.graphite)
        P.text("每串电码对应一条可重访的航路。",R(43,195,760,32),P.sans(17),P.gray)
        P.rule(42,239,1116,P.rule)
        guard wireUnlocked else {
            P.rect(R(42,266,1116,315),P.deep)
            stamp(id:4,in:R(95,302,157,206),paper:P.pale,title:"盐风外港")
            P.text("外港联络尚待接通",R(302,315,750,59),P.serif(33,heavy:true),P.cream)
            P.text("送达盐风外港的四封信后，即可在这里收听每日航线，或凭电码驶入新的海域。",R(304,396,663,101),P.serif(20),P.cream,wrap:true,spacing:6)
            button(R(43,628,178,47),.depart,"继续送信  →",style:.selected)
            button(R(241,628,143,47),.back,"返回")
            return
        }
        guard let c = selectedWire else { return }
        let card = R(42,267,686,341)
        P.rect(card,P.ink(0xf9f1db))
        P.frame(card,P.rule)
        for j in 0..<15 {
            let yy = card.minY+10+CGFloat(j)*22
            P.ellipse(R(card.minX+8,yy,5,5),fill:P.paper,stroke:P.rule,width:0.5)
            P.ellipse(R(card.maxX-13,yy,5,5),fill:P.paper,stroke:P.rule,width:0.5)
        }
        P.text("航 线 电 报",R(74,287,300,36),P.serif(22,heavy:true),P.graphite)
        P.text("MIST POST   //   RADIO",R(372,293,320,25),P.mono(12,.semibold),P.gray,align:.right,kern:1)
        P.rule(75,335,619,P.rule)
        P.text(c.code,R(73,357,630,62),P.mono(38,.bold),P.brick,kern:2)
        P.text(c.motif,R(74,433,475,46),P.serif(28,heavy:true),P.graphite)
        P.text(c.level.briefing,R(75,487,617,77),P.sans(17),P.graphite,wrap:true,spacing:3)
        P.text("\(c.level.echoLimit) 艘船影     潮限 \(c.level.turnLimit) 拍     参考总拍 \(c.level.par)",R(75,566,617,27),P.sans(14,.semibold),P.teal)
        let receive = store.profile.telegrams?[c.code]?.draft.isEmpty == false ? "续航这封电报  →" : "接受航线  →"
        button(R(43,636,205,49),.wire(.launch),receive,style:.selected,fontSize:17)
        button(R(262,636,136,49),.wire(.copyCode),"复制电码")
        button(R(412,636,136,49),.wire(.enterCode),"输入电码")
        if store.profile.telegrams?[c.code]?.best != nil {
            button(R(562,636,165,49),.wire(.printCard),"印制航线明信片")
        }
        button(R(749,267,182,45),.wire(.daily),"接收今日电报")
        button(R(945,267,211,45),.wire(.tune),"随机收听  ↻")
        P.text("最近航件",R(751,341,403,35),P.serif(23,heavy:true),P.graphite)
        P.rule(751,389,405,P.rule)
        let entries = (store.profile.telegrams ?? [:]).sorted {
            $0.value.visited == $1.value.visited ? $0.key < $1.key : $0.value.visited > $1.value.visited
        }
        let pages = max(1,(entries.count+3)/4)
        let index = min(wirePage,pages-1)
        let recent = entries.dropFirst(index*4).prefix(4)
        if pages > 1 {
            button(R(989,339,36,31),.wire(.page(index-1)),"‹",enabled:index>0,fontSize:17)
            P.text("\(index+1)/\(pages)",R(1031,341,78,28),P.mono(13),P.gray,align:.center,centerY:true)
            button(R(1117,339,37,31),.wire(.page(index+1)),"›",enabled:index+1<pages,fontSize:17)
        }
        if recent.isEmpty {
            P.text("接受第一封电报后，这里会记录你的航程。",R(752,416,370,92),P.sans(16),P.gray,wrap:true)
        }
        for (i,item) in recent.enumerated() {
            let row = R(752,404+CGFloat(i)*49,403,42)
            let selected = item.key == c.code
            if hoverOn(row) || selected { P.rect(row,P.ink(0xd9dcc6)) }
            P.text(item.key,R(row.minX+8,row.minY,235,row.height),P.mono(16,.semibold),P.graphite,centerY:true)
            P.text(item.value.best == nil ? "航行中" : "已投递",R(row.maxX-118,row.minY,107,row.height),P.sans(13,.semibold),P.teal,align:.right,centerY:true)
            target(row,.wire(.open(item.key)),"选择电码 "+item.key+(item.value.best == nil ? "，航行中" : "，已投递"))
        }
        P.rule(751,609,405,P.rule)
        button(R(1018,644,137,38),.back,"←  返回",fontSize:14)
        if let wireNotice { P.text(wireNotice,R(43,702,960,28),P.sans(14,.semibold),P.brick) }
    }

    func drawWireReceipt() {
        guard let c = activeWire else { return }
        P.rect(R(0,0,1200,750),P.deep)
        if let coverImage { P.imageCover(coverImage,in:R(0,64,1200,686)); P.rect(R(0,64,1200,686),P.night.withAlphaComponent(0.8)) }
        masthead()
        let slip = R(156,124,888,425)
        P.rect(slip,P.paper)
        P.frame(slip.insetBy(dx:9,dy:9),P.rule)
        P.text("远洋电报已妥投",R(198,161,800,63),P.serif(40,heavy:true),P.graphite)
        P.text(c.code,R(201,238,728,42),P.mono(25,.semibold),P.teal,kern:1)
        P.rule(200,301,800,P.rule)
        P.text(c.motif,R(202,331,607,48),P.serif(28,heavy:true),P.graphite)
        P.text("本次航程 \(voyage.totalBeats) 拍，留影 \(voyage.echoes.count) 艘。",R(203,397,620,43),P.sans(21),P.graphite)
        P.text("该电码的最佳航程已收入电报台。",R(203,474,610,36),P.sans(16),P.gray)
        postmark(R(832,336,133,133),name:"妥投",id:0,color:P.brick)
        button(R(156,585,171,49),.wire(.copyCode),"复制电码",style:.dark)
        button(R(343,585,197,49),.wire(.replay),"回看最佳航程",style:.dark)
        if store.profile.telegrams?[c.code]?.best != nil {
            button(R(556,585,207,49),.wire(.printCard),"印制航线明信片",style:.dark)
        }
        button(R(823,585,221,49),.wire(.listenAgain),"返回电报台  →",style:.primary)
        if let wireNotice { P.text(wireNotice,R(157,659,855,28),P.sans(15),P.cream) }
    }
}
