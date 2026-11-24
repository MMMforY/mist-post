import AppKit

extension StationView {
    // Positions are registered to the twelve landmarks in the printed atlas.
    static let portPins: [CGPoint] = [
        .init(x:0.132,y:0.689),.init(x:0.064,y:0.845),.init(x:0.228,y:0.858),.init(x:0.323,y:0.648),
        .init(x:0.374,y:0.488),.init(x:0.658,y:0.543),.init(x:0.516,y:0.368),.init(x:0.261,y:0.299),
        .init(x:0.652,y:0.100),.init(x:0.763,y:0.187),.init(x:0.875,y:0.634),.init(x:0.926,y:0.319)
    ]
    func atlasPoint(_ id: Int, rect: CGRect) -> CGPoint {
        let pt = Self.portPins[id-1]
        return .init(x:rect.minX+pt.x*rect.width,y:rect.minY+pt.y*rect.height)
    }
    func atlasImage(in rect: CGRect) {
        guard let atlasImage else { P.rect(rect,P.deep); return }
        atlasImage.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,
                        hints:[.interpolation:NSImageInterpolation.high])
    }
    func drawRouteAtlas() {
        let all = MistCampaign.levels
        let level = all.first(where:{ $0.id == selectedPort }) ?? all[0]
        let delivered = store.profile.records[level.id] != nil
        let unlocked = store.unlocked(level.id)
        P.rect(R(0,0,1200,750),P.paper)
        masthead()
        P.text("沿海邮路   /   COASTAL ATLAS",R(33,87,787,22),P.mono(12,.semibold),P.teal,kern:1)
        P.text("群岛航路簿",R(29,111,660,55),P.serif(38,heavy:true),P.graphite)
        P.text(String(format:"%02d / %02d  已投递",store.profile.records.count,all.count),
               R(820,117,344,36),P.mono(17,.semibold),P.teal,align:.right,centerY:true)
        let map = R(30,177,797,491)
        atlasImage(in:map)
        P.rect(map,P.night.withAlphaComponent(0.155))
        P.frame(map,P.graphite,2)
        P.frame(map.insetBy(dx:6,dy:6),P.cream.withAlphaComponent(0.65),1)
        // A dotted sailing itinerary links the landmarks. The selected ticket
        // stays beside the map so it never covers a neighboring port.
        for id in 2...all.count {
            let a = atlasPoint(id-1,rect:map), b = atlasPoint(id,rect:map)
            let delta = CGPoint(x:b.x-a.x,y:b.y-a.y)
            let mid = CGPoint(x:(a.x+b.x)/2+delta.y*0.13,y:(a.y+b.y)/2-delta.x*0.13)
            let path = NSBezierPath()
            path.move(to:a)
            path.curve(to:b,controlPoint1:mid,controlPoint2:mid)
            path.lineWidth = 4.2
            P.night.withAlphaComponent(0.53).setStroke()
            path.stroke()
            path.lineWidth = 1.8
            path.setLineDash([4,3],count:2,phase:0)
            (store.unlocked(id) ? P.ochre : P.cream.withAlphaComponent(0.7)).setStroke()
            path.stroke()
        }
        for l in all {
            let pos = atlasPoint(l.id,rect:map)
            let active = level.id == l.id
            let done = store.profile.records[l.id] != nil
            let radius:CGFloat = active ? 18 : 15
            let r = R(pos.x-radius,pos.y-radius,2*radius,2*radius)
            let available = store.unlocked(l.id)
            let fill = active ? P.ochre : done ? P.paper : available ? P.cream : P.deep
            P.ellipse(r.offsetBy(dx:1,dy:2),fill:P.night.withAlphaComponent(0.65))
            P.ellipse(r,fill:fill,stroke:P.night,width:2.4)
            if active { P.ellipse(r.insetBy(dx:-4,dy:-4),stroke:P.ochre,width:1.8) }
            P.text(String(format:"%02d",l.id),r,P.mono(active ? 16 : 13,.bold),
                   active || done || available ? P.night : P.cream,align:.center,centerY:true)
            let hit = r.insetBy(dx:-4,dy:-4)
            target(hit,.port(l.id),"第 \(l.id) 港 "+l.title+"，"+(done ? "已投递" : available ? "可启航" : "待解锁"))
        }
        let x:CGFloat = 850, w:CGFloat = 320
        P.rect(R(x,177,w,491),P.ink(0xf6efdc))
        P.frame(R(x,177,w,491),P.rule)
        P.text(String(format:"PORT %02d",level.id),R(x+20,195,145,25),P.mono(13,.bold),P.teal,kern:1)
        P.text(level.district,R(x+130,193,169,27),P.sans(15,.semibold),P.gray,align:.right)
        P.rule(x+19,233,w-38,P.rule)
        stamp(id:level.id,in:R(x+88,249,144,149),paper:P.ink(0xd8c9a9),title:level.postmark)
        P.text(level.title,R(x+12,417,w-24,48),P.serif(29,heavy:true),P.graphite,align:.center)
        P.text("收信人   "+level.recipient,R(x+12,470,w-24,30),P.sans(16),P.gray,align:.center)
        P.rule(x+20,520,w-40,P.rule)
        let info: String
        if let score = store.profile.records[level.id] {
            info = score == level.par ? "已获准点邮戳   ·   最短 \(score) 拍" : "已送达   ·   最佳 \(score) 拍"
        } else if unlocked { info = "\(level.echoLimit) 艘船影   ·   每潮 \(level.turnLimit) 拍" }
        else { info = "完成第 \(level.id-1) 条航路后开启" }
        P.text(info,R(x+12,539,w-24,25),P.sans(14,.semibold),P.teal,align:.center)
        let label = delivered ? "再次启航  →" : (store.profile.journeys[level.id]?.isEmpty == false ? "继续航行  →" : "启航送信  →")
        button(R(x+20,595,w-40,49),.route(level.id),unlocked ? label : "尚待解锁",style:unlocked ? .selected : .paper,enabled:unlocked,fontSize:17)
        button(R(30,689,121,36),.back,"←  返回",fontSize:14)
        P.text("选取图中港口查看航件",R(168,693,416,27),P.sans(14),P.gray)
        button(R(600,689,225,36),.studio(.editor),"进入制图室  ↗",style:.selected,fontSize:14)
        button(R(854,689,145,36),.port(max(1,level.id-1)),"←  前一港",enabled:level.id>1,fontSize:14)
        button(R(1010,689,160,36),.port(min(all.count,level.id+1)),"后一港  →",enabled:level.id<all.count,fontSize:14)
    }
}
