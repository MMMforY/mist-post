import AppKit

extension StationView {
    var hasFinalReceipt: Bool {
        let records = store.profile.records
        return MistCampaign.levels.allSatisfy { records[$0.id] != nil }
    }

    func drawCatalog() {
        let album = desk == .album
        P.rect(R(0,0,1200,750),P.paper)
        masthead()
        let levels = MistCampaign.levels
        let entries = Array(levels.dropFirst(chapter*4).prefix(4))
        guard let first = entries.first else { return }
        P.text(album ? "来信存档  /  CORRESPONDENCE" : "航区索引  /  ROUTE INDEX",R(42,93,750,27),P.mono(13,.semibold),P.teal,kern:1)
        P.text(album ? "收信册" : "航路簿",R(39,126,550,68),P.serif(48,heavy:true),P.graphite)
        P.text(album ? "投递后，可在这里重读来信与回看航程。" : "从三个航区选择本班要送的信。",R(43,196,780,27),P.sans(16),P.gray)
        P.text(String(format:"%02d / %02d",store.profile.records.count,levels.count),R(888,131,270,60),P.mono(37,.semibold),P.teal,align:.right)
        P.text("已投递",R(998,190,160,24),P.sans(14,.medium),P.gray,align:.right)
        P.rule(42,239,1116,P.rule)
        for (index, l) in stride(from:0,to:levels.count,by:4).map({ levels[$0] }).enumerated() {
            let box = R(42+CGFloat(index)*168,257,155,37)
            button(box,.chapter(index),String(format:"%02d",index+1)+"   "+l.district,
                   style:index == chapter ? .selected : .paper,fontSize:14)
        }
        P.text(first.district+"  /  四封",R(850,261,306,26),P.serif(17),P.gray,align:.right)
        for (j,l) in entries.enumerated() {
            let x:CGFloat = 42+CGFloat(j)*282
            let card = R(x,322,267,318)
            let delivered = store.profile.records[l.id] != nil
            let accessible = album ? delivered : store.unlocked(l.id)
            let hot = hoverOn(card) && accessible
            P.rect(card,hot ? P.cream : P.ink(0xf5edda))
            P.frame(card,hot ? P.teal : P.rule,hot ? 2 : 1)
            let stampRect = R(x+70,343,127,135)
            if album && !delivered {
                P.frame(stampRect,P.rule)
                P.frame(stampRect.insetBy(dx:5,dy:5),P.rule)
                postmark(stampRect.insetBy(dx:26,dy:30),name:"待收",id:l.id,color:P.rule)
            } else {
                stamp(id:l.id,in:stampRect,paper:P.ink(0xd8c9a9),title:l.postmark)
            }
            P.rule(x+17,498,233,P.rule)
            P.text(String(format:"航线 %02d",l.id),R(x+17,511,138,22),P.mono(13,.medium),P.teal)
            P.text(delivered ? "已投递" : (accessible ? "可启航" : (album ? "待投递" : "待解锁")),R(x+132,511,116,22),P.sans(13,.medium),delivered ? P.brick : P.gray,align:.right)
            P.text(l.title,R(x+15,541,239,45),P.serif(25,heavy:true),P.graphite)
            let desc: String
            if delivered { desc = "最佳航程  "+String(store.profile.records[l.id] ?? 0)+" 拍" }
            else if accessible { desc = (store.profile.journeys[l.id]?.isEmpty == false) ? "继续未完成的投递" : "收信人  "+l.recipient }
            else { desc = album ? "投递后收入此册" : "完成上一条航路后开启" }
            P.text(desc,R(x+17,597,233,25),P.sans(13),P.gray)
            target(card,album ? .letter(l.id) : .route(l.id),l.title+"，"+desc,accessible)
        }
        P.rule(42,669,1116,P.rule)
        button(R(42,687,141,37),.back,"←  返回",fontSize:14)
        if album && hasFinalReceipt {
            button(R(926,683,232,45),.readFinale,"重读结航回函  →",style:.primary,fontSize:16)
        } else {
            P.text("雾信航局  ·  "+first.district,R(672,691,486,27),P.serif(15),P.gray,align:.right)
        }
    }

    func drawLetter(id: Int) {
        guard let level = MistCampaign.levels.first(where:{ $0.id == id }) else { return }
        let deliveredNow = letterReturn == .sailing
        P.rect(R(0,0,1200,750),P.night)
        if let coverImage {
            P.imageCover(coverImage,in:R(0,64,1200,686))
            P.rect(R(0,64,1200,686),P.night.withAlphaComponent(0.79))
        }
        masthead()
        let card = R(111,108,978,497)
        P.rect(card.offsetBy(dx:7,dy:9),P.night.withAlphaComponent(0.6))
        P.rect(card,P.paper)
        P.frame(card.insetBy(dx:8,dy:8),P.rule)
        P.text(deliveredNow ? "邮件已送达" : "馆藏来信",R(150,146,615,55),P.serif(37,heavy:true),P.graphite)
        P.text(String(format:"航线 %02d   /   ",id)+level.district+"   /   "+level.title,
               R(154,207,621,29),P.sans(15,.medium),P.teal)
        P.rule(153,256,896,P.rule)
        P.text("致  "+level.recipient,R(155,283,555,39),P.serif(23,heavy:true),P.graphite)
        P.text(level.letter,R(155,346,537,159),P.serif(23),P.graphite,wrap:true,spacing:8)
        P.text("——  "+level.sender,R(158,513,527,48),P.serif(20),P.gray,align:.right)
        P.line([.init(x:733,y:282),.init(x:733,y:561)],P.rule)
        stamp(id:id,in:R(836,273,166,180),paper:P.ink(0xd1c39f),title:level.postmark)
        postmark(R(759,383,93,93),name:(deliveredNow ? voyage.totalBeats : store.profile.records[id]) == level.par ? "准点" : "妥投",id:id,color:P.brick.withAlphaComponent(0.85))
        P.rule(766,491,275,P.rule)
        let beats = deliveredNow ? voyage.totalBeats : store.profile.records[id] ?? 0
        P.text("航程  \(beats) 拍",R(768,505,267,29),P.serif(20,heavy:true),P.graphite,align:.center)
        P.text("最短总拍  \(level.par) 拍",R(766,543,270,24),P.sans(14),P.gray,align:.center)
        button(R(111,635,173,50),.album,"翻阅收信册",style:.dark)
        button(R(300,635,188,50),.replay(id),"回看最佳航程",style:.dark,enabled:store.profile.winningRoutes[id] != nil)
        button(R(503,635,174,50),.printLetter(id),"印制明信片",style:.dark)
        if deliveredNow {
            let lastLetter = id == MistCampaign.levels.last?.id
            let title = lastLetter && hasFinalReceipt ? "领取结航回函  →" : "下一封信  →"
            button(R(858,635,231,50),.next,title,style:.primary,fontSize:18)
        } else {
            button(R(858,635,231,50),.route(id),"重走这条航路  →",style:.primary,fontSize:17)
        }
    }
    func drawFinale() {
        P.rect(R(0,0,1200,750),P.night)
        if let coverImage { P.imageCover(coverImage,in:R(0,64,1200,686)) }
        P.rect(R(0,64,1200,686),P.night.withAlphaComponent(0.63))
        masthead()
        let card = R(99,133,625,498)
        P.rect(card,P.paper)
        P.frame(card.insetBy(dx:8,dy:8),P.teal)
        P.text("总 局 回 函",R(137,173,340,33),P.serif(20,heavy:true),P.teal,kern:3)
        P.text("致最后一位航员",R(135,226,565,65),P.serif(40,heavy:true),P.graphite)
        P.rule(139,304,540,P.rule)
        P.text("今夜，十二扇窗都亮了。\n有人把邮戳压在枕下，有人开始修桥。你留在海上的船影还守着那些铃。\n\n下一次起雾，港里的人知道该听哪里。",R(138,337,530,180),P.serif(21),P.graphite,wrap:true,spacing:5)
        P.text("雾信航局  谨上",R(139,554,520,41),P.serif(19),P.teal,align:.right)
        button(R(771,411,241,48),.studio(.mailbag),"拆阅三份港民来图",style:.dark)
        button(R(771,478,241,53),.album,finaleFromAlbum ? "返回收信册  →" : "翻开完整收信册  →",style:.primary,fontSize:17)
        button(R(771,549,241,48),.printAtlas,"印制全港邮路图",style:.dark)
        button(R(771,612,241,36),.home,"返回航局",style:.clear,fontSize:14)
    }
}
