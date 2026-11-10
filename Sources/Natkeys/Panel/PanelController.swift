import AppKit
import NatkeysCore
import SwiftUI

/// A borderless panel that takes keyboard focus without activating Natkeys,
/// so the app you were typing in stays frontmost and ready to receive the paste.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Per-open state: what was selected/copied when the hotkey was pressed, and what Save will store.
@MainActor
final class PanelSession: ObservableObject {
    enum Source { case selection, clipboard }

    @Published var selection: Clip?
    @Published var clipboard: Clip?
    @Published var armed: Source?
    @Published var now = Date()
    @Published var trusted = true
    @Published var showMore: Bool {
        didSet { UserDefaults.standard.set(showMore, forKey: "panelShowMore") }
    }

    init() {
        showMore = UserDefaults.standard.bool(forKey: "panelShowMore")
    }

    var armedClip: Clip? {
        switch armed {
        case .selection: return selection
        case .clipboard: return clipboard
        case nil: return nil
        }
    }

    var armedText: String? { armedClip?.text }

    func prepare(selection: Clip?, clipboard: Clip?, trusted: Bool) {
        self.selection = selection
        // Don't offer the clipboard separately when it's the same as the selection.
        self.clipboard = clipboard == selection ? nil : clipboard
        self.armed = selection != nil ? .selection : nil
        self.now = Date()
        self.trusted = trusted
    }

    func toggleArm(_ source: Source) {
        armed = armed == source ? nil : source
    }

    func clear() {
        selection = nil
        clipboard = nil
        armed = nil
    }
}

@MainActor
final class PanelController {
    let store: Store
    let session = PanelSession()
    private unowned let app: AppDelegate

    private var panel: FloatingPanel?
    private var host: NSHostingView<PanelRoot>?
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var isOpening = false
    private var anchorTop: CGFloat = 0
    private var outsidePress = false
    private var outsideDragged = false

    init(store: Store, app: AppDelegate) {
        self.store = store
        self.app = app
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: Open / close

    func toggle() {
        if isVisible {
            close()
        } else {
            Task { await open() }
        }
    }

    /// - Parameter knownSelection: text the caller already has (the "Save to Natkeys" right-click
    ///   service hands it over), so the selection doesn't need to be grabbed again.
    func open(knownSelection: Clip? = nil, source: String = "hotkey") async {
        guard !isOpening else { return }
        if isVisible {
            guard let knownSelection else { return }
            session.selection = knownSelection
            session.armed = .selection
            return
        }
        isOpening = true
        defer { isOpening = false }

        let mouse = NSEvent.mouseLocation
        let front = NSWorkspace.shared.frontmostApplication
        let frontIsNatkeys = front?.processIdentifier == getpid()

        let clipboard = Clipboard.read(.general)
        let selection: Clip?
        if let knownSelection {
            selection = knownSelection
        } else {
            selection = frontIsNatkeys ? nil : await SelectionGrabber.grab(from: front)
        }

        session.prepare(selection: selection, clipboard: clipboard, trusted: Accessibility.isTrusted)
        if !session.trusted { app.watchAccessibility() }
        Log.info("panel opened (\(source)) over \(front?.bundleIdentifier ?? "?"); selection: \(selection.map { $0.isImage ? "image" : "text" } ?? "none")")
        store.runAutoShift()
        show(at: mouse)
    }

    func close() {
        removeMonitors()
        panel?.orderOut(nil)
        session.clear()
    }

    private func show(at mouse: NSPoint) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let host else { return }

        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Open with the mouse just inside the top-left corner.
        var frame = NSRect(x: mouse.x - 24, y: mouse.y + 12 - size.height, width: size.width, height: size.height)
        frame = clamp(frame, to: visible)
        anchorTop = frame.maxY
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        installMonitors()
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel()

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = FloatingPanel.roundedMask(radius: 12)

        let root = PanelRoot(store: store, session: session, controller: self) { [weak self] size in
            self?.applySize(size)
        }
        let host = NSHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect
        host.frame = effect.bounds
        self.host = host
        return panel
    }

    /// Grows/shrinks the panel downward from its top edge as sections expand.
    private func applySize(_ size: CGSize) {
        guard let panel, panel.isVisible, size.width > 1, size.height > 1 else { return }
        let current = panel.frame
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? current
        var frame = NSRect(x: current.minX, y: anchorTop - size.height, width: size.width, height: size.height)
        frame = clamp(frame, to: visible)
        anchorTop = frame.maxY
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var f = frame
        let margin: CGFloat = 8
        f.origin.x = min(max(f.minX, visible.minX + margin), visible.maxX - f.width - margin)
        if f.minY < visible.minY + margin { f.origin.y = visible.minY + margin }
        if f.maxY > visible.maxY - margin { f.origin.y = visible.maxY - margin - f.height }
        return f
    }

    // MARK: Dismissal

    private func installMonitors() {
        removeMonitors()

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            if event.keyCode == 53 { // Esc
                self.close()
                return nil
            }
            return event
        }) {
            monitors.append(monitor)
        }

        // Clicking elsewhere closes the panel, but starting a drag elsewhere does not,
        // so you can drag a picture or file from another app into a scratch slot.
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.handleOutsideMouse(event) }
            }
        ) {
            monitors.append(monitor)
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, activated?.processIdentifier != getpid() else { return }
                // ⌘-Tab away closes; mouse-down in another app (maybe the start of a drag) doesn't.
                if NSEvent.pressedMouseButtons == 0 { self.close() }
            }
        }
    }

    private func handleOutsideMouse(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            outsidePress = true
            outsideDragged = false
        case .leftMouseDragged:
            if outsidePress { outsideDragged = true }
        case .leftMouseUp:
            if outsidePress, !outsideDragged { close() }
            outsidePress = false
        default:
            close()
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        outsidePress = false
        outsideDragged = false
    }

    // MARK: Actions (called by the panel's views)

    func paste(_ clip: Clip) {
        let target = NSWorkspace.shared.frontmostApplication
        close()
        app.paster.paste(clip, into: target)
    }

    func pasteText(_ text: String) {
        paste(.text(text))
    }

    func copy(_ clip: Clip) {
        close()
        app.paster.copy(clip)
    }

    func pasteSlot(_ group: RotatingGroup, _ slot: WeekSlot) {
        let value = group[slot]
        if value.isEmpty {
            edit(group: group.id, slot: slot)
        } else {
            pasteText(value)
        }
    }

    func pasteCombo(_ rendered: RenderedTemplate) {
        if rendered.isComplete {
            pasteText(rendered.text)
        } else {
            HUD.show(rendered.problems.first ?? "This combo isn't ready", symbol: "exclamationmark.triangle.fill")
        }
    }

    func pasteScratch(_ scratch: Scratch) {
        if let clip = store.clip(for: scratch) {
            paste(clip)
        } else {
            edit(scratch: scratch.id)
        }
    }

    func copyScratch(_ scratch: Scratch) {
        if let clip = store.clip(for: scratch) { copy(clip) }
    }

    func saveArmed(group groupID: UUID, slot: WeekSlot) {
        guard let text = session.armedText, let group = store.group(groupID) else { return }
        store.setSlot(groupID, slot, to: text)
        close()
        HUD.show("Saved to \(group.name) · \(slot.label)")
    }

    func saveArmed(scratch id: UUID) {
        guard let clip = session.armedClip, let scratch = store.scratch(id) else { return }
        store.setScratch(id, to: clip)
        close()
        HUD.show("Saved to \(scratch.name.isEmpty ? "scratch" : scratch.name)")
    }

    func newScratchTapped() {
        if let clip = session.armedClip {
            store.addScratch(clip)
            session.showMore = true
            close()
            HUD.show("Saved to a new scratch clipboard")
        } else {
            let id = store.addScratch(nil)
            session.showMore = true
            close()
            Editors.editScratch(id, store: store)
        }
    }

    func dropped(_ clip: Clip, on scratchID: UUID?) {
        if let scratchID {
            store.setScratch(scratchID, to: clip)
        } else {
            store.addScratch(clip)
            session.showMore = true
        }
        HUD.show(clip.isImage ? "Image saved" : "Text saved")
    }

    func replaceWithClipboard(_ scratchID: UUID) {
        guard let clip = session.clipboard ?? Clipboard.read(.general) else { return }
        store.setScratch(scratchID, to: clip)
    }

    func shift(_ groupID: UUID) {
        store.shift(groupID)
    }

    func clearSlot(_ groupID: UUID, _ slot: WeekSlot) {
        store.setSlot(groupID, slot, to: "")
    }

    func togglePin(_ id: UUID) {
        store.togglePin(id)
    }

    func deleteScratch(_ id: UUID) {
        store.deleteScratch(id)
    }

    func edit(group groupID: UUID, slot: WeekSlot) {
        close()
        Editors.editSlot(groupID, slot, store: store)
    }

    func edit(scratch id: UUID) {
        close()
        Editors.editScratch(id, store: store)
    }

    func openSettings(_ tab: SettingsTab = .general) {
        close()
        app.openSettings(tab)
    }

    func openAccessibility() {
        close()
        Accessibility.requestOrRepair()
    }

    /// Called when Accessibility access changes while the panel may be showing.
    func refreshTrust() {
        session.trusted = Accessibility.isTrusted
    }
}
