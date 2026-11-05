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
            onMinimize: { [weak self] in self?.panel?.orderOut(nil) },
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
        panel.orderFrontRegardless()

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
        fitPanel()
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
        guard let panel, let item = statusItem, let model else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            if !model.config.altCurrency.isEmpty {
                let showAlt = UserDefaults.standard.bool(forKey: "showAlt")
                let code = showAlt ? model.config.currency : model.config.altCurrency
                menu.addItem(withTitle: L("显示%@", currencyName(code)), action: #selector(toggleCurrency), keyEquivalent: "")
                    .target = self
            }
            menu.addItem(withTitle: L("设置…"), action: #selector(openSettings), keyEquivalent: "").target = self
            if let tag = updates.latestTag {
                menu.addItem(withTitle: L("下载新版本 %@", tag), action: #selector(openRelease), keyEquivalent: "")
                    .target = self
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: L("退出"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc func toggleCurrency() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "showAlt"), forKey: "showAlt")
        tick()
    }

    @objc func openRelease() {
        if let url = updates.latestURL { NSWorkspace.shared.open(url) }
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
