import AppKit
import Carbon
import NatkeysCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store: Store
    lazy var paster = PasteService(store: store)
    lazy var panel = PanelController(store: store, app: self)
    let settingsRouter = SettingsRouter()

    init(store: Store) {
        self.store = store
        super.init()
    }

    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private(set) var hotKeyRegistered = false
    private var shiftTimer: Timer?
    private var settingsWindow: NSWindow?
    private var serviceProvider: ServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A hotkey app has no windows most of the time; never let macOS quit it as "idle".
        ProcessInfo.processInfo.disableAutomaticTermination("Natkeys listens for Option+Space")
        ProcessInfo.processInfo.disableSuddenTermination()

        setupMainMenu()
        setupStatusItem()
        registerHotKey(showAlert: true)

        // Right-click menu entries ("Open Natkeys", "Save to Natkeys") in other apps' text boxes.
        let provider = ServiceProvider { [weak self] clip, source in
            guard let self else { return }
            Task { await self.panel.open(knownSelection: clip, source: source) }
        }
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()

        if !Accessibility.isTrusted {
            Accessibility.prompt()
            watchAccessibility()
        }
        LoginItem.configureOnFirstLaunch(enabled: store.data.settings.launchAtLogin)

        // Sunday auto-shift: check now, every 30 seconds, and after the Mac wakes.
        store.runAutoShift()
        shiftTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.store.runAutoShift() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.store.runAutoShift() }
        }

        if store.isFirstLaunch {
            HUD.show("Natkeys is running. Press Option+Space", symbol: "keyboard")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: Accessibility

    private var trustTimer: Timer?

    /// While Natkeys isn't allowed, checks once a second, so the panel and menu update the moment
    /// it's switched on in System Settings, with a bubble to confirm it worked.
    func watchAccessibility() {
        guard trustTimer == nil, !Accessibility.isTrusted else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard Accessibility.isTrusted else { return }
                timer.invalidate()
                self?.trustTimer = nil
                self?.panel.refreshTrust()
                Log.info("accessibility access granted")
                HUD.show("Natkeys can paste for you now", symbol: "checkmark.circle.fill")
            }
        }
    }

    // MARK: Hotkey

    @discardableResult
    func registerHotKey(showAlert: Bool) -> Bool {
        let hotKey = self.hotKey ?? HotKey { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggle() }
        }
        self.hotKey = hotKey
        let status = hotKey.register(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        hotKeyRegistered = status == noErr
        Log.info("Option+Space hotkey \(hotKeyRegistered ? "registered" : "FAILED (status \(status))"); accessibility trusted: \(Accessibility.isTrusted)")
        if !hotKeyRegistered, showAlert {
            let alert = NSAlert()
            alert.messageText = "Option+Space is already taken"
            alert.informativeText = "Another app is using Option+Space (Claude's Quick Entry uses it by default). Change that app's shortcut, then choose Try Again. (Error \(status))"
            alert.addButton(withTitle: "Try Again")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                return registerHotKey(showAlert: true)
            }
        }
        return hotKeyRegistered
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Natkeys")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Natkeys (Option+Space)"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        menu.removeAllItems()

        let open = ClosureMenuItem(title: "Open Natkeys Panel") { [weak self] in
            self?.panel.toggle()
        }
        open.keyEquivalent = " "
        open.keyEquivalentModifierMask = [.option]
        menu.addItem(open)

        let shiftable = store.data.groups.filter(\.canShift)
        let shift = ClosureMenuItem(title: shiftable.count == 1 ? "Shift \(shiftable[0].name) This → Last" : "Shift All Weekly Groups This → Last") { [weak self] in
            self?.store.shiftAll()
        }
        shift.isEnabled = !shiftable.isEmpty
        menu.addItem(shift)

        menu.addItem(.separator())
        if !hotKeyRegistered {
            menu.addItem(ClosureMenuItem(title: "⚠︎ Option+Space unavailable. Try Again") { [weak self] in
                self?.registerHotKey(showAlert: true)
            })
        }
        if !Accessibility.isTrusted {
            menu.addItem(ClosureMenuItem(title: "⚠︎ Allow Accessibility Access…") { [weak self] in
                Accessibility.requestOrRepair()
                self?.watchAccessibility()
            })
        }
        let settings = ClosureMenuItem(title: "Settings…") { [weak self] in self?.openSettings(.general) }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Natkeys", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// Even though Natkeys has no visible menu bar, its text fields need Edit-menu shortcuts (⌘C, ⌘V, ⌘A…).
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(ClosureMenuItem(title: "Settings…") { [weak self] in self?.openSettings(.general) })
        appMenu.items.last?.keyEquivalent = ","
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Natkeys", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Natkeys", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    // MARK: Settings window

    func openSettings(_ tab: SettingsTab) {
        settingsRouter.tab = tab
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(store: store, router: settingsRouter, app: self))
            let window = NSWindow(contentViewController: host)
            window.title = "Natkeys Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
            WindowFocus.trackClose(of: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
