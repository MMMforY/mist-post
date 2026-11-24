import AppKit
import ApplicationServices

/// Exercise the AppKit provider in a transparent window. The optional strict mode also
/// requires successful delivery of an AXPress from a separately launched system AX client.
@MainActor
enum StationAccessCheck {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private enum ServerResult: Sendable {
        case pressed, unavailable(String), failed(String)
    }

    /// Use a separate client process. With AX disabled, a process querying itself may
    /// receive an AXApplication as its own AXWindows entry. An external query returns
    /// kAXErrorAPIDisabled, distinguishing denied transport from a broken provider.
    private nonisolated static func pressThroughServer(title: String) -> ServerResult {
        let app = AXUIElementCreateApplication(getppid())
        AXUIElementSetMessagingTimeout(app, 2)
        func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
        }
        var fixture: AXUIElement?, windows: [AXUIElement] = []
        var lastError: AXError = .success
        let deadline = Date(timeIntervalSinceNow: 2)
        repeat {
            var listed: CFTypeRef?
            lastError = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &listed)
            if lastError == .apiDisabled { return .unavailable("system returned kAXErrorAPIDisabled (-25211) for the separate AX client") }
            windows = listed as? [AXUIElement] ?? []
            fixture = windows.first { element in
                [kAXIdentifierAttribute, kAXTitleAttribute].contains { attribute(element, $0) as? String == title }
            }
            if fixture == nil { Thread.sleep(forTimeInterval: 0.04) }
        } while fixture == nil && Date() < deadline
        guard let fixture else {
            return .failed("AX server did not vend fixture (AXWindows error \(lastError.rawValue), \(windows.count) entries)")
        }
        var pending = [fixture], examined = 0
        while let element = pending.popLast(), examined < 150 {
            examined += 1
            let labels = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attribute(element, $0) as? String }
            if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole, labels.contains("航员手册") {
                var names: CFArray?
                guard AXUIElementCopyActionNames(element, &names) == .success,
                      (names as? [String])?.contains(kAXPressAction) == true else { return .failed("AX guide button omitted AXPress") }
                let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                return result == .success ? .pressed : .failed("AX guide button press returned \(result.rawValue)")
            }
            pending += attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return .failed("AX server failed to find the guide among \(examined) elements")
    }

    private nonisolated static func runExternalClient(token: UUID) -> ServerResult {
        let child = Process(), pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.arguments = ["--qa", "--accessibility"]
        var environment = ProcessInfo.processInfo.environment
        environment["MIST_POST_AX_FIXTURE"] = token.uuidString
        child.environment = environment
        child.standardOutput = pipe
        do { try child.run() } catch { return .failed("Could not launch the AX test client: " + error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        switch child.terminationStatus {
        case 0: return .pressed
        case 77: return .unavailable(message)
        default: return .failed("AX client exited \(child.terminationStatus): " + message)
        }
    }

    /// Start at the application's published accessibility windows, as AppKit does when
    /// vending the AX tree, so this checks the hierarchy above the custom drawing view.
    private static func pressThroughProvider(window: NSWindow) throws {
        guard (NSApp.accessibilityWindows() ?? []).contains(where: { $0 as AnyObject === window }) else {
            throw Failure(description: "AppKit omitted the fixture from its accessibility windows")
        }
        var pending: [Any] = [window], examined = 0
        while let raw = pending.popLast(), examined < 150 {
            examined += 1
            guard let element = raw as? NSAccessibilityProtocol else { continue }
            if element.accessibilityRole() == .button && element.accessibilityLabel() == "航员手册" {
                guard element.isAccessibilityEnabled(), element.accessibilityPerformPress() else {
                    throw Failure(description: "AppKit provider rejected the guide press")
                }
                return
            }
            pending += element.accessibilityChildren() ?? []
        }
        throw Failure(description: "AppKit did not expose the guide among \(examined) window elements")
    }

    private static func checkWindow(_ window: NSWindow, view: StationView, paint: () -> Void) async throws {
        let before = window.frame.origin
        let token = UUID()
        let title = "Mist Post AX test " + token.uuidString
        window.title = title
        window.setAccessibilityIdentifier(title)
        window.alphaValue = 0
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.setFrameOrigin(NSPoint(x: -32_000, y: -32_000))
        window.orderBack(nil)
        defer { window.orderOut(nil); window.setFrameOrigin(before) }

        try pressThroughProvider(window: window)
        guard view.drawer == .guide(0) else { throw Failure(description: "AppKit press did not open the guide") }
        print("PASS AppKit application-to-window accessibility provider and guide press")
        paint()
        view.act(.dismiss)
        paint()
        // Suspend instead of nesting a run loop inside a main-queue operation. AppKit must
        // process the system server's requests on the main thread while the client waits.
        let result = await Task.detached(priority: .userInitiated) { runExternalClient(token: token) }.value
        switch result {
        case .pressed:
            guard view.drawer == .guide(0) else { throw Failure(description: "System AXPress did not open the guide") }
            print("PASS external AXUIElement window lookup and AXPress")
            paint()
            view.act(.dismiss)
        case .unavailable(let reason):
            if CommandLine.arguments.contains("--require-system-ax") { throw Failure(description: reason) }
            print("SKIP external AXUIElement transport: " + reason)
        case .failed(let reason):
            throw Failure(description: reason)
        }
    }

    static func run(resources: URL) async throws {
        if let raw = ProcessInfo.processInfo.environment["MIST_POST_AX_FIXTURE"], let token = UUID(uuidString: raw) {
            // Target only our immediate parent and its uniquely identified test window.
            switch pressThroughServer(title: "Mist Post AX test " + token.uuidString) {
            case .pressed: exit(0)
            case .unavailable(let reason): print(reason); exit(77)
            case .failed(let reason): print(reason); exit(1)
            }
        }
        let view = StationView(store: DispatchStore(file: nil), resources: resources)
        view.frozenTime = 20
        view.audio.setEnabled(false)
        let window = NSWindow(contentRect: NSRect(x: 73, y: 91, width: 960, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        let context = CGContext(data: nil, width: 960, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func paint() {
            NSGraphicsContext.saveGraphicsState()
            context.saveGState()
            context.translateBy(x: 0, y: 600)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            view.draw(view.bounds)
            context.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
        }
        func verify(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw Failure(description: message) }
        }
        func children() -> [NSAccessibilityElement] { view.accessibilityChildren() as? [NSAccessibilityElement] ?? [] }
        func node(_ prefix: String, deep: Bool = false) throws -> NSAccessibilityElement {
            var all = children()
            if deep { all += all.flatMap { $0.accessibilityChildren() as? [NSAccessibilityElement] ?? [] } }
            guard let found = all.first(where: { $0.accessibilityLabel()?.hasPrefix(prefix) == true }) else {
                throw Failure(description: "Missing accessible element \(prefix)")
            }
            return found
        }
        func press(_ element: NSAccessibilityElement) throws {
            try verify(element.isAccessibilityEnabled(), "Unavailable control \(element.accessibilityLabel() ?? "")")
            try verify(element.accessibilityPerformPress(), "AXPress rejected \(element.accessibilityLabel() ?? "")")
            paint()
        }
        func press(_ prefix: String) throws { try press(node(prefix)) }
        func hit(_ action: DeskAction) throws -> NSAccessibilityElement {
            guard let target = view.targets.first(where: { $0.action == action }) else { throw Failure(description: "Missing target \(action)") }
            let frame = window.convertToScreen(view.convert(view.viewRect(target.rect), to: nil))
            guard let element = view.accessibilityHitTest(NSPoint(x: frame.midX, y: frame.midY)) as? NSAccessibilityElement else {
                throw Failure(description: "AX hit test did not resolve \(action)")
            }
            return element
        }
        func readText() -> String { children().compactMap { $0.accessibilityValue() as? String }.joined(separator: " ") }
        func route(_ commands: [MistCommand]) throws {
            for command in commands {
                switch command {
                case .record: try press("留影返航")
                case .move(.wait): try press("候一拍")
                case .move(let dir): try press("向" + dir.direction + "，")
                }
            }
        }

        paint()
        try verify(view.isAccessibilityElement(), "Root game group hidden")
        try verify(readText().contains("雾信航局"), "Cover text")
        try await checkWindow(window, view: view, paint: paint)
        paint()
        let depart = try node("启程送信")
        try verify(depart.accessibilityRole() == .button && depart.accessibilityParent() as AnyObject? === view, "Button role/parent")
        let frame = depart.accessibilityFrame()
        try verify(!frame.isEmpty && view.accessibilityHitTest(NSPoint(x: frame.midX, y: frame.midY)) as AnyObject? === depart, "Native hit test")
        window.setFrameOrigin(window.frame.origin.applying(CGAffineTransform(translationX: 29, y: 43)))
        let moved = depart.accessibilityFrame()
        try verify(abs(moved.minX - frame.minX - 29) < 0.1 && abs(moved.minY - frame.minY - 43) < 0.1, "Screen frame did not follow window")
        window.setContentSize(NSSize(width: 864, height: 540))
        paint()
        let resized = depart.accessibilityFrame()
        try verify(abs(resized.width - frame.width * 0.9) < 0.2, "Virtual frame did not follow content resize")
        window.setContentSize(NSSize(width: 960, height: 600))
        paint()
        depart.setAccessibilityFocused(true)
        try verify(depart.isAccessibilityFocused() && view.accessibilityFocusedUIElement as AnyObject? === depart, "Virtual keyboard focus")
        try verify(depart.isAccessibilitySelectorAllowed(NSSelectorFromString("accessibilityPerformPress")), "AXPress selector not accepted")
        try press(hit(.routes))
        let ports = try node("群岛港口")
        try verify((ports.accessibilityChildren()?.count ?? -1) == MistCampaign.levels.count, "Incomplete port atlas")
        let oldLaunch = try hit(.route(1)), twelfthPin = try hit(.port(12))
        try verify(twelfthPin.accessibilityPerformPress(), "Port inspection unavailable")
        try verify(!oldLaunch.isAccessibilityEnabled() && !oldLaunch.accessibilityPerformPress(), "Stale ticket remained actionable before redrawing")
        paint()
        try verify(twelfthPin.isAccessibilitySelected(), "Selected pin state unavailable")
        let locked = try hit(.route(12)), port = MistCampaign.levels[11]
        try verify(!locked.isAccessibilityEnabled() && !locked.accessibilityPerformPress(), "Locked route can launch")
        try verify(readText().contains(port.recipient) && readText().contains(port.briefing), "Selected port ticket missing")
        try press(hit(.back))
        try press(hit(.depart))
        let north = try node("向北，"), east = try node("向东，")
        let record = try node("留影返航")
        try verify(!record.isAccessibilityEnabled() && !record.accessibilityPerformPress(), "Disabled record accepted a press")
        try verify(!north.isAccessibilityEnabled() && !north.accessibilityPerformPress(), "Land should be described and disabled")
        try verify(east.isAccessibilityEnabled(), "East water should be open")
        let map = try node("整幅海图")
        let rows = map.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        try verify(rows.count == view.voyage.level.height + 1 && (rows[1].accessibilityValue() as? String)?.hasPrefix("第1行") == true, "Missing map rows")
        try verify(rows.allSatisfy { $0.accessibilityParent() as AnyObject? === map }, "Map row parent")
        let timeline = try node("潮表")
        let ticks = timeline.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        try verify(ticks.count == view.voyage.level.turnLimit + 1 && ticks.allSatisfy { $0.accessibilityParent() as AnyObject? === timeline }, "Timeline hierarchy")
        try press(east)
        let eastAgain = try node("向东，")
        try verify(eastAgain === east, "Neighbor identity changed after moving")
        try press("撤回")
        try press("设置")
        try verify(!east.isAccessibilityEnabled() && !east.accessibilityPerformPress(), "Stale navigation accepted a press")
        let trails = try node("绘制航迹")
        try verify(trails.accessibilityRole() == .checkBox, "Preference exposed without checkbox role")
        guard let before = (trails.accessibilityValue() as? NSNumber)?.boolValue else { throw Failure(description: "Checkbox has no initial state") }
        try press(trails)
        try verify((trails.accessibilityValue() as? NSNumber)?.boolValue == !before, "Checkbox did not change")
        try press("返回游戏")
        try press("航员手册")
        try press("下一页")
        try verify(readText().contains("重走原路"), "Guide page content unavailable")
        try press("关闭")

        for level in MistCampaign.levels {
            try verify(view.voyage.level.id == level.id && view.desk == .sailing, "Failed to open campaign route")
            try route(level.guide)
            try verify(view.desk == .letter(level.id) && readText().contains(level.letter), "Letter content inaccessible on route \(level.id)")
            try press(level.id == MistCampaign.levels.last?.id ? "领取结航回函" : "下一封信")
        }
        try verify(view.desk == .finale && readText().contains("总局回函"), "Finale inaccessible")
        try press("翻开完整收信册")
        let items = children()
        try verify((view.accessibilityChildrenInNavigationOrder()?.count ?? -1) == items.count, "Incomplete navigation order")
        try press(hit(.wire(.office)))
        guard let wire = view.selectedWire else { throw Failure(description: "No selected telegram") }
        try verify(readText().contains(wire.code), "Telegram code missing from office")
        try press(hit(.wire(.launch)))
        try verify(readText().contains(wire.code), "Remote route described as a campaign number")
        try route(wire.level.guide)
        try verify(view.desk == .telegramReceipt && readText().contains(wire.code), "Telegram receipt missing")
        try press(hit(.wire(.replay)))
        try press(hit(.replayNext))
        try verify(view.replayIndex == 1 && readText().contains("航程回放"), "Replay step unavailable")
        print("PASS native accessibility tree, focus, window coordinates, port atlas, map rows, timeline, disabled actions, settings, guide, all 12 campaign deliveries, telegram and replay through AppKit accessibility presses")
    }
}
