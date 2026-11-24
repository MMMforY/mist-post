import AppKit

extension StationView {
    func masthead(dark: Bool = true, showArchive: Bool = true) {
        P.rect(R(0,0,1200,64), P.night)
        P.mark(R(28,15,39,32),P.ochre)
        P.text("雾信航局",R(82,10,118,42),P.serif(25,heavy:true),P.cream,centerY:true)
        P.line([.init(x:201,y:21),.init(x:201,y:44)],P.foam.withAlphaComponent(0.35))
        P.text("MIST POST",R(218,12,205,38),P.mono(13,.semibold),P.foam,kern:2.4,centerY:true)
        target(R(20,8,330,48),.home,"雾信航局首页")
        if showArchive || wireUnlocked {
            button(R(658,14,83,36),.wire(.office),"电报台",style:desk == .telegraph ? .selected : .clear,fontSize:14)
        }
        if showArchive {
            button(R(748,14,83,36),.routes,"航路簿",style:desk == .routes ? .selected : .clear,fontSize:14)
            button(R(837,14,83,36),.album,"收信册",style:desk == .album ? .selected : .clear,fontSize:14)
        }
        P.line([.init(x:932,y:19),.init(x:932,y:45)],P.foam.withAlphaComponent(0.3))
        let sound = R(946,12,44,40)
        if hoverOn(sound) { P.rect(sound,P.sea) }
        P.sound(R(957,22,21,19), on:store.profile.soundOn,color:P.cream)
        target(sound,.sound,store.profile.soundOn ? "关闭声音" : "开启声音")
        button(R(1000,14,82,36),.guide,"航员手册",style:.clear,fontSize:14)
        button(R(1092,14,81,36),.preferences,"设置",style:.dark,fontSize:14)
        P.rule(0,63.5,1200,P.foam.withAlphaComponent(0.27))
    }

    func stampArt(id: Int, in r: NSRect, opacity: CGFloat = 1) {
        let i = max(0,min(11,id-1))
        guard stampImages.indices.contains(i) else { P.mark(r,P.teal); return }
        stampImages[i].draw(in:r,from:.zero,operation:.sourceOver,fraction:opacity,
                            respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
    }
    func stamp(id: Int, in r: NSRect, paper: NSColor, ink: NSColor = P.graphite, title: String? = nil) {
        let dx:CGFloat = max(2.5,min(5,r.width*0.027))
        let pad = max(5,r.width*0.065)
        let base = R(r.minX+dx,r.minY+dx,r.width-2*dx,r.height-2*dx)
        // The perforations are scalloped paper edges on all four sides.
        P.rect(base,paper)
        for x in stride(from:base.minX+dx,through:base.maxX-dx,by:2*dx) {
            for y in [base.minY,base.maxY] { P.ellipse(R(x-dx,y-dx,dx*2,dx*2),fill:paper) }
        }
        for y in stride(from:base.minY+dx,through:base.maxY-dx,by:2*dx) {
            for x in [base.minX,base.maxX] { P.ellipse(R(x-dx,y-dx,dx*2,dx*2),fill:paper) }
        }
        let inner = r.insetBy(dx:pad,dy:pad)
        P.frame(inner,ink,1)
        let labelH:CGFloat = title == nil ? 0 : max(17,r.width*0.16)
        stampArt(id:id,in:R(inner.minX+2,inner.minY+2,inner.width-4,inner.height-labelH-4))
        if let title {
            P.text(title, R(inner.minX+2,inner.maxY-labelH,inner.width-4,labelH),P.serif(max(10,r.width*0.092),heavy:true),ink,align:.center,kern:1.4,centerY:true)
        }
    }
    func postmark(_ r: NSRect, name: String, id: Int, color: NSColor) {
        let s = min(r.width,r.height)
        let ring = R(r.midX-s/2,r.midY-s/2,s,s)
        P.ellipse(ring,stroke:color,width:1.8)
        P.ellipse(ring.insetBy(dx:4,dy:4),stroke:color,width:0.8)
        let b = ring.insetBy(dx:s*0.08,dy:0)
        P.text("MIST POST",R(b.minX,b.minY+s*0.13,b.width,s*0.2),P.mono(s*0.095,.bold),color,align:.center,kern:0.5,centerY:true)
        P.rule(b.minX,b.minY+s*0.37,b.width,color)
        P.text(name,R(b.minX,b.minY+s*0.38,b.width,s*0.27),P.serif(s*0.17,heavy:true),color,align:.center,centerY:true)
        P.rule(b.minX,b.minY+s*0.67,b.width,color)
        P.text(String(format:"PORT %02d",id),R(b.minX,b.minY+s*0.69,b.width,s*0.19),P.mono(s*0.085,.semibold),color,align:.center,kern:0.55,centerY:true)
    }
    func drawCover() {
        P.rect(R(0,0,1200,750),P.night)
        masthead(showArchive:false)
        let art = R(0,64,1200,584)
        if let coverImage { P.imageCover(coverImage,in:art) }
        NSGradient(colors:[P.night.withAlphaComponent(0.85),P.night.withAlphaComponent(0.16),P.night.withAlphaComponent(0.0)])?.draw(in:R(0,64,790,584),angle:0)
        P.rule(54,191,46,P.ochre)
        P.text("M A R I T I M E    P O S T A L    S E R V I C E",R(54,207,530,24),P.mono(11,.medium),P.ochre)
        P.text("雾信航局",R(48,235,615,121),P.serif(91,heavy:true),P.cream,kern:6)
        P.text("MIST    POST",R(58,354,530,45),P.serif(34),P.cream,kern:7)
        P.text("用上一轮潮汐的船影，送达这一封信。",R(56,428,580,42),P.serif(21),P.cream)
        let hasBegan = !store.profile.journeys.isEmpty || !store.profile.records.isEmpty
        let c = R(56,502,211,53)
        P.rect(c,hoverOn(c) ? P.cream : P.ochre)
        P.text(hasBegan ? "继续航行" : "启程送信",R(c.minX+18,c.minY,c.width-66,c.height),P.sans(18,.semibold),P.night,centerY:true)
        P.arrow(R(c.maxX-48,c.midY-6,25,12),color:P.night)
        target(c,.depart,hasBegan ? "继续航行" : "启程送信")
        button(R(282,502,125,53),.routes,"查看航路",style:.dark,fontSize:16)
        P.rect(R(0,648,1200,102),P.paper)
        P.rule(0,652,1200,P.rule)
        let n = store.profile.records.count
        let id = store.nextUndelivered
        let l = MistCampaign.levels.first(where: { $0.id == id }) ?? MistCampaign.levels[0]
        P.text("值班航线",R(55,663,105,26),P.sans(13,.semibold),P.gray)
        P.text(l.district+"   /   "+l.title,R(54,690,510,39),P.serif(24,heavy:true),P.graphite)
        P.line([.init(x:676,y:670),.init(x:676,y:727)],P.rule)
        P.text("投递进度",R(707,667,150,23),P.sans(13,.semibold),P.gray)
        P.text(String(format:"%02d  /  %02d",n,MistCampaign.levels.count),R(707,694,190,32),P.mono(22,.medium),P.graphite)
        button(R(992,675,156,49),.album,"翻阅收信册  ↗",fontSize:16)
        if let warning = store.notice {
            P.rect(R(0,620,1200,28),P.brick)
            P.text(warning,R(25,620,1150,28),P.sans(14),P.cream,centerY:true)
        }
    }

    func drawSailing() {
        let game = shownTrip, level = game.level, replay = desk == .replay
        P.rect(R(0,0,1200,750),P.paper)
        masthead()
        let id = String(format:"%02d",level.id)
        P.text(level.id < 0 ? "自绘海图   /   "+level.sender : level.id == 0 ? "远洋电报   /   "+(activeWire?.code ?? "") : "第 "+id+" 航线   /   "+level.district,R(29,78,600,25),P.sans(13,.semibold),P.teal,kern:0.7)
        P.text(level.title,R(26,99,630,47),P.serif(35,heavy:true),P.graphite)
        P.text(replay ? "航 程 回 放" : "领 航 海 图",R(653,103,178,31),P.serif(17,heavy:true),P.teal,align:.right,centerY:true)
        drawSeaChart(game,replay:replay)
        drawTimeline(game, replay:replay)
        drawManifest(game, replay:replay)
        if let m = store.notice {
            P.text(m,R(32,725,760,20),P.sans(12,.medium),P.brick)
        }
    }
    func drawSeaChart(_ game: MistVoyage, replay: Bool) {
        var options = ChartOptions()
        options.reduceMotion = store.profile.lowMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        options.highContrast = store.profile.contrast
        options.showTrails = store.profile.trails
        options.hintPoint = replay ? nil : (hint?.point ?? (clock-lastEventTime < 4 ? inspectedPoint : nil))
        options.hoverPoint = (!replay && drawer == nil && hover.map(isAdjacent) == true) ? hover.flatMap { chart.cell(at:$0,in:chartRect,game:game) } : nil
        options.motionStartedAt = motionAt
        options.previewBeat = replay ? nil : previewBeat
        if !replay, clock-lastEventTime < 4 { options.signalStations = signalInspection?.points ?? [] }
        chart.draw(in:chartRect,game:game,time:clock,options:options)
        P.frame(chartRect,P.graphite,1.5)
    }
    func drawManifest(_ game: MistVoyage, replay: Bool) {
        let l = game.level
        let x:CGFloat = 860, w:CGFloat = 312
        P.rect(R(x,86,w,488),P.ink(0xf6eedb))
        P.frame(R(x,86,w,488),P.rule)
        for i in 0..<20 {
            let px = x+CGFloat(i)*15.6
            let col = i % 2 == 0 ? P.teal : P.brick
            P.polygon([.init(x:px,y:86),.init(x:px+8,y:86),.init(x:px+13,y:91),.init(x:px+5,y:91)],fill:col.withAlphaComponent(0.75))
        }
        P.text("随 船 邮 单",R(x+18,105,180,28),P.serif(19,heavy:true),P.graphite)
        P.text(l.id < 0 ? "CHART / LOCAL" : String(format:"MP / %03d",l.id),R(x+150,108,w-168,22),P.mono(12,.medium),P.gray,align:.right)
        P.rule(x+18,142,w-36,P.rule)
        if l.id < 0 { postmark(R(x+16,158,81,81),name:"自绘",id:1,color:P.teal) }
        else { stamp(id:l.id,in:R(x+17,157,75,83),paper:P.ink(0xe9d8b2),title:l.postmark) }
        P.text("寄往",R(x+109,164,172,22),P.sans(12,.semibold),P.gray)
        P.text(l.recipient,R(x+108,187,190,44),P.serif(23,heavy:true),P.graphite,wrap:true)
        P.rule(x+18,257,w-36,P.rule)
        if !replay, !l.signalIDs.isEmpty {
            let first = x+w-18-CGFloat(l.signalIDs.count)*34
            P.text("查铃",R(first-48,266,42,27),P.sans(12,.medium),P.teal,align:.right,centerY:true)
            for (slot,id) in l.signalIDs.enumerated() {
                let box = R(first+CGFloat(slot)*34,266,31,27)
                let active = signalInspection?.id == id && clock-lastEventTime < 4
                P.rect(box,active ? P.sea : (hoverOn(box) ? P.cream : P.paper))
                P.frame(box,P.teal)
                P.text(String(id+1),box,P.mono(14,.semibold),active ? P.cream : P.teal,align:.center,centerY:true)
                target(box,.signal(id),"查阅"+MistLevel.signalName(id)+"铃标与水闸")
            }
        }
        P.text("本航任务",R(x+18,271,94,24),P.sans(13,.semibold),P.teal,kern:1)
        P.text(l.briefing,R(x+18,299,w-36,74),P.serif(19),P.graphite,wrap:true,spacing:3)
        P.rule(x+18,382,w-36,P.rule)
        P.text("船影",R(x+18,397,60,24),P.sans(14,.medium),P.gray)
        P.text("\(game.echoes.count) / \(l.echoLimit)",R(x+93,393,w-113,26),P.mono(17,.medium),P.graphite,align:.right)
        P.text("邮戳",R(x+18,429,74,24),P.sans(14,.medium),P.gray)
        P.text(l.stamps.isEmpty ? "直投" : "\(game.stamped.count) / \(l.stamps.count)",R(x+93,425,w-113,28),P.sans(17,.semibold),P.graphite,align:.right)
        P.rule(x+18,461,w-36,P.rule)
        let showingEvent = !replay && !lastEvent.isEmpty && clock-lastEventTime < 4
        let msg: String
        if replay { msg = "点选航程和潮拍可跳到那一刻。左右键逐步回看，空格播放或暂停。" }
        else if showingEvent { msg = lastEvent }
        else if let hint { msg = hint.text }
        else if let previewBeat { msg = "正预览第 \(previewBeat) 拍的船影与闸门。点击「现在」回到航行。" }
        else if game.beat == l.turnLimit { msg = game.canRecord ? "本潮已尽，按 E 将这一程留作船影。" : "本潮已尽，按 Z 撤回或点「重航」。" }
        else if case .buoy = l.tile(at:game.position), game.canRecord { msg = "在铃标上按 E 留影。新一程中，船影会替你守住铃标。" }
        else if l.id < 0 && studio.authoring { msg = "亲自送达即可验航并封存。按 Esc 返回制图室继续改绘。" }
        else if l.id == 1 { msg = "用方向键，或点击相邻水格驶向灯塔。每次移动消耗一拍。" }
        else if !game.echoes.isEmpty { msg = "下方潮表可预览任一拍的船影位置。" }
        else { msg = "船影能敲响铃标。需要领航时，按 H 查看下一步。" }
        P.text(showingEvent ? "航局电报" : (hint != nil && !replay ? "领航提示" : "值班记录"),R(x+18,474,w-36,19),P.sans(12,.semibold),showingEvent ? P.brick : P.teal)
        P.text(msg,R(x+18,499,w-36,65),P.sans(15,.medium),P.graphite,wrap:true,spacing:2)
        if replay {
            button(R(x,590,w,47),.replayPlay,replayRunning ? "暂停回放" : (replayIndex == replayRoute.count ? "再看一遍" : "播放航程"),style:.selected,key:"␣")
            button(R(x,647,150,38),.replayPrevious,"上一步",enabled:replayIndex>0)
            button(R(x+160,647,152,38),.replayNext,"下一步",enabled:replayIndex<replayRoute.count)
            button(R(x,697,150,32),.replaySpeed,"速度  "+replaySpeed.label,key:"V",fontSize:13)
            let returnLabel = l.id == 0 ? "返回电报" : (l.id < 0 ? "返回回执" : "返回信件")
            button(R(x+160,697,152,32),.back,returnLabel,fontSize:13)
        } else {
            button(R(x,590,w,47),.record,"留影返航",style:game.canRecord ? .primary : .paper,key:"E",enabled:game.canRecord,fontSize:18)
            button(R(x,647,150,38),.move(.wait),"候一拍",key:"␣",enabled:game.beat<l.turnLimit)
            button(R(x+160,647,152,38),.undo,"撤回",key:"Z",enabled:game.canUndo)
            button(R(x,697,150,32),.hint,"领航提示",key:"H",enabled:l.id >= 0 || !studio.authoring,fontSize:13)
            button(R(x+160,697,152,32),.restart,"重航",key:"R",enabled:game.canUndo,fontSize:13)
        }
    }
    func drawTimeline(_ game: MistVoyage, replay: Bool) {
        let l = game.level, y:CGFloat = 589
        P.rect(R(28,y,808,140),P.deep)
        P.text(replay ? "回放潮表" : "潮汐节拍",R(47,y+12,155,28),P.serif(20,heavy:true),P.cream)
        let beat = previewBeat ?? game.beat
        P.text(String(format:"%02d / %02d",beat,l.turnLimit),R(177,y+15,150,23),P.mono(15,.medium),P.ochre)
        if previewBeat != nil && !replay { button(R(745,y+9,72,26),.live,"现在",style:.dark,fontSize:12) }
        else { P.text(replay ? "操作 \(replayIndex) / \(replayRoute.count)" : "点选节拍可预览",R(570,y+14,244,23),P.sans(12),P.foam,align:.right) }
        if replay {
            for index in replayLegs.indices {
                let label = "第" + String(index+1) + "程"
                button(R(337+CGFloat(index)*73,y+8,67,27),.replayLeg(index),label,
                       style:game.echoes.count == index ? .selected : .dark,fontSize:13)
            }
        }
        let left:CGFloat = 101, right:CGFloat = 810
        let lineY = y + (game.echoes.isEmpty ? 65 : 46)
        let spacing = (right-left)/CGFloat(l.turnLimit+1)
        let maxTick = l.turnLimit
        P.text("潮拍",R(47,lineY-11,48,24),P.sans(14,.semibold),P.cream)
        for i in 0...maxTick {
            let px = left + (CGFloat(i)+0.5)*spacing
            let current = i == beat
            let past = i <= game.beat
            let radius:CGFloat = current ? 6.5 : 3
            let color = current ? P.ochre : (past ? P.foam : P.foam.withAlphaComponent(0.5))
            if i < maxTick { P.rule(px,lineY,spacing,P.foam.withAlphaComponent(0.4)) }
            P.ellipse(R(px-radius,lineY-radius,2*radius,2*radius),fill:past || current ? color : P.deep,stroke:color)
            if current || i==0 || i==maxTick || (maxTick<17 ? i % 2 == 0 : i % 4 == 0) {
                P.text(String(format:"%02d",i),R(px-14,lineY+9,28,19),P.mono(10,current ? .bold : .regular),color,align:.center)
            }
            let tick = R(px-spacing/2,lineY-13,spacing,44)
            if replay, replayLegs.indices.contains(game.echoes.count) {
                let leg = replayLegs[game.echoes.count]
                let step = leg.lowerBound+i
                if leg.contains(step) { target(tick,.replaySeek(step),"回看第 \(game.echoes.count+1) 程第 \(i) 拍") }
            } else if !replay { target(tick,.preview(i),"预览第 \(i) 拍") }
            for (j,pt) in game.echoPositions(at:i).enumerated() {
                let yy = y+78+CGFloat(j)*17
                if case .buoy(let id) = l.tile(at:pt) {
                    signalMark(id,at:.init(x:px,y:yy),size:3.2,ink:j == 0 ? P.foam : P.ink(0xe7c5de))
                } else {
                    P.rule(px-2,yy,4,P.foam.withAlphaComponent(0.35))
                }
            }
        }
        for j in game.echoes.indices {
            P.text("影"+String(j+1),R(47,y+68+CGFloat(j)*17,50,19),P.sans(12,.medium),P.foam)
        }
        P.rule(47,y+106,770,P.foam.withAlphaComponent(0.28))
        let footer = replay ? "← →  逐步回放      ↑ ↓  换程      空格  播放／暂停      V  速度" : "↑ ↓ ← →  航行      空格  候潮      E  留影      Z  撤回"
        P.text(footer,R(47,y+111,760,24),P.sans(13,.medium),P.foam)
    }
}
