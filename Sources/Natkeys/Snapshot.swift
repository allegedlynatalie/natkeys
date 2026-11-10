import AppKit
import NatkeysCore
import SwiftUI

/// `Natkeys --snapshot <folder>` renders the panel and Settings tabs to PNGs with sample data
/// (in a temporary data folder, never your real one) and exits. Used to check the layout.
@MainActor
enum Snapshot {
    static func run(outputFolder: URL) {
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        let dataFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NatkeysSnapshot-\(UUID().uuidString)", isDirectory: true)
        let store = Store(folder: dataFolder)
        fillSampleData(store)
        let app = AppDelegate(store: store)
        let controller = PanelController(store: store, app: app)
        let session = controller.session

        // 1. Panel right after selecting a title and pressing Option+Space.
        session.prepare(selection: .text("Grace Upon Grace"), clipboard: .text("https://zoom.us/j/5550100"), trusted: true)
        session.showMore = false
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let name = appearance == .aqua ? "light" : "dark"
            render(PanelView(store: store, session: session, controller: controller),
                   appearance: appearance, to: outputFolder.appendingPathComponent("panel-selection-\(name).png"))
        }

        // 2. Panel with nothing selected and "More" expanded.
        session.prepare(selection: nil, clipboard: nil, trusted: false)
        session.showMore = true
        render(PanelView(store: store, session: session, controller: controller),
               appearance: .aqua, to: outputFolder.appendingPathComponent("panel-plain-light.png"))
        session.showMore = false

        // 3. Settings tabs.
        let router = SettingsRouter()
        for tab in [SettingsTab.general, .weekly, .combos, .dates, .scratch] {
            router.tab = tab
            render(SettingsView(store: store, router: router, app: app).frame(width: 680, height: 600),
                   appearance: .aqua, to: outputFolder.appendingPathComponent("settings-\(tab.rawValue).png"))
        }
        // General again, as it looks before Accessibility is allowed.
        Accessibility.simulateUntrusted = true
        router.tab = .general
        render(SettingsView(store: store, router: router, app: app).frame(width: 680, height: 600),
               appearance: .aqua, to: outputFolder.appendingPathComponent("settings-general-not-allowed.png"))
        Accessibility.simulateUntrusted = false

        try? FileManager.default.removeItem(at: dataFolder)
        print("Snapshots written to \(outputFolder.path)")
    }

    private static func fillSampleData(_ store: Store) {
        store.data.groups[0].thisWeek = "Grace Upon Grace"
        store.data.groups[0].lastWeek = "The Narrow Gate"
        store.addScratch(.text("https://zoom.us/j/5550100?pwd=abc"), name: "Zoom link", pinned: true)
        store.addScratch(.text("1234 Main Street\nSpringfield"), name: "Church address", pinned: true)
        if let logo = sampleImage()?.pngData {
            store.addScratch(.image(logo), name: "Logo", pinned: true)
        }
        store.addScratch(.text("Welcome to worship! Please silence your phones."), pinned: false)
        store.addScratch(.text("Livestream starts at 10:25"), name: "Stream note", pinned: false)
        store.addScratch(nil)
    }

    private static func sampleImage() -> NSImage? {
        NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
            NSColor.systemIndigo.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()
            let cross = NSBezierPath()
            cross.lineWidth = 14
            cross.move(to: NSPoint(x: 60, y: 20)); cross.line(to: NSPoint(x: 60, y: 100))
            cross.move(to: NSPoint(x: 32, y: 72)); cross.line(to: NSPoint(x: 88, y: 72))
            NSColor.white.setStroke()
            cross.stroke()
            return true
        }
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let window = NSWindow(
            contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
