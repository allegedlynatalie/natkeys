import AppKit
import ApplicationServices
import Carbon

/// Accessibility access lets Natkeys read the selected text and press ⌘C / ⌘V for you.
enum Accessibility {
    static var isTrusted: Bool { !simulateUntrusted && AXIsProcessTrusted() }

    /// Lets `--snapshot` draw the "not allowed" state.
    nonisolated(unsafe) static var simulateUntrusted = false

    /// Shows the system "Natkeys would like to control this computer" prompt (only if not yet trusted).
    static func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True once the "Allow auto-paste" action has sent the person to System Settings this run.
    @MainActor private static var sentToSettings = false

    /// The "Allow auto-paste…" action. The first time, it shows the system prompt and opens the
    /// Accessibility list. If Natkeys still isn't allowed after that, it offers a reset, because
    /// the usual cause is a stale entry (see `resetAndAsk`).
    @MainActor
    static func requestOrRepair() {
        guard !isTrusted else { return }
        guard sentToSettings else {
            sentToSettings = true
            prompt()
            openSettings()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Natkeys still isn't allowed to paste"
        alert.informativeText = """
            If Natkeys is already switched on under Accessibility, macOS is holding that permission \
            for an older build of Natkeys, and switching it off and on doesn't update it.

            Reset Permission removes Natkeys from the list. Switch it on again when it reappears.
            """
        alert.addButton(withTitle: "Reset Permission")
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: resetAndAsk()
        case .alertSecondButtonReturn: openSettings()
        default: break
        }
    }

    /// macOS saves an Accessibility entry together with the signature of the build that was
    /// allowed. If Natkeys is later signed differently (for example ad hoc before the
    /// "Natkeys Local" certificate existed), the entry never matches again, and toggling it keeps
    /// the old signature. Removing the entry and allowing again records the current one.
    @MainActor
    static func resetAndAsk() {
        let id = Bundle.main.bundleIdentifier ?? "io.github.allegedlynatalie.natkeys"
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tool.arguments = ["reset", "Accessibility", id]
        tool.standardOutput = FileHandle.nullDevice
        tool.standardError = FileHandle.nullDevice
        var status: Int32 = -1
        do {
            try tool.run()
            tool.waitUntilExit()
            status = tool.terminationStatus
        } catch {
            Log.info("tccutil reset failed to start: \(error.localizedDescription)")
        }
        Log.info("tccutil reset Accessibility \(id) exited \(status)")
        sentToSettings = true
        guard status == 0 else {
            let alert = NSAlert()
            alert.messageText = "Natkeys couldn't reset its permission"
            alert.informativeText = "In System Settings → Privacy & Security → Accessibility, select Natkeys, click − to remove it, then click + and add Natkeys from Applications."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { openSettings() }
            return
        }
        // With the old entry gone, this adds Natkeys back to the list (switched off) for this build.
        prompt()
        openSettings()
    }
}

enum KeySender {
    /// Presses ⌘+key. Flags are set explicitly so a still-held Option key doesn't turn ⌘C into ⌥⌘C.
    static func pressCommand(_ keyCode: Int) {
        let source = CGEventSource(stateID: .privateState)
        let code = CGKeyCode(keyCode)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func copy() { pressCommand(kVK_ANSI_C) }
    static func paste() { pressCommand(kVK_ANSI_V) }
}

/// Grabs whatever is selected in the frontmost app when the hotkey is pressed.
@MainActor
enum SelectionGrabber {
    private enum AXSelection {
        case text(String)
        case nothingSelected
        case unknown
    }

    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
    ]

    /// 1. Ask the app through Accessibility (instant, doesn't touch the clipboard).
    /// 2. If the app doesn't say, press ⌘C, read the result, and put the clipboard back.
    static func grab(from app: NSRunningApplication?) async -> Clip? {
        guard Accessibility.isTrusted, let app else { return nil }
        switch axSelection(pid: app.processIdentifier) {
        case .text(let text):
            return .text(text)
        case .nothingSelected:
            return nil
        case .unknown:
            return await copyFallback()
        }
    }

    private static func axSelection(pid: pid_t) -> AXSelection {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return .unknown
        }
        let focused = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.25)

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
              let selected = selectedRef as? String else {
            return .unknown
        }
        if !selected.isEmpty {
            return .text(selected)
        }

        // An empty answer is only trustworthy from real text controls; web views often
        // report "" even when page text is selected, so fall back to ⌘C for those.
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        if let role = roleRef as? String, textRoles.contains(role) {
            return .nothingSelected
        }
        return .unknown
    }

    private static func copyFallback() async -> Clip? {
        let pasteboard = NSPasteboard.general
        let saved = Clipboard.snapshot(pasteboard)
        let before = pasteboard.changeCount

        KeySender.copy()

        var result: Clip?
        for _ in 0..<15 { // up to ~225 ms
            try? await Task.sleep(nanoseconds: 15_000_000)
            if pasteboard.changeCount != before {
                try? await Task.sleep(nanoseconds: 25_000_000) // let the app finish writing
                result = Clipboard.read(pasteboard)
                break
            }
        }
        if pasteboard.changeCount != before {
            Clipboard.restore(saved, to: pasteboard)
        }
        return result
    }
}
