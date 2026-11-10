import AppKit

/// Answers the right-click menu entries declared under NSServices in Info.plist.
///
/// A service call is synchronous: the app you right-clicked in waits until this returns.
/// So each handler returns right away (writing nothing back, which leaves the text box
/// untouched) and opens the panel a moment later, once the menu has closed.
final class ServiceProvider: NSObject {
    private let open: @MainActor (Clip?, String) -> Void

    init(open: @escaping @MainActor (Clip?, String) -> Void) {
        self.open = open
    }

    /// "Open Natkeys": shown in editable text boxes. Same as pressing Option+Space.
    @objc func openPanelService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        schedule(nil, source: "right-click Open Natkeys")
    }

    /// "Save to Natkeys": shown wherever text is selected. Opens the panel with that text ready to save.
    @objc func saveSelectionService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let text = pboard.string(forType: .string)
            ?? pboard.string(forType: NSPasteboard.PasteboardType("NSStringPboardType"))
        let clip = text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Clip.text($0) }
        schedule(clip, source: "right-click Save to Natkeys")
    }

    private func schedule(_ clip: Clip?, source: String) {
        let open = self.open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MainActor.assumeIsolated { open(clip, source) }
        }
    }
}
