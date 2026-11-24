import Foundation

enum MistCampaign {
    static let levels = [
        MistLevel(id: 1, title: "晨盐渡", district: "盐风外港", sender: "盐田阿桂", recipient: "早班渡工",
                  postmark: "盐晶", letter: "我把第一锅盐留了一小罐，盖子还是拧得紧。你从栈桥过来时顺路取，粥已经温在小炉上。",
                  briefing: "绕过浅滩，把第一封信送到收信灯塔。",
                  rows: [
                    "##...##",
                    "#..#..#",
                    "S..#..H",
                    "#.....#",
                    "###.###"
                  ], echoLimit: 0, turnLimit: 14, routes: ["EESEENEE"]),
        MistLevel(id: 2, title: "哑钟浮台", district: "盐风外港", sender: "早班渡工", recipient: "浮台修钟人",
                  postmark: "海钟", letter: "钟舌找到了，原来滚进了我那只破筐。今晚请再敲一遍。码头的人都说，看不见灯也认得你的钟声。",
                  briefing: "驶上一号铃标，留影返航。船影会替下一轮的你鸣钟开闸。",
                  rows: [
                    "###.###",
                    "##a..##",
                    "S...A.H",
                    "##..#..",
                    "###.###"
                  ], echoLimit: 1, turnLimit: 10, routes: ["EEN", "EEEEEE"]),
        MistLevel(id: 3, title: "退潮书摊", district: "盐风外港", sender: "阿汐", recipient: "书摊婆婆",
                  postmark: "书页", letter: "借你的书，最后一页粘着一根小羽毛。我怕拿掉会忘记读到哪，就连同还书的邮戳一起留给你。",
                  briefing: "请船影开启一号水闸。在收信前，到南边的邮戳站盖戳。",
                  rows: [
                    "##.##..",
                    "#..#..H",
                    "S..A..#",
                    ".#.#..*",
                    ".a.#...",
                    "##.##.."
                  ], echoLimit: 1, turnLimit: 16, routes: ["SSE", "EEEEESEWNNE"]),
        MistLevel(id: 4, title: "慢半拍的桥", district: "盐风外港", sender: "桥上抄表员", recipient: "对岸小乐队",
                  postmark: "潮桥", letter: "昨天我听清了。你们敲两下，我在第三拍抬桥。那段空白最好听，像有人在雾里轻轻吸了一口气。",
                  briefing: "这轮潮汐只有四拍。选择「候一拍」，让邮船和船影同时抵达水闸与铃标。",
                  rows: [
                    "##..###",
                    "##.a###",
                    "##.##.#",
                    "..S.AH.",
                    ".##.##.",
                    "....###"
                  ], echoLimit: 1, turnLimit: 4, routes: ["NNE", "E.EE"]),
        MistLevel(id: 5, title: "苔井邮铺", district: "鸣沙内湾", sender: "苔井掌柜", recipient: "小岛学堂",
                  postmark: "井纹", letter: "孩子们寄来的两张拓印都收到了。把井沿和屋檐拼在一起，恰好是我们那条老街下雨时的模样。",
                  briefing: "北岸和南岸各有一枚中转戳。找一条把它们串起来的水路。",
                  rows: [
                    "#*...##..",
                    "..##.....",
                    "#.##.##.#",
                    "S....#..H",
                    "##.#....#",
                    "#..*##..#"
                  ], echoLimit: 0, turnLimit: 30, routes: ["EESSEWNNWNNNEEESEEESSE"]),
        MistLevel(id: 6, title: "候鸟台", district: "鸣沙内湾", sender: "候鸟台记录员", recipient: "浮台修钟人",
                  postmark: "迁燕", letter: "头燕落在第一根桩上时，尾燕才过第二座闸。我把那段距离记成了三声钟。明年春天，我们再一起数。",
                  briefing: "一艘船影要依次敲响两只铃标。先走上水道，再沿下水道与它并航。",
                  rows: [
                    "##...####",
                    "..a..b..#",
                    "S########",
                    "..A..B.H#",
                    "##..##.##"
                  ], echoLimit: 1, turnLimit: 12, routes: ["NEEEEE", "SEEEEEEE"]),
        MistLevel(id: 7, title: "双门船坞", district: "鸣沙内湾", sender: "船匠林姐", recipient: "北坞、南坞",
                  postmark: "船肋", letter: "新船的两根肋木，一根来自北坞，一根来自南坞。等你们的铃都响了，我就撤下垫木，让她第一次见水。",
                  briefing: "两只铃标相隔甚远。分别留影返航，让两艘船影守住双门。",
                  rows: [
                    "###a.####",
                    "##...####",
                    "##..#####",
                    "S...AB..H",
                    "##..#####",
                    "##...####",
                    "###b.####"
                  ], echoLimit: 2, turnLimit: 11, routes: ["EEENNN", "EEESSS", "EEE..EEEEE"]),
        MistLevel(id: 8, title: "雨琴渠", district: "鸣沙内湾", sender: "浮台修钟人", recipient: "雨琴看闸人",
                  postmark: "雨弦", letter: "修钟剩下一截铜丝，我绕了三圈放在信封里。把它系在集雨斗下次再听，第一滴或许就是你缺的那个音。",
                  briefing: "二号铃标藏在一号水闸之后。让第一艘船影送第二艘进内渠。",
                  rows: [
                    "##.##.b##",
                    "#.a#...##",
                    "S..A..#..",
                    "##.#..B.H",
                    "#..##.###"
                  ], echoLimit: 2, turnLimit: 13, routes: ["EEN", "EEEEENNE", "EEEEES.EEE"]),
        MistLevel(id: 9, title: "旋灯窄巷", district: "远灯群岛", sender: "窄巷点灯人", recipient: "旧巷住户",
                  postmark: "风灯", letter: "我把灯罩转了一圈。先照井口，再照窗口，最后照回井口。你小时候画在墙上的小船，还泊在原处。",
                  briefing: "两道一号水闸共用同一只铃标。船影敲过二号钟后，还要折回。",
                  rows: [
                    "##...#####",
                    "..a.b.####",
                    "S#########",
                    "..A.######",
                    "###.B.*.##",
                    "#######A.H"
                  ], echoLimit: 1, turnLimit: 15, routes: ["NEEEE.WW", "SEEESEEEESEE"]),
        MistLevel(id: 10, title: "钟腹长堤", district: "远灯群岛", sender: "长堤守潮员", recipient: "试航班",
                  postmark: "钟摆", letter: "我坐进旧铜钟的肚子，里面听得到三条水道。最远处那一声很轻。你们试航的船到了，我就能认出来。",
                  briefing: "三条水道共用一个时钟。一号铃标会同时打开中渠和下渠的闸门。",
                  rows: [
                    "##...#####",
                    "..a..c..##",
                    ".#########",
                    "S..A..b###",
                    ".#########",
                    "..A..C.B.H",
                    "###..##..#"
                  ], echoLimit: 2, turnLimit: 13, routes: ["NNEEEEE", "EE.EEEE", "SSEEEEEEEEE"]),
        MistLevel(id: 11, title: "旧址换印", district: "远灯群岛", sender: "新邮铺阿汐", recipient: "老邮铺前辈",
                  postmark: "双印", letter: "我从旧址的抽屉里找到了老印章。新旧两枚并排盖下去，左边是你刻歪的屋脊，右边是我刻歪的烟囱。",
                  briefing: "进出旧邮铺都要过一号水闸。留足盖戳往返的节拍，再让船影转向二号钟。",
                  rows: [
                    "###..b..##",
                    ".a....####",
                    ".#########",
                    "S...B...H#",
                    "##A###.###",
                    "##..*#*..#",
                    "###..###.#"
                  ], echoLimit: 1, turnLimit: 24, routes: ["NNE......EEEEN", "EESSEEWWNNE..EEESSNNEE"]),
        MistLevel(id: 12, title: "灯塔回函", district: "远灯群岛", sender: "远灯守塔人", recipient: "雾信航局",
                  postmark: "灯塔", letter: "今晚雾最浓的时候，十二枚邮戳在桌上排成了岸线。谢谢你把这些平常话送过海来。我已点灯，换你回家。",
                  briefing: "最后一袋信要盖齐两枚中转戳。请留心西渠的两只铃标，以及灯塔前的最后一道闸。",
                  rows: [
                    "###..####H#",
                    "#...#####A#",
                    "#...#b###.*",
                    "#.c.#.####.",
                    "#.#.#.#B.C.",
                    "#...#A#*###",
                    "##..#.#.###",
                    "#..a#.#..##",
                    "###..S...##"
                  ], echoLimit: 2, turnLimit: 18, routes: ["WWNNNNNWESSSS",
                                                          "NNNNNN", "EENNNNEEENNWNN"])
    ]
}
