import AppKit

@MainActor
final class HarborDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var pendingCharts: [URL] = []
    var window: NSWindow?
    var station: StationView?
    var hiddenRun: Bool {
        #if MIST_POST_QA
        return CommandLine.arguments.contains("--qa") || CommandLine.arguments.contains("--snapshot")
        #else
        return false
        #endif
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let env = ProcessInfo.processInfo.environment
        let custom = env["MIST_POST_SAVE"].map { URL(fileURLWithPath:$0) }
        let save = DispatchStore(file:hiddenRun ? custom : custom ?? DispatchStore.defaultFile())
        let resources = env["MIST_POST_RESOURCES"].map { URL(fileURLWithPath:$0) }
            ?? Bundle.main.resourceURL ?? URL(fileURLWithPath:".")
        let view = StationView(store:save, resources:resources)
        station = view
        #if MIST_POST_QA
        if hiddenRun {
            view.frozenTime = 10
            DispatchQueue.main.async { qaEntry(view, arguments:CommandLine.arguments) }
            return
        }
        #endif
        let win = NSWindow(contentRect:R(0,0,1200,750),
                           styleMask:[.titled,.closable,.miniaturizable,.resizable],
                           backing:.buffered,defer:false)
        win.title = "雾信航局  ·  MIST POST"
        win.contentView = view
        win.contentAspectRatio = NSSize(width:16,height:10)
        win.contentMinSize = NSSize(width:800,height:500)
        if let visible = NSScreen.main?.visibleFrame {
            let width = min(1200,visible.width*0.92,(visible.height-59)*1.6)
            win.setContentSize(NSSize(width:width,height:width/1.6))
        }
        win.center()
        win.setFrameAutosaveName("MistPost.StationWindow.v1")
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.fullScreenPrimary]
        window = win
        win.delegate = self
        NSApp.mainMenu = applicationMenu()
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps:true)
        view.setRunning(NSApp.isActive)
        for file in pendingCharts { view.receiveChart(from:file) }
        pendingCharts.removeAll()
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let station, !hiddenRun {
            for url in urls { station.receiveChart(from:url) }
            window?.makeKeyAndOrderFront(nil)
        } else {
            pendingCharts.append(contentsOf:urls)
        }
    }
    @objc func openChart() { station?.act(.studio(.importChart)) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidBecomeActive(_ note: Notification) { if !hiddenRun { station?.setRunning(true) } }
    func applicationDidResignActive(_ note: Notification) { station?.setRunning(false) }
    func windowDidMiniaturize(_ note: Notification) { station?.setRunning(false) }
    func windowDidDeminiaturize(_ note: Notification) { station?.setRunning(NSApp.isActive == true) }
    @objc func showGuide() { station?.act(.guide) }
    @objc func showPrefs() { station?.act(.preferences) }
    @objc func home() { station?.act(.home) }
    private func applicationMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let app = NSMenu(title:"雾信航局")
        appItem.submenu = app
        let pref = app.addItem(withTitle:"航舱设置…",action:#selector(showPrefs),keyEquivalent:",")
        pref.target = self
        app.addItem(.separator())
        app.addItem(withTitle:"隐藏雾信航局",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        app.addItem(withTitle:"退出雾信航局",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let chartItem = NSMenuItem()
        menu.addItem(chartItem)
        let file = NSMenu(title:"文件")
        chartItem.submenu = file
        let open = file.addItem(withTitle:"打开自制海图…",action:#selector(openChart),keyEquivalent:"o")
        open.target = self
        let editingItem = NSMenuItem()
        menu.addItem(editingItem)
        let editing = NSMenu(title:"编辑")
        editingItem.submenu = editing
        editing.addItem(withTitle:"剪切",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
        editing.addItem(withTitle:"拷贝",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        editing.addItem(withTitle:"粘贴",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        editing.addItem(withTitle:"全选",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        let winItem = NSMenuItem()
        menu.addItem(winItem)
        let win = NSMenu(title:"窗口")
        winItem.submenu = win
        win.addItem(withTitle:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        let full = win.addItem(withTitle:"切换全屏",action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f")
        full.keyEquivalentModifierMask = [.command,.control]
        let helpItem = NSMenuItem()
        menu.addItem(helpItem)
        let help = NSMenu(title:"帮助")
        helpItem.submenu = help
        let guide = help.addItem(withTitle:"航员手册",action:#selector(showGuide),keyEquivalent:"?")
        guide.target = self
        let homeItem = help.addItem(withTitle:"返回雾信航局",action:#selector(home),keyEquivalent:"0")
        homeItem.target = self
        return menu
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = HarborDelegate()
    let accessibilityFixture = CommandLine.arguments.contains("--accessibility")
    application.setActivationPolicy(delegate.hiddenRun ? (accessibilityFixture ? .accessory : .prohibited) : .regular)
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
}
