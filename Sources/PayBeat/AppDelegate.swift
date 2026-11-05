import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let holidays = HolidayStore()
    let rates = RateStore()
    let updates = UpdateChecker()
    var model: AppModel?
    var panel: NSPanel?
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var ticker: Timer?
    let notchState = NotchState()
    var notchPanel: NSPanel?
    var hoverTimer: Timer?
    var collapseWork: DispatchWorkItem?
    var mode: DisplayMode?
    /// Hidden from the menu bar item or the card's minimize button.
    var hidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        do {
            if let cfg = try loadConfig() {
                start(try AppModel(config: cfg, holidays: holidays, rates: rates, updates: updates))
            } else {
                openSettings()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("配置文件有误，请重新设置")
            alert.informativeText = "\(configURL.path)\n\(error.localizedDescription)"
            NSApp.activate()
            alert.runModal()
            openSettings()
        }
    }

    /// Without a main menu, copy/paste/select-all shortcuts do nothing in text fields.
    func installEditMenu() {
        let edit = NSMenu(title: L("编辑"))
        edit.addItem(withTitle: L("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem()
        item.submenu = edit
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(item)
    }

    func start(_ model: AppModel) {
        self.model = model
        let host = NSHostingView(rootView: CardView(
            model: model, rates: rates, updates: updates,
            onMinimize: { [weak self] in
                self?.hidden = true
                self?.refreshVisibility()
            },
            onSettings: { [weak self] in self?.openSettings() }))
        host.sizingOptions = [.intrinsicContentSize]
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        if !panel.setFrameUsingName("WorkTicker"), let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.maxX - panel.frame.width - 20, y: vf.minY + 20))
        }
        panel.setFrameAutosaveName("WorkTicker")
        self.panel = panel
        fitPanel()
        makeNotchPanel(model)
        applyMode()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollNotchHover() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutNotch() }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        tick()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func tick() {
        applyMode()
        if mode == .notch { layoutNotch() } else { fitPanel() }
        guard let model, let button = statusItem?.button else { return }
        let s = model.snapshot()
        switch model.config.statusBar {
        case .today:
            button.image = nil
            let shown = model.display(s.today, showAlt: UserDefaults.standard.bool(forKey: "showAlt"))
            button.title = formatMoney(shown.value, shown.code, 2)
        case .countdown:
            button.image = nil
            button.title = s.phase == .working || s.phase == .lunch ? L("距下班 %@", hms(s.toOff)) : s.phase.label
        case .icon:
            button.title = ""
            button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: L("薪跳"))
        }
    }

    /// Keeps the panel sized to the card, anchored at its top edge.
    func fitPanel() {
        guard let panel, let host = panel.contentView else { return }
        let size = host.fittingSize
        guard abs(size.width - panel.frame.width) > 0.5 || abs(size.height - panel.frame.height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    @objc func statusItemClicked() {
        guard let item = statusItem, let model else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            item.menu = buildMenu(model)
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            toggleHidden()
        }
    }

    // MARK: Menu

    func buildMenu(_ model: AppModel) -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem()
        let host = NSHostingView(rootView: MenuHeader(model: model))
        host.frame.size = host.fittingSize
        header.view = host
        menu.addItem(header)
        menu.addItem(.separator())

        if model.snapshot().phase == .overtime {
            add(menu, L("结束加班"), #selector(stopOvertime))
        }
        let modeName = (mode ?? model.config.displayMode).label
        add(menu, hidden ? L("显示%@", modeName) : L("隐藏%@", modeName), #selector(toggleHidden))
        menu.addItem(choices(L("显示方式"), DisplayMode.allCases, model.config.displayMode, \.label, #selector(pickDisplayMode(_:))))
        menu.addItem(choices(L("菜单栏显示"), StatusBarMode.allCases, model.config.statusBar, \.label, #selector(pickStatusBar(_:))))
        if !model.config.altCurrency.isEmpty {
            let showAlt = UserDefaults.standard.bool(forKey: "showAlt")
            add(menu, L("显示%@", currencyName(showAlt ? model.config.currency : model.config.altCurrency)), #selector(toggleCurrency))
        }
        menu.addItem(.separator())
        add(menu, L("开机自启"), #selector(toggleLaunchAtLogin)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        add(menu, L("设置…"), #selector(openSettings), key: ",")
        if let tag = updates.latestTag {
            add(menu, L("下载新版本 %@", tag), #selector(openRelease))
        }
        add(menu, L("关于薪跳"), #selector(showAbout))
        menu.addItem(.separator())
        menu.addItem(withTitle: L("退出薪跳"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @discardableResult
    func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Submenu of options with a checkmark on the current one; the item carries the option's raw value.
    func choices<T: RawRepresentable & Equatable>(
        _ title: String, _ options: [T], _ selected: T, _ label: KeyPath<T, String>, _ action: Selector
    ) -> NSMenuItem where T.RawValue == String {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for option in options {
            let i = add(sub, option[keyPath: label], action)
            i.representedObject = option.rawValue
            i.state = option == selected ? .on : .off
        }
        item.submenu = sub
        return item
    }

    func updateConfig(_ change: (inout Config) -> Void) {
        guard let model else { return }
        var cfg = model.config
        change(&cfg)
        do { try model.apply(cfg) } catch { log("保存设置失败: \(error)") }
        tick()
    }

    @objc func pickDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = DisplayMode(rawValue: raw) else { return }
        hidden = false
        updateConfig { $0.displayMode = value }
    }

    @objc func pickStatusBar(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = StatusBarMode(rawValue: raw) else { return }
        updateConfig { $0.statusBar = value }
    }

    @objc func toggleHidden() {
        hidden.toggle()
        refreshVisibility()
    }

    @objc func stopOvertime() {
        model?.stopOvertime()
    }

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    @objc func showAbout() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let credits = NSMutableAttributedString(
            string: L("打工人哄自己上班神器（当然也可能被狗资本家气笑）") + "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor, .paragraphStyle: center])
        credits.append(NSAttributedString(
            string: "github.com/Tsukinai/paybeat",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: repoURL, .paragraphStyle: center]))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: L("薪跳"), .credits: credits])
    }

    @objc func toggleCurrency() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "showAlt"), forKey: "showAlt")
        tick()
    }

    @objc func openRelease() {
        if let url = updates.latestURL { NSWorkspace.shared.open(url) }
    }

    // MARK: Notch

    func makeNotchPanel(_ model: AppModel) {
        let host = NSHostingView(rootView: NotchView(
            model: model, rates: rates, updates: updates, state: notchState,
            onSettings: { [weak self] in self?.openSettings() }))
        host.sizingOptions = []
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar, like other notch apps.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        notchPanel = panel
    }

    /// Centers a fixed transparent window on the notch; the black shape inside grows and shrinks.
    func layoutNotch() {
        guard let panel = notchPanel, let model else { return }
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        var notch = CGSize(width: 120, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
        var centerX = screen.frame.midX
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notch = CGSize(width: screen.frame.width - l.width - r.width, height: screen.safeAreaInsets.top)
            centerX = screen.frame.minX + l.width + notch.width / 2
        }
        if notchState.notchSize != notch { notchState.notchSize = notch }
        let scale = (model.preview ?? model.config).scale
        let size = NSSize(width: max(320 * scale, notch.width + 132) + 40, height: notch.height + 420 * scale)
        let frame = NSRect(x: centerX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// Expands while the pointer is over the black shape, collapses shortly after it leaves.
    func pollNotchHover() {
        guard let panel = notchPanel, panel.isVisible else { return }
        let s = notchState.shapeSize
        let f = panel.frame
        let shape = NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
        if shape.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
            collapseWork?.cancel()
            collapseWork = nil
            if !notchState.expanded {
                notchState.expanded = true
                panel.ignoresMouseEvents = false
            }
        } else if notchState.expanded, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.notchState.expanded = false
                    self.notchPanel?.ignoresMouseEvents = true
                    self.collapseWork = nil
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    func applyMode() {
        guard let model else { return }
        let want = (model.preview ?? model.config).displayMode
        guard want != mode else { return }
        mode = want
        refreshVisibility()
    }

    func refreshVisibility() {
        if mode == .card, !hidden { panel?.orderFrontRegardless() } else { panel?.orderOut(nil) }
        if mode == .notch, !hidden {
            layoutNotch()
            notchPanel?.orderFrontRegardless()
        } else {
            notchPanel?.orderOut(nil)
            notchState.expanded = false
            notchPanel?.ignoresMouseEvents = true
        }
    }


    @objc func openSettings() {
        if settingsWindow?.isVisible != true {
            let firstRun = model == nil
            let view = SettingsView(
                config: model?.config ?? Config(), holidays: holidays, updates: updates, firstRun: firstRun,
                onChange: { [weak self] draft in self?.model?.preview = draft },
                onSave: { [weak self] cfg, launchAtLogin in try self?.save(cfg, launchAtLogin: launchAtLogin) })
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = firstRun ? L("薪跳") : L("设置")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func save(_ cfg: Config, launchAtLogin: Bool) throws {
        if let model {
            try model.apply(cfg)
        } else {
            let model = try AppModel(config: cfg, holidays: holidays, rates: rates, updates: updates)
            try saveConfig(cfg)
            start(model)
        }
        let service = SMAppService.mainApp
        if launchAtLogin, service.status != .enabled { try service.register() }
        if !launchAtLogin, service.status == .enabled { try service.unregister() }
        tick()
        settingsWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        model?.preview = nil
        if model == nil { NSApp.terminate(nil) }
    }
}
