import AppKit
import UniformTypeIdentifiers

/// A dispatch card is printed from a delivered journey in this player's ledger.
struct WirePostcard {
    let wire: MistChallenge
    let trip: MistVoyage

    init?(wire: MistChallenge, ledger: StationProfile) {
        guard let best = ledger.telegrams?[wire.code]?.best,
              let delivered = MistVoyage(level:wire.level,replay:best), delivered.delivered else { return nil }
        self.wire = wire
        trip = delivered
    }
}

enum Keepsake { case letter(Int), atlas, telegram(WirePostcard) }

extension StationView {
    func offerPrint(_ item: Keepsake) {
        let name: String
        switch item {
        case .letter(let id):
            guard store.profile.records[id] != nil, let l = MistCampaign.levels.first(where:{ $0.id == id }) else { return }
            name = String(format:"雾信明信片-%02d-",id)+l.title
        case .telegram(let card):
            name = "雾信明信片-"+card.wire.code
        case .atlas:
            guard store.profile.records.count == MistCampaign.levels.count else { return }
            name = "雾信航局-全港邮路图"
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name+".png"
        panel.prompt = "保存"
        panel.title = "印制"+(name.contains("明信片") ? "明信片" : "全港邮路图")
        guard panel.runModal() == .OK, let url = panel.url else {
            window?.makeFirstResponder(self)
            return
        }
        do {
            try keepsakePNG(item).write(to:url,options:.atomic)
            announce("已保存图片。")
        } catch {
            let alert = NSAlert()
            alert.messageText = "图片暂未写入磁盘"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        window?.makeFirstResponder(self)
    }
    func keepsakePNG(_ item: Keepsake) throws -> Data {
        let w = 2400, h = 1500
        guard let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,
                                  space:CGColorSpace(name:CGColorSpace.sRGB)!,
                                  bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteOutOfSpace) }
        ctx.translateBy(x:0,y:CGFloat(h))
        ctx.scaleBy(x:2,y:-2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext:ctx,flipped:true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        P.rect(R(0,0,1200,750),P.paper)
        P.frame(R(20,20,1160,710),P.teal,2)
        P.frame(R(26,26,1148,698),P.teal)
        switch item {
        case .letter(let id):
            guard let level = MistCampaign.levels.first(where: { $0.id == id }),
                  let best = store.profile.records[id] else { throw CocoaError(.fileWriteUnknown) }
            P.mark(R(58,62,58,49),P.teal)
            P.text("雾信航局",R(133,55,360,59),P.serif(36,heavy:true),P.graphite)
            P.text("MIST POST   /   POSTAL CORRESPONDENCE",R(134,113,450,27),P.mono(12,.medium),P.teal,kern:1)
            P.rule(57,149,1086,P.rule)
            P.line([.init(x:559,y:179),.init(x:559,y:663)],P.rule)
            stamp(id:id,in:R(96,193,374,385),paper:P.ink(0xd9c7a1),title:level.postmark)
            postmark(R(367,515,110,110),name:best == level.par ? "准点" : "妥投",id:id,color:P.brick.withAlphaComponent(0.92))
            P.text(level.title,R(79,631,420,47),P.serif(27,heavy:true),P.graphite,align:.center)
            P.text("岛 屿 明 信 片",R(604,57,526,51),P.serif(30,heavy:true),P.graphite,align:.right,kern:2)
            P.text(String(format:"ROUTE %02d  /  ",id)+level.district,R(625,112,506,27),P.mono(13,.semibold),P.teal,align:.right)
            P.text("致  "+level.recipient,R(600,213,520,57),P.serif(28,heavy:true),P.graphite)
            P.text(level.letter,R(601,313,516,205),P.serif(26),P.graphite,wrap:true,spacing:9)
            P.text("——  "+level.sender,R(601,543,509,61),P.serif(22),P.gray,align:.right)
            P.rule(601,624,512,P.rule)
            P.text("最佳航程  \(best) 拍",R(601,642,512,32),P.sans(17,.medium),P.teal)
        case .telegram(let card):
            drawWirePostcard(card)
        case .atlas:
            P.mark(R(56,43,53,41),P.teal)
            P.text("雾信航局 · 全港邮路图",R(127,39,800,58),P.serif(34,heavy:true),P.graphite)
            P.text("十二港全线妥投",R(911,53,229,30),P.sans(17,.semibold),P.teal,align:.right)
            P.rule(55,103,1090,P.rule)
            let map = R(56,124,743,458)
            atlasImage(in:map)
            for level in MistCampaign.levels {
                let p = atlasPoint(level.id,rect:map)
                let mark = R(p.x-12,p.y-12,24,24)
                P.ellipse(mark,fill:P.ochre,stroke:P.night,width:1.6)
                P.text(String(level.id),mark,P.mono(12,.bold),P.deep,align:.center,centerY:true)
            }
            P.frame(map,P.graphite,1.5)
            P.text("妥 投 清 册",R(827,129,310,36),P.serif(22,heavy:true),P.teal)
            for level in MistCampaign.levels {
                let y = 183+CGFloat(level.id-1)*32
                P.text(String(format:"%02d",level.id),R(830,y,35,25),P.mono(14,.bold),P.brick)
                P.text(level.title,R(873,y-3,167,28),P.serif(17,heavy:true),P.graphite)
                if let best = store.profile.records[level.id] {
                    P.text("\(best) 拍",R(1033,y,103,25),P.mono(14),P.gray,align:.right)
                }
            }
            P.rule(55,601,1090,P.rule)
            for l in MistCampaign.levels {
                stamp(id:l.id,in:R(58+CGFloat(l.id-1)*91,617,80,79),paper:P.ink(0xd7c59f))
            }
        }
        guard let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])
        else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    private func drawWirePostcard(_ card: WirePostcard) {
        let wire = card.wire, trip = card.trip
        P.mark(R(54,53,54,43),P.teal)
        P.text("雾信航局  /  远洋邮务",R(126,54,496,42),P.serif(23,heavy:true),P.teal)
        P.text("航线明信片",R(54,110,260,56),P.serif(36,heavy:true),P.graphite)
        P.text("航线电码",R(781,54,357,26),P.sans(15,.semibold),P.teal)
        P.text(wire.code,R(779,90,366,49),P.mono(32,.bold),P.brick)
        P.rule(54,174,1091,P.rule)

        let map = R(55,197,689,360)
        var options = ChartOptions()
        options.reduceMotion = true
        options.highContrast = store.profile.contrast
        chart.draw(in:map,game:trip,time:0,options:options)
        P.frame(map,P.graphite,1)
        P.text(wire.motif,R(55,572,311,41),P.serif(27,heavy:true),P.graphite)
        P.text("船影 \(trip.echoes.count) 艘     邮戳 \(trip.stamped.count) 枚",
               R(360,576,382,31),P.sans(16,.medium),P.teal,align:.right)

        P.text("个人最佳投递航迹",R(781,199,363,43),P.serif(25,heavy:true),P.graphite)
        P.text("总计 \(trip.totalBeats) 拍",R(783,249,363,31),P.sans(17,.semibold),P.brick)
        let crossings = trip.history.split(separator:.record)
        let rowHeight = 294 / CGFloat(crossings.count)
        for (i,crossing) in crossings.enumerated() {
            let y = 292 + CGFloat(i)*rowHeight
            P.rule(782,y,362,P.rule)
            let title = i == crossings.count-1 ? "投递" : "留影 "+String(i+1)
            P.text(title,R(782,y+9,178,26),P.serif(17,heavy:true),P.teal)
            P.text("\(crossing.count) 拍",R(984,y+9,161,25),P.mono(14,.medium),P.gray,align:.right)
            let directions = crossing.compactMap { command -> String? in
                guard case .move(let move) = command else { return nil }
                return move == .wait ? "候" : move.direction
            }
            for index in stride(from:0,to:directions.count,by:20) {
                let end = min(index+20,directions.count)
                let groups = stride(from:index,to:end,by:5).map { offset in
                    directions[offset..<min(offset+5,end)].joined()
                }
                P.text(groups.joined(separator:"  "),R(782,y+42+CGFloat(index/20)*21,363,22),
                       P.sans(15,.medium),P.graphite)
            }
        }
        P.text("每字一拍，候为原地等待。",R(782,584,364,27),P.sans(14),P.gray)
        P.rule(54,627,1091,P.rule)
        P.text("凭码重航",R(55,653,168,37),P.serif(21,heavy:true),P.teal)
        P.text("在电报台选择「输入电码」，即可打开卡上的同一片海域。",R(226,652,785,39),P.sans(17,.medium),P.graphite)
        postmark(R(1050,629,80,80),name:"妥投",id:0,color:P.brick)
    }
}
