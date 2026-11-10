import AppKit

/// Pastes into the app you were using, then puts your own clipboard back.
@MainActor
final class PasteService {
    private let store: Store
    /// The user's clipboard from before the first of a burst of pastes, waiting to be restored.
    private var pendingOriginal: [NSPasteboardItem]?
    private var restoreWork: DispatchWorkItem?

    init(store: Store) {
        self.store = store
    }

    func paste(_ clip: Clip, into target: NSRunningApplication?) {
        let pasteboard = NSPasteboard.general

        guard Accessibility.isTrusted else {
            Clipboard.write(clip, to: pasteboard, transient: false)
            HUD.show("Copied. Press ⌘V to paste (allow Accessibility for auto-paste)", symbol: "doc.on.clipboard")
            return
        }

        let restore = store.data.settings.restoreClipboard
        if restore, pendingOriginal == nil {
            pendingOriginal = Clipboard.snapshot(pasteboard)
        }
        restoreWork?.cancel()

        Clipboard.write(clip, to: pasteboard, transient: restore)
        let ourChangeCount = pasteboard.changeCount

        if let target, target.processIdentifier != getpid(), !target.isActive {
            target.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            KeySender.paste()
            guard let self, restore else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if pasteboard.changeCount == ourChangeCount, let original = self.pendingOriginal {
                    Clipboard.restore(original, to: pasteboard)
                }
                self.pendingOriginal = nil
                self.restoreWork = nil
            }
            self.restoreWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    /// Puts the clip on the clipboard and leaves it there.
    func copy(_ clip: Clip) {
        restoreWork?.cancel()
        restoreWork = nil
        pendingOriginal = nil
        Clipboard.write(clip, to: .general, transient: false)
        HUD.show("Copied", symbol: "doc.on.clipboard")
    }
}
