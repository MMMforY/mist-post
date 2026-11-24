import AppKit

extension StationView {
    func drawChartRoom() {
        let s = studio
        P.rect(R(0,0,1200,750),P.paper)
        masthead()
        P.text("航图工务  /  CARTOGRAPHY",R(31,83,640,22),P.mono(12,.semibold),P.teal,kern:1)
        P.text("制图室",R(28,108,292,47),P.serif(37,heavy:true),P.graphite)
        P.text(s.draft.title,R(292,113,520,40),P.serif(22),P.teal,align:.right,centerY:true)
        button(R(861,101,139,40),.studio(.configure),"编辑航单")
        button(R(1012,101,155,40),.studio(.shelf),"海图匣  ↗")
        let field = draftingRect
        var opts = ChartOptions()
        opts.reduceMotion = true
        opts.highContrast = store.profile.contrast
        opts.showTrails = false
        chart.draw(in:field,game:s.paper,time:0,options:opts)
        let level = s.paper.level
        let first = chart.center(of:.init(x:0,y:0),in:field,game:s.paper)
        let next = chart.center(of:.init(x:1,y:1),in:field,game:s.paper)
        let dx = next.x-first.x, dy = next.y-first.y
        let left = first.x-dx/2, top = first.y-dy/2
        for i in 0...level.width {
            let xx = left+CGFloat(i)*dx
            P.line([.init(x:xx,y:top),.init(x:xx,y:top+dy*CGFloat(level.height))],P.cream.withAlphaComponent(0.29),0.8,dash:[2,4])
        }
        for i in 0...level.height {
            let yy = top+CGFloat(i)*dy
            P.line([.init(x:left,y:yy),.init(x:left+dx*CGFloat(level.width),y:yy)],P.cream.withAlphaComponent(0.29),0.8,dash:[2,4])
        }
        let hoverCell = hover.flatMap { chart.cell(at:$0,in:field,game:s.paper) }
        if let p = hoverCell ?? s.cursor {
            let at = chart.center(of:p,in:field,game:s.paper)
            P.frame(R(at.x-dx/2+2,at.y-dy/2+2,dx-4,dy-4),P.ochre,2.2)
        }
        P.frame(field,P.graphite,1.5)
        let x:CGFloat = 839
        P.rect(R(x,161,329,439),P.ink(0xf6efdc))
        P.frame(R(x,161,329,439),P.rule)
        P.text("绘图工具",R(x+18,177,192,37),P.serif(22,heavy:true),P.graphite)
        P.text(s.brush.label,R(x+193,183,116,25),P.sans(14,.semibold),P.teal,align:.right)
        P.rule(x+17,222,295,P.rule)
        for (i,brush) in CoastBrush.allCases.enumerated() {
            let r = R(x+16+CGFloat(i%4)*75,236+CGFloat(i/4)*78,69,70)
            let selected = brush == s.brush
            P.rect(r,selected ? P.deep : (hoverOn(r) ? P.cream : P.ink(0xe4dfc9)))
            P.frame(r,selected ? P.teal : P.rule)
            chart.drawKey(brush.tile,in:R(r.midX-20,r.minY+2,40,40))
            P.text(brush.label,R(r.minX,r.maxY-25,r.width,22),P.sans(13,.semibold),selected ? P.cream : P.graphite,align:.center)
            target(r,.studio(.brush(brush)),"画笔 "+brush.label+(selected ? "，已选" : ""))
        }
        P.rule(x+17,477,295,P.rule)
        P.text("每潮  \(level.turnLimit) 拍",R(x+18,494,152,27),P.sans(15,.medium),P.teal)
        P.text("船影  \(level.echoLimit) 艘",R(x+166,494,144,27),P.sans(15,.medium),P.teal,align:.right)
        P.text("亲自试航并送达信件后，即可封存和导出海图。",R(x+18,541,292,52),P.sans(15),P.gray,wrap:true)
        P.text(s.message.isEmpty ? "点击海图落笔。水道、陆岸可拖动画线；方向键移光标，空格落笔。" : s.message,
               R(32,617,785,55),P.sans(15,.medium),s.message.isEmpty ? P.gray : P.brick,wrap:true)
        button(R(30,683,130,39),.back,"←  航路簿",fontSize:14)
        button(R(172,683,161,39),.studio(.undo),"撤回编辑",key:"Z",enabled:s.draft.canUndo,fontSize:14)
        button(R(346,683,149,39),.studio(.newSheet),"新建草图",fontSize:14)
        button(R(850,632,318,57),.studio(.trial),s.authorRoute.isEmpty ? "下水试航  →" : "继续试航  →",style:.selected,fontSize:18)
    }
    func drawChartCase() {
        let s = studio, keys = s.sortedKeys
        let key = s.selection, selected = key.flatMap { s.volumes[$0] }
        P.rect(R(0,0,1200,750),P.paper)
        masthead()
        P.text("自绘海图  /  CHART ARCHIVE",R(44,89,780,22),P.mono(13,.semibold),P.teal,kern:1)
        P.text("海图匣",R(40,126,700,65),P.serif(45,heavy:true),P.graphite)
        P.text("这里收存你亲自走通的航线，也能打开其他航员制作的海图。",R(44,196,1048,32),P.sans(17),P.gray)
        P.rule(43,243,1115,P.rule)
        button(R(44,265,175,43),studio.fromAfterpost ? .back : .studio(.editor),studio.fromAfterpost ? "←  港民来图" : "返回制图室",style:.selected)
        button(R(234,265,177,43),.studio(.importChart),"打开海图文件…")
        button(R(427,265,177,43),.studio(.sample),"打开示范海图")
        P.text("\(keys.count) 张成图",R(785,273,369,28),P.sans(15,.semibold),P.teal,align:.right)
        let start = min(max(0,s.page*5),max(0,keys.count-1))
        if keys.isEmpty {
            P.rect(R(45,338,1111,222),P.ink(0xf6efdc))
            P.frame(R(45,338,1111,222),P.rule)
            P.mark(R(89,395,105,78),P.teal)
            P.text("等待第一张海图",R(230,383,835,55),P.serif(30,heavy:true),P.graphite)
            P.text("在制图室画好港口与水道，送达一次便能留下带航迹的成图。",R(231,457,839,50),P.sans(18),P.gray,wrap:true)
        } else {
            for (i,k) in keys.dropFirst(start).prefix(5).enumerated() {
                guard let c = s.volumes[k] else { continue }
                let row = R(45,338+CGFloat(i)*60,599,52)
                P.rect(row,k == key ? P.deep : (hoverOn(row) ? P.cream : P.ink(0xf6efdc)))
                P.frame(row,P.rule)
                let ink = k == key ? P.cream : P.graphite
                P.text(c.level.title,R(row.minX+13,row.minY+2,394,row.height-4),P.serif(20,heavy:true),ink,centerY:true)
                P.text(c.level.sender,R(row.minX+405,row.minY+2,178,row.height-4),P.sans(13),ink,align:.right,centerY:true)
                target(row,.studio(.select(k)),c.level.title+"，"+c.level.sender)
            }
            if let selected {
                let l = selected.level
                P.rect(R(668,338,488,290),P.ink(0xf6efdc)); P.frame(R(668,338,488,290),P.rule)
                P.text(l.title,R(690,363,444,48),P.serif(28,heavy:true),P.graphite)
                P.text("绘图  "+l.sender,R(692,423,437,29),P.sans(16),P.gray)
                P.rule(691,468,439,P.rule)
                P.text("\(l.width) × \(l.height) 海图    船影 \(l.echoLimit) 艘    试航 \(l.par) 拍",
                       R(692,481,436,32),P.sans(15,.semibold),P.teal)
                button(R(691,527,438,42),.studio(.launch),"驶入这张海图  →",style:.selected)
                button(R(691,580,208,33),.studio(.remix),"改绘副本",fontSize:14)
                button(R(912,580,217,33),.studio(.export),"导出海图文件",fontSize:14)
            }
        }
        if keys.count > 5 {
            button(R(46,650,112,34),.studio(.turnPage(s.page-1)),"←  上页",enabled:s.page>0,fontSize:13)
            button(R(170,650,112,34),.studio(.turnPage(s.page+1)),"下页  →",enabled:(s.page+1)*5 < keys.count,fontSize:13)
        }
        P.text(s.message,R(45,699,1108,30),P.sans(15),P.brick)
    }
    func drawStudioReceipt() {
        guard let c = studio.active else { return }
        P.rect(R(0,0,1200,750),P.deep)
        masthead()
        let r = R(123,114,954,475)
        P.rect(r,P.paper)
        P.frame(r.insetBy(dx:8,dy:8),P.rule)
        P.text(studio.authoring ? "海图验航通过" : "邮船已抵达",R(160,144,740,60),P.serif(38,heavy:true),P.graphite)
        P.text(c.level.title+"   /   "+c.level.sender,R(163,226,785,37),P.serif(21),P.teal)
        P.rule(161,279,878,P.rule)
        P.text(c.level.letter,R(163,307,665,168),P.serif(c.level.letter.count > 95 ? 18 : 21),P.graphite,wrap:true,spacing:5)
        postmark(R(862,306,130,130),name:"验航",id:1,color:P.brick)
        P.rule(160,486,878,P.rule)
        P.text("本次总拍  \(voyage.totalBeats)     作者航程  \(c.level.par) 拍",R(164,512,735,35),P.sans(17,.semibold),P.teal)
        button(R(124,625,197,46),.studio(.export),"保存海图文件…",style:.dark)
        button(R(338,625,163,46),.studio(.replay),"回看航程",style:.dark)
        button(R(847,625,229,46),.studio(.shelf),"返回海图匣  →",style:.primary)
        P.text(studio.message,R(126,691,950,31),P.sans(14),P.cream)
    }
}
