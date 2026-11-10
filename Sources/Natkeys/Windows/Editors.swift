import AppKit
import NatkeysCore
import SwiftUI

/// Small windows for editing one slot or one scratch clipboard.
@MainActor
enum Editors {
    private static var open: [ObjectIdentifier: NSWindow] = [:]

    static func editSlot(_ groupID: UUID, _ slot: WeekSlot, store: Store) {
        guard let group = store.group(groupID) else { return }
        let box = WindowBox()
        let view = SlotEditorView(
            title: "\(group.name) · \(slot.label)",
            initialText: group[slot],
            onSave: { text in
                store.setSlot(groupID, slot, to: text)
                box.close()
            },
            onCancel: { box.close() }
        )
        present(view, title: "\(group.name) · \(slot.label)", size: NSSize(width: 460, height: 200), box: box)
    }

    static func editScratch(_ id: UUID, store: Store) {
        guard let scratch = store.scratch(id) else { return }
        let box = WindowBox()
        let view = ScratchEditorView(
            store: store,
            scratchID: id,
            initialName: scratch.name,
            initialText: scratch.content.imageFile == nil ? (scratch.content.isEmpty ? "" : (store.clip(for: scratch)?.text ?? "")) : nil,
            close: { box.close() }
        )
        let title = scratch.name.isEmpty ? "Scratch Clipboard" : scratch.name
        present(view, title: title, size: NSSize(width: 480, height: 320), box: box)
    }

    static func present<V: View>(_ view: V, title: String, size: NSSize, box: WindowBox) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(size)
        window.center()
        box.window = window

        let key = ObjectIdentifier(window)
        open[key] = window
        WindowFocus.trackClose(of: window) {
            open[key] = nil
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class WindowBox {
    weak var window: NSWindow?
    func close() { window?.close() }
}

@MainActor
enum WindowFocus {
    private static var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// When the last Natkeys window closes, hand focus back to the app you came from.
    static func trackClose(of window: NSWindow, onClose: (() -> Void)? = nil) {
        let key = ObjectIdentifier(window)
        if let existing = observers[key] {
            NotificationCenter.default.removeObserver(existing)
        }
        observers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                onClose?()
                DispatchQueue.main.async {
                    let othersVisible = NSApp.windows.contains {
                        $0 !== window && $0.isVisible && $0.styleMask.contains(.titled)
                    }
                    if !othersVisible { NSApp.hide(nil) }
                }
            }
        }
    }
}

private struct SlotEditorView: View {
    let title: String
    @State var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    init(title: String, initialText: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        _text = State(initialValue: initialText)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Type a value", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit { onSave(text) }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(text) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 160)
        .onAppear { focused = true }
    }
}

private struct ScratchEditorView: View {
    @ObservedObject var store: Store
    let scratchID: UUID
    @State private var name: String
    @State private var text: String
    private let isText: Bool
    let close: () -> Void

    init(store: Store, scratchID: UUID, initialName: String, initialText: String?, close: @escaping () -> Void) {
        self.store = store
        self.scratchID = scratchID
        _name = State(initialValue: initialName)
        _text = State(initialValue: initialText ?? "")
        isText = initialText != nil
        self.close = close
    }

    private var scratch: Scratch? { store.scratch(scratchID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name (optional, e.g. “Zoom link”)", text: $name)
                .textFieldStyle(.roundedBorder)

            if isText {
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            } else if let file = scratch?.content.imageFile, let image = store.image(file) {
                HStack {
                    Spacer()
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 180)
                    Spacer()
                }
                HStack {
                    Button("Replace with Clipboard") {
                        if let clip = Clipboard.read(.general) { store.setScratch(scratchID, to: clip) }
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.imageURL(file)])
                    }
                }
            }

            HStack {
                Toggle("Pinned", isOn: store.scratchPinnedBinding(scratchID))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.updateScratch(scratchID, name: name, text: isText ? text : nil)
                    close()
                }
                .keyboardShortcut(isText ? KeyboardShortcut("s", modifiers: .command) : .defaultAction)
            }
            if isText {
                Text("⌘S to save")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 260)
    }
}
