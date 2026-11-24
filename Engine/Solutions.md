# 雾信航局 · 参考航线

此页含全部关卡解法。每栏记一轮航行，栏与栏之间执行一次「留影返航」。N、E、S、W 分别表示向北、东、南、西移动一格。点号表示「候一拍」。

| 航线 | 第一轮 | 第二轮 | 第三轮 | 单轮潮限 | 最短总拍 |
| --- | --- | --- | --- | ---: | ---: |
| 01　晨盐渡 | `EESEENEE` | — | — | 14 | 8 |
| 02　哑钟浮台 | `EEN` | `EEEEEE` | — | 10 | 9 |
| 03　退潮书摊 | `SSE` | `EEEEESEWNNE` | — | 16 | 14 |
| 04　慢半拍的桥 | `NNE` | `E.EE` | — | 4 | 7 |
| 05　苔井邮铺 | `EESSEWNNWNNNEEESEEESSE` | — | — | 30 | 22 |
| 06　候鸟台 | `NEEEEE` | `SEEEEEEE` | — | 12 | 14 |
| 07　双门船坞 | `EEENNN` | `EEESSS` | `EEE..EEEEE` | 11 | 22 |
| 08　雨琴渠 | `EEN` | `EEEEENNE` | `EEEEES.EEE` | 13 | 21 |
| 09　旋灯窄巷 | `NEEEE.WW` | `SEEESEEEESEE` | — | 15 | 20 |
| 10　钟腹长堤 | `NNEEEEE` | `EE.EEEE` | `SSEEEEEEEEE` | 13 | 25 |
| 11　旧址换印 | `NNE......EEEEN` | `EESSEEWWNNE..EEESSNNEE` | — | 24 | 36 |
| 12　灯塔回函 | `WWNNNNNWESSSS` | `NNNNNN` | `EENNNNEEENNWNN` | 18 | 33 |

最短总拍计算所有航迹中的移动与候拍，留影返航本身不耗拍。抵达末格后，船影会停留，无需额外录入候拍。

在此目录运行 `./Tests/verify.sh --optimal` 可以重新验证每条航线、最少船影数与最短总拍。运行 `./Tests/verify.sh --charts 4096` 可对指定数量的外海航图进行离线抽验。
