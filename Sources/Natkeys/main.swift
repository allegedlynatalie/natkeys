import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let arguments = CommandLine.arguments

    // Developer aid: render the panel and Settings to PNGs and exit.
    if let flag = arguments.firstIndex(of: "--snapshot") {
        let folder = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "snapshots"
        app.setActivationPolicy(.accessory)
        Snapshot.run(outputFolder: URL(fileURLWithPath: folder))
        exit(0)
    }

    let delegate = AppDelegate(store: Store())
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
    app.run()
}
