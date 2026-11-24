import AppKit

extension StationView {
    func drawDrawer(_ sheet: Drawer) {
        renderingDrawer = true
        defer { renderingDrawer = false }
        P.rect(R(0,0,1200,750),P.night.withAlphaComponent(0.83))
        let box = R(239,104,722,540)
        P.rect(box.offsetBy(dx:6,dy:8),P.night)
        P.rect(box,P.paper)
        P.frame(box.insetBy(dx:6,dy:6),P.rule)
        let section: String
        switch sheet { case .afterpost: section = "港民来图"; case .lesson: section = "港内演练"; case .guide: section = "航员手册"; case .preferences: section = "航舱设置"; case .restart: section = "重新出航" }
        P.text(section,R(274,128,497,55),P.serif(35,heavy:true),P.graphite)
        button(R(838,132,86,34),.dismiss,"关闭  ×",fontSize:13)
        P.rule(276,190,648,P.rule)
        switch sheet {
        case .afterpost:
            P.text("三位老寄件人送来了亲手绘制的航线。选一张收入海图匣，即可启航。",R(278,212,644,49),P.serif(18),P.graphite,wrap:true)
            for (index, chart) in afterpost.enumerated() {
                let y = 277+CGFloat(index)*99
                let row = R(277,y,646,84)
                P.rect(row,hoverOn(row) ? P.cream : P.ink(0xf1e8d4))
                P.frame(row,P.rule)
                stamp(id:[1,5,9][index],in:R(291,y+10,55,63),paper:P.pale,title:chart.level.postmark)
                P.text(chart.level.title,R(365,y+10,392,34),P.serif(22,heavy:true),P.graphite)
                P.text(chart.level.sender+"  ·  船影上限 "+String(chart.level.echoLimit),R(367,y+47,444,27),P.sans(14),P.teal)
                P.text("收图  →",R(813,y+25,92,34),P.sans(15,.semibold),P.teal,align:.right)
                target(row,.studio(.takeMail(index)),"收取"+chart.level.sender+"的海图《"+chart.level.title+"》")
            }
        case .lesson: drawLesson()
        case .guide(let page):
            let titles = ["航行与投递","把昨天的船留在海上","读懂下一拍"]
            P.text(String(format:"0%d   /   ",page+1)+titles[page],R(277,211,637,43),P.serif(24,heavy:true),P.graphite)
            switch page {
            case 0:
                let items: [(MistTile,String,String)] = [
                    (.origin,"出发港","邮船载信出港，方向键或 WASD 每次航行一格。"),
                    (.harbor,"收信灯塔","驶入灯塔完成投递。海图中带纹理的陆地无法通行。"),
                    (.stamp,"邮戳站","有邮戳任务时，本轮航线须经过全部邮戳站。")
                ]
                for (i,item) in items.enumerated() {
                    let y = 269 + CGFloat(i)*83
                    chart.drawKey(item.0,in:R(278,y,60,60))
                    P.text(item.1,R(358,y,550,28),P.serif(20,heavy:true),P.graphite)
                    P.text(item.2,R(358,y+32,543,49),P.sans(15),P.gray,wrap:true)
                }
            case 1:
                chart.drawKey(.buoy(0),in:R(281,267,87,87))
                P.arrow(R(389,302,43,12),color:P.teal)
                chart.drawKey(.gate(0),in:R(451,267,87,87))
                P.text("相同纹样组成一对铃标与水闸。",R(563,275,345,76),P.serif(19),P.graphite,wrap:true,centerY:true)
                let instructions = [
                    "先驶上铃标，按 E 留影返航。你的邮船将回到出发港。",
                    "上一程的船影会逐拍重走原路，到达末格后停留。",
                    "船影在铃标上的那一拍，你便能驶入对应的水闸。"
                ]
                for (i,s) in instructions.enumerated() {
                    let y = 379+CGFloat(i)*45
                    P.text(String(format:"%02d",i+1),R(283,y,40,33),P.mono(16,.bold),P.brick,centerY:true)
                    P.text(s,R(329,y,578,37),P.sans(16),P.graphite,wrap:true,centerY:true)
                }
            default:
                let rows = [
                    ("候潮","空格或点击船身，邮船原地等一拍，船影继续移动。"),
                    ("潮表","闸臂预告下一拍能否驶入。点选潮表可查看指定节拍。"),
                    ("撤回","按 Z 撤回上一步。刚刚留影时，也可以撤回到上一程。"),
                    ("领航","按 H 获取当前局面的一步提示。重航可从头规划。")
                ]
                for (i,row) in rows.enumerated() {
                    let y = 270+CGFloat(i)*62
                    P.text(row.0,R(281,y,74,38),P.serif(20,heavy:true),P.teal,centerY:true)
                    P.text(row.1,R(366,y,546,51),P.sans(16),P.graphite,wrap:true,centerY:true)
                    if i < 3 { P.rule(282,y+51,629,P.rule.withAlphaComponent(0.45)) }
                }
            }
            P.rule(276,546,648,P.rule)
            button(R(277,568,119,38),.guidePage(max(0,page-1)),"←  上一页",enabled:page>0)
            if page == 1 {
                button(R(483,568,180,38),.lesson(.open),"上船演练  ↗",style:.selected,fontSize:15)
            } else {
                P.text("\(page+1)  /  3",R(497,574,206,25),P.mono(15,.medium),P.gray,align:.center)
            }
            button(R(792,568,132,38),page==2 ? .dismiss : .guidePage(page+1),page==2 ? "收起手册" : "下一页  →",style:.selected)
        case .preferences:
            let prefs = store.profile
            let items: [(String,String,Bool,DeskAction)] = [
                ("港湾声景","海潮、铃声与邮船的声音",prefs.soundOn,.sound),
                ("绘制航迹","在海图上显示本船与船影走过的路线",prefs.trails,.trails),
                ("高对比海图","加强陆岸、格线与航标的对比",prefs.contrast,.contrast),
                ("减少动态","静止水面与船身，保留逐拍位置变化",prefs.lowMotion,.motion)
            ]
            for (i,row) in items.enumerated() {
                let y = 213+CGFloat(i)*81
                P.text(row.0,R(280,y,396,29),P.serif(20,heavy:true),P.graphite)
                P.text(row.1,R(280,y+32,492,27),P.sans(14),P.gray)
                button(R(815,y+3,105,40),row.3,row.2 ? "已开启" : "已关闭",style:row.2 ? .selected : .paper)
                P.rule(279,y+66,642,P.rule)
            }
            button(R(280,559,147,42),.fullscreen,"切换全屏")
            button(R(776,559,145,42),.dismiss,"返回游戏",style:.selected)
        case .restart:
            P.text("从第一拍重新启航？",R(280,237,621,52),P.serif(28,heavy:true),P.graphite)
            P.text("本航线的船影和进行中的航程会清空。已送达的信件和最佳航程记录会保留。",R(282,315,608,134),P.sans(19),P.graphite,wrap:true,spacing:6)
            button(R(282,540,178,47),.dismiss,"继续这趟航行")
            button(R(736,540,184,47),.confirmRestart,"重新出航",style:.selected)
        }
    }
}
