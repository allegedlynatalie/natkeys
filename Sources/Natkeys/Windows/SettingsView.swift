import AppKit
import NatkeysCore
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, Hashable {
    case general, weekly, combos, dates, scratch
}

@MainActor
final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var router: SettingsRouter
    let app: AppDelegate

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralSettings(store: store, app: app)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            WeeklySettings(store: store)
                .tabItem { Label("Weekly Groups", systemImage: "calendar") }
                .tag(SettingsTab.weekly)
            ComboSettings(store: store)
                .tabItem { Label("Combos", systemImage: "text.append") }
                .tag(SettingsTab.combos)
            DateSettings(store: store)
                .tabItem { Label("Date Formats", systemImage: "calendar.badge.clock") }
                .tag(SettingsTab.dates)
            ScratchSettings(store: store)
                .tabItem { Label("Scratch", systemImage: "doc.on.clipboard") }
                .tag(SettingsTab.scratch)
        }
        .padding(12)
        .frame(minWidth: 640, idealWidth: 680, minHeight: 500, idealHeight: 560)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var store: Store
    let app: AppDelegate
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var trusted = Accessibility.isTrusted
    @State private var hotKeyOK = true

    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var flipTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: store.data.settings.flipHour,
                    minute: store.data.settings.flipMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.data.settings.flipHour = parts.hour ?? 14
                store.data.settings.flipMinute = parts.minute ?? 0
            }
        )
    }

    var body: some View {
        Form {
            Section("Hotkey") {
                LabeledContent("Open the Natkeys panel", value: "⌥ Option + Space")
                if !hotKeyOK {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Another app is already using Option+Space. If Claude's Quick Entry uses it, change that in Claude → Settings, then try again.")
                            .foregroundStyle(.red)
                        Button("Try Again") { hotKeyOK = app.registerHotKey(showAlert: false) }
                    }
                }
            }

            Section("Weekly flip") {
                DatePicker("Every Sunday at", selection: flipTime, displayedComponents: .hourAndMinute)
                Text("At this time each Sunday, weekly groups shift This Week → Last Week, and “Last Sunday” / “Coming Sunday” roll forward, so the Last Week title always matches the Last Sunday date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pasting") {
                Toggle("Put my clipboard back after Natkeys pastes", isOn: $store.data.settings.restoreClipboard)
                if trusted {
                    Label("Accessibility access is on, so Natkeys can read selections and paste for you.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Natkeys needs Accessibility access to read selected text and paste for you.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        HStack {
                            Button("Open Accessibility Settings…") {
                                Accessibility.prompt()
                                Accessibility.openSettings()
                                app.watchAccessibility()
                            }
                            Button("Reset Permission") {
                                Accessibility.resetAndAsk()
                                app.watchAccessibility()
                            }
                        }
                        Text("Turn on Natkeys in the list. If it's already on but this still says it's off, macOS is holding the permission for an older build of Natkeys. Click Reset Permission, then turn Natkeys on again when it reappears in the list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch Natkeys at login", isOn: Binding(
                    get: { loginEnabled },
                    set: { newValue in
                        do {
                            try LoginItem.set(newValue)
                            store.data.settings.launchAtLogin = newValue
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        loginEnabled = LoginItem.isEnabled
                    }
                ))
                .disabled(!LoginItem.isInstalledCopy)
                if !LoginItem.isInstalledCopy {
                    Text("Available once Natkeys is installed in your Applications folder.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if LoginItem.needsApproval {
                    Text("Approve Natkeys in System Settings → General → Login Items.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Backup") {
                HStack {
                    Button("Export Backup…") { exportBackup() }
                    Button("Import Backup…") { importBackup() }
                    Spacer()
                    Button("Show Data Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.folder])
                    }
                }
                Text("A backup is a single file with your groups, combos, date formats, and scratch clipboards (including images).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hotKeyOK = app.hotKeyRegistered
            loginEnabled = LoginItem.isEnabled
        }
        .onReceive(refresh) { _ in
            trusted = Accessibility.isTrusted
            loginEnabled = LoginItem.isEnabled
        }
    }

    /// "1.0 (261104.1329)": the build number is the build's date and time.
    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        guard let build = info["CFBundleVersion"] as? String, build != "1" else { return short }
        return "\(short) (\(build))"
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let stamp = DateText.format(Date(), pattern: "yyyy-MM-dd", calendar: .natkeys())
        panel.nameFieldStringValue = "Natkeys Backup \(stamp).json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportBackup(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let confirm = NSAlert()
        confirm.messageText = "Replace all Natkeys data with this backup?"
        confirm.informativeText = "Your current groups, combos, date formats, and scratch clipboards will be replaced."
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.importBackup(from: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

// MARK: - Weekly groups

private struct WeeklySettings: View {
    @ObservedObject var store: Store

    var body: some View {
        Form {
            ForEach(store.data.groups) { group in
                Section {
                    CommitTextField(title: "Group name", value: group.name) { store.renameGroup(group.id, to: $0) }
                    TextField("This Week", text: store.groupBinding(group.id).thisWeek)
                    TextField("Last Week", text: store.groupBinding(group.id).lastWeek)
                    Toggle("Shift automatically every Sunday at \(store.data.settings.flipTimeDescription)",
                           isOn: store.groupBinding(group.id).autoShift)
                    HStack {
                        Button("Shift Now") { store.shift(group.id) }
                            .disabled(!group.canShift)
                        Spacer()
                        Button("Delete Group…", role: .destructive) { confirmDelete(group) }
                    }
                }
            }
            Section {
                Button("Add Weekly Group") { store.addGroup() }
                Text("Each group has a This Week and a Last Week slot and appears in the panel. Use it in combos as {Group Name: This Week} or {Group Name: Last Week}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func confirmDelete(_ group: RotatingGroup) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(group.name)”?"
        alert.informativeText = "Its This Week and Last Week values will be removed. Combos that use it will show it as unknown."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.deleteGroup(group.id)
        }
    }
}

/// A text field that commits on Return or when focus leaves (used for names other things refer to).
private struct CommitTextField: View {
    let title: String
    let value: String
    let onCommit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .focused($focused)
            .onAppear { text = value }
            .onChange(of: value) { _, newValue in
                if !focused { text = newValue }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onSubmit(commit)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            text = value
        } else if trimmed != value {
            onCommit(trimmed)
        }
    }
}

// MARK: - Combos

private struct ComboSettings: View {
    @ObservedObject var store: Store

    var body: some View {
        Form {
            ForEach(store.data.combos) { combo in
                let rendered = store.render(combo, now: Date())
                Section {
                    TextField("Template", text: store.comboBinding(combo.id), axis: .vertical)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Pastes") {
                        Text(rendered.text)
                            .foregroundStyle(rendered.isComplete ? Color.primary : Color.orange)
                            .textSelection(.enabled)
                    }
                    if !rendered.isComplete {
                        Text(rendered.problems.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        insertMenu(combo)
                        Spacer()
                        Button("Delete", role: .destructive) { store.deleteCombo(combo.id) }
                    }
                }
            }
            Section {
                Button("Add Combo") { store.addCombo() }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Write any text and put fields in braces:")
                    Text("{Sermon Title: Last Week}   {Sermon Title: This Week}")
                    Text("{Last Sunday: MMMM d}   {Today: MM-dd-yy}   {Coming Sunday: M/d/yy}")
                    Text("Date patterns work like the Date Formats tab. Example: {Sermon Title: Last Week} – {Last Sunday: MMMM d}")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func insertMenu(_ combo: Combo) -> some View {
        let binding = store.comboBinding(combo.id)
        return Menu("Insert Field") {
            ForEach(store.data.groups) { group in
                Section(group.name) {
                    ForEach(WeekSlot.allCases) { slot in
                        Button(slot.label) {
                            binding.wrappedValue += TemplateEngine.field(group: group.name, slot: slot)
                        }
                    }
                }
            }
            ForEach(DateAnchor.allCases) { anchor in
                Section(anchor.title) {
                    ForEach(store.data.dateFormats) { format in
                        let example = DateText.format(anchor.date(now: Date(), clock: store.data.settings.clock), pattern: format.pattern)
                        Button(example) {
                            binding.wrappedValue += TemplateEngine.field(anchor: anchor, pattern: format.pattern)
                        }
                    }
                }
            }
        }
        .fixedSize()
    }
}

// MARK: - Date formats

private struct DateSettings: View {
    @ObservedObject var store: Store

    private let presets = [
        "MMMM d", "MMM d", "MMMM d, yyyy", "MMM d, yyyy", "EEEE, MMMM d", "EEEE, MMMM d, yyyy",
        "MM-dd-yy", "M/d/yy", "MM/dd/yyyy", "yyyy-MM-dd", "M.d.yy", "d MMMM yyyy",
    ]

    var body: some View {
        let clock = store.data.settings.clock
        let lastSunday = clock.lastSunday(now: Date())

        Form {
            Section("Rows in the panel's date grid") {
                ForEach(Array(store.data.dateFormats.enumerated()), id: \.element.id) { index, format in
                    HStack(spacing: 10) {
                        TextField("Pattern", text: store.formatBinding(format.id))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 200)
                        Text(DateText.format(lastSunday, pattern: format.pattern, calendar: clock.calendar))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button { store.moveFormat(format.id, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                        Button { store.moveFormat(format.id, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(index == store.data.dateFormats.count - 1)
                        Button(role: .destructive) { store.deleteFormat(format.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Menu("Add Format") {
                    ForEach(presets, id: \.self) { pattern in
                        Button("\(DateText.format(lastSunday, pattern: pattern, calendar: clock.calendar))   (\(pattern))") {
                            store.addFormat(pattern)
                        }
                    }
                    Divider()
                    Button("Custom…") { store.addFormat("MMMM d") }
                }
                .fixedSize()
            }

            Section("Pattern letters") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                    patternRow("MMMM", "November", "MMM", "Nov")
                    patternRow("MM", "11 (zero-padded)", "M", "11")
                    patternRow("dd", "01 (zero-padded)", "d", "1")
                    patternRow("yyyy", "2026", "yy", "26")
                    patternRow("EEEE", "Sunday", "EEE", "Sun")
                }
                .font(.caption)
                Text("Anything else (spaces, dashes, commas, slashes) is copied as-is. Put plain words in single quotes, e.g. 'Week of' MMMM d.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func patternRow(_ a: String, _ aMeaning: String, _ b: String, _ bMeaning: String) -> some View {
        GridRow {
            Text(a).font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
            Text(aMeaning).foregroundStyle(.secondary)
            Text(b).font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
            Text(bMeaning).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Scratch

private struct ScratchSettings: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.data.scratches.isEmpty {
                ContentUnavailableView(
                    "No scratch clipboards yet",
                    systemImage: "doc.on.clipboard",
                    description: Text("Add one here, or press Option+Space and click “+ New scratch”. You can also drop text or images onto it.")
                )
            } else {
                List {
                    ForEach(store.data.scratches) { scratch in
                        ScratchRow(store: store, scratch: scratch)
                    }
                    .onMove { store.moveScratch(from: $0, to: $1) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            HStack {
                Button("New Text Scratch") {
                    let id = store.addScratch(nil, pinned: true)
                    Editors.editScratch(id, store: store)
                }
                Button("New from Clipboard") {
                    if let clip = Clipboard.read(.general) {
                        store.addScratch(clip, pinned: true)
                    } else {
                        NSSound.beep()
                    }
                }
                Spacer()
                Text("Drag rows to reorder. Pinned ones always show in the panel; the rest are under “More”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }
}

private struct ScratchRow: View {
    @ObservedObject var store: Store
    let scratch: Scratch

    var body: some View {
        HStack(spacing: 10) {
            if let file = scratch.content.imageFile, let image = store.image(file) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: scratch.content.isEmpty ? "square.dashed" : "doc.plaintext")
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name (optional)", text: store.scratchNameBinding(scratch.id))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                Text(scratch.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("Pinned", isOn: store.scratchPinnedBinding(scratch.id))
                .toggleStyle(.checkbox)
            Button("Edit…") { Editors.editScratch(scratch.id, store: store) }
            Button(role: .destructive) { store.deleteScratch(scratch.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
    }
}
