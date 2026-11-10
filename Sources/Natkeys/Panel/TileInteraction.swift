import AppKit
import SwiftUI

/// A right-click menu entry usable from both SwiftUI and AppKit.
struct MenuAction: Identifiable {
    let id = UUID()
    var title: String
    var destructive = false
    var isSeparator = false
    var action: () -> Void = {}

    static var separator: MenuAction { MenuAction(title: "", isSeparator: true) }

    static func nsMenu(_ actions: [MenuAction]) -> NSMenu {
        let menu = NSMenu()
        for action in actions {
            if action.isSeparator {
                menu.addItem(.separator())
            } else {
                menu.addItem(ClosureMenuItem(title: action.title, handler: action.action))
            }
        }
        return menu
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { handler() }
}

extension View {
    /// Attaches a SwiftUI context menu built from MenuActions.
    func menuActions(_ actions: [MenuAction]) -> some View {
        contextMenu {
            ForEach(actions) { action in
                if action.isSeparator {
                    Divider()
                } else {
                    Button(action.title, role: action.destructive ? .destructive : nil, action: action.action)
                }
            }
        }
    }
}

/// What a scratch tile hands to the system when you drag it out.
struct DragPayload {
    var writer: NSPasteboardWriting
    var image: NSImage
}

/// Transparent AppKit layer over a scratch tile: click to paste, drag out (files/text),
/// drop in (images/text from other apps), and right-click menu. AppKit is used here because
/// a real file-URL drag is what websites' "drop image here to upload" boxes expect.
struct TileInteraction: NSViewRepresentable {
    var onClick: () -> Void
    var dragPayload: (() -> DragPayload?)?
    var menu: () -> [MenuAction]
    var onDrop: ((Clip) -> Void)?
    var onHover: (Bool) -> Void
    var onDropTarget: (Bool) -> Void
    /// Drag-out started / ended (true when something accepted the drop).
    var onDragBegan: (() -> Void)? = nil
    var onDragEnded: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> TileInteractionView {
        let view = TileInteractionView()
        configure(view)
        return view
    }

    func updateNSView(_ view: TileInteractionView, context: Context) {
        configure(view)
    }

    private func configure(_ view: TileInteractionView) {
        view.onClick = onClick
        view.dragPayload = dragPayload
        view.menuActions = menu
        view.onDrop = onDrop
        view.onHover = onHover
        view.onDropTarget = onDropTarget
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
    }
}

final class TileInteractionView: NSView, NSDraggingSource {
    var onClick: (() -> Void)?
    var dragPayload: (() -> DragPayload?)?
    var menuActions: (() -> [MenuAction])?
    var onDrop: ((Clip) -> Void)?
    var onHover: ((Bool) -> Void)?
    var onDropTarget: ((Bool) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        MainActor.assumeIsolated {
            registerForDraggedTypes(DropReader.acceptedTypes)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard hypot(dx, dy) > 4 else { return }
        mouseDownEvent = nil
        guard let payload = dragPayload?() else { return }

        let item = NSDraggingItem(pasteboardWriter: payload.writer)
        let start = convert(down.locationInWindow, from: nil)
        let size = payload.image.size
        item.setDraggingFrame(
            NSRect(x: start.x - size.width / 2, y: start.y - size.height / 2, width: size.width, height: size.height),
            contents: payload.image
        )
        onHover?(false)
        beginDraggingSession(with: [item], event: down, source: self)
        onDragBegan?()
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard mouseDownEvent != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let actions = menuActions?(), !actions.isEmpty else { return nil }
        return MenuAction.nsMenu(actions)
    }

    // MARK: Drag source

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?(!operation.isEmpty)
    }

    // MARK: Drop destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Ignore drags that started in Natkeys itself (e.g. one tile onto another).
        guard onDrop != nil, sender.draggingSource == nil else { return [] }
        onDropTarget?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTarget?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDropTarget?(false)
        guard let onDrop else { return false }
        MainActor.assumeIsolated {
            DropReader.read(sender.draggingPasteboard) { clip in
                if let clip {
                    onDrop(clip)
                } else {
                    NSSound.beep()
                }
            }
        }
        return true
    }
}

enum DragImages {
    static func forImage(_ image: NSImage) -> NSImage {
        let maxSide: CGFloat = 96
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = NSSize(width: max(size.width * scale, 16), height: max(size.height * scale, 16))
        return NSImage(size: target, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    static func forText(_ text: String) -> NSImage {
        let line = String(text.split(whereSeparator: \.isNewline).first ?? "").prefix(40)
        let attributed = NSAttributedString(string: String(line), attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
        ])
        let textSize = attributed.size()
        let size = NSSize(width: ceil(textSize.width) + 16, height: ceil(textSize.height) + 8)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            attributed.draw(at: NSPoint(x: 8, y: 4))
            return true
        }
    }
}
