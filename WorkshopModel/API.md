# 自绘航图

`MistWorkshopSize.small`、`.medium`、`.large` 分别为 7×5、9×7、11×9，提供 `width`、`height` 和 `allCases`。坐标使用 `MistPoint`，从左上角起算。

## 绘图

`MistWorkshopDraft(size: .small)` 创建带出发港和收信灯塔的空白水域。`MistWorkshopDraft(chart: chart)` 从已验证的成图开始编辑。读取 `size, title, author, letter, echoLimit, turnLimit, rows, canUndo` 或 `tile(at:)` 展示状态。

- `paint(_ tile: MistTile, at: MistPoint) throws -> Bool` 绘制一格。出发港和收信灯塔画笔会移动对应港口。将其画在另一港口上会交换两者。普通画笔覆写港口时返回本地化提示。
- 水道和陆岸画笔使用 `beginTerrainStroke(_ tile:)`、`extendTerrainStroke(to:)` 和 `endTerrainStroke()`。连续采样点间会补齐上下左右相接的格子，保留途经的港口。指针移出画布时传入 `nil`，再次进入后从新位置续画。整笔只产生一次撤回，即使在绘制途中保存草图也可恢复。
- `configure(title: String? = nil, author: String? = nil, letter: String? = nil, echoLimit: Int? = nil, turnLimit: Int? = nil) throws -> Bool` 一次提交一组设置。标题上限 28 字，署名上限 20 字，信件上限 160 字。船影名额为 0–2，潮限为 5–48 拍。
- `resize(_ size: MistWorkshopSize) -> Bool` 保留左上角相交区域，将越界的港口移到新边界附近。裁掉的内容可由一次撤回取回。
- `undo() -> Bool` 撤回最近一次已生效的操作。至多保留 32 次。重复绘制同一格和失败操作不会增加撤回记录。
- `trialLevel() -> MistLevel` 提供试航关卡。编辑状态下的试航使用空参考航迹，试航界面应隐藏参考总拍与领航提示。
- `encodedDraft() throws -> Data` 和 `MistWorkshopDraft.restoreDraft(_ data: Data) throws -> MistWorkshopDraft` 用于本机续编，包含撤回历史。若旧撤回记录损坏，恢复当前有效草图和最近连续有效的历史。

## 封存与打开

`draft.seal(proof: voyage.history) throws -> MistWorkshopChart` 逐步重放试航，送达收信灯塔后生成成图。`chart.level` 是编号为 −1 的可玩关卡。其参考拍数来自作者交付的航迹，`chart.fingerprint` 是规范化内容与参考航迹的 SHA-256 十六进制摘要。

`chart.encoded() throws -> Data` 产生版本 1 的 UTF-8 JSON。`MistWorkshopChart.open(_ data: Data) throws -> MistWorkshopChart` 验证文件格式、内容和航迹后返回可玩成图。读写磁盘和原子替换由界面层负责，扩展名为 `.mistchart`。只要对当前成图建立新的草图，原成图就能继续作为独立的已验证版本使用。

所有模型错误都遵循 `LocalizedError`，可直接显示 `error.localizedDescription`。
