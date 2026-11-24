import AppKit

enum LessonAction: Hashable { case open, previous, next, back }

struct BellLesson {
    static let level = MistLevel(id:-2,title:"港内演习",district:"实习水道",sender:"领航员",recipient:"实习灯塔",
                                postmark:"铃",letter:"演练完成。",briefing:"用一艘船影打开水闸。",
                                rows:["##a##","S..AH","#####"],echoLimit:1,turnLimit:5,routes:["EEN","EEEE"])
    var game = MistVoyage(level:Self.level)
    var count: Int { game.history.count }
    var caption: String {
        switch count {
        case 0: return "先走去摸一摸那只铃。第一程的目标是上方的一号铃标。"
        case 1: return "再向东一格，进入铃标下方的水道。"
        case 2: return "向北驶上铃标。你要把这一程留给下一轮潮汐。"
        case 3: return "邮船已经就位。按「留影返航」，把刚才的三拍录成船影。"
        case 4: return "第二程开始。你和船影同时出港，各自走自己的路线。"
        case 5: return "再向东航行。船影即将转向铃标，你则准备穿过水闸。"
        case 6: return "下一拍，船影抵达铃标。现在向东划，就能同时驶入打开的闸口。"
        case 7: return "船影停在铃标上，水闸继续敞开。再向东驶入收信灯塔。"
        default: return "信已送达。你用两趟不同的航线完成了一次投递。"
        }
    }
    var nextLabel: String {
        guard count < Self.level.guide.count else { return "返回手册" }
        switch Self.level.guide[count] {
        case .record: return "留影返航  ↶"
        case .move(let m): return "向"+m.direction+"航行  →"
        }
    }
}

extension StationView {
    func lessonAction(_ action: LessonAction) {
        switch action {
        case .open:
            lesson = BellLesson()
            drawer = .lesson
        case .previous: _ = lesson?.game.undo()
        case .next:
            guard var exercise = lesson else { return }
            guard exercise.count < BellLesson.level.guide.count else {
                lessonAction(.back)
                return
            }
            let cmd = BellLesson.level.guide[exercise.count]
            _ = exercise.game.perform(cmd)
            lesson = exercise
            switch cmd {
            case .record: audio.play(.rewind)
            case .move: audio.play(exercise.game.delivered ? .delivered : .move)
            }
        case .back: lesson = nil; drawer = .guide(1)
        }
        resetFocus()
        if drawer == .lesson, let lesson { announce(lesson.caption) }
    }
    func drawLesson() {
        guard let lesson else { return }
        let game = lesson.game
        let field = R(277,210,415,237)
        var opts = ChartOptions()
        opts.reduceMotion = true
        opts.showTrails = true
        opts.highContrast = store.profile.contrast
        chart.draw(in:field,game:game,time:0,options:opts)
        P.frame(field,P.graphite,1.2)
        P.text(game.echoes.isEmpty ? "第一程" : "第二程",R(718,223,195,48),P.serif(29,heavy:true),P.graphite)
        P.text(game.echoes.isEmpty ? "把船影留在铃上" : "让船影替你开闸",R(719,286,205,55),P.sans(18,.semibold),P.teal,wrap:true)
        P.rule(719,355,193,P.rule)
        P.text("潮拍  \(game.beat)",R(719,375,191,33),P.sans(16),P.graphite)
        P.text("船影  \(game.echoes.count) 艘",R(719,414,191,31),P.sans(16),P.graphite)
        P.text(lesson.caption,R(280,466,639,68),P.serif(19),P.graphite,wrap:true,spacing:4)
        P.rule(276,546,648,P.rule)
        button(R(277,569,124,39),.lesson(.previous),"←  退一步",enabled:lesson.count>0)
        P.text("\(lesson.count) / \(BellLesson.level.guide.count)",R(441,575,172,27),P.mono(15,.medium),P.gray,align:.center)
        button(R(697,569,226,39),.lesson(.next),lesson.nextLabel,style:.selected)
    }
}
