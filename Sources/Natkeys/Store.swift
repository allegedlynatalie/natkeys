import AppKit
import Combine
import NatkeysCore
import SwiftUI

/// Owns all Natkeys data and saves it to ~/Library/Application Support/Natkeys.
@MainActor
final class Store: ObservableObject {
    @Published var data: AppData

    let folder: URL
    let imagesFolder: URL
    private let dataURL: URL
    private var saveSubscription: AnyCancellable?
    private var imageCache: [String: NSImage] = [:]
    private var thumbnailCache: [String: (image: NSImage, pixelSize: CGSize)] = [:]
    private(set) var isFirstLaunch = false
    /// data.json couldn't be read this run, so unused-image cleanup is off (the images may
    /// belong to the unreadable file).
    private var loadFailed = false

    /// `folder` defaults to ~/Library/Application Support/Natkeys (snapshots use a temp folder).
    init(folder customFolder: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = customFolder ?? support.appendingPathComponent("Natkeys", isDirectory: true)
        imagesFolder = folder.appendingPathComponent("Images", isDirectory: true)
        dataURL = folder.appendingPathComponent("data.json")
        try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)

        data = AppData.defaults()
        load()

        saveSubscription = $data
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveNow() }
    }

    // MARK: Persistence

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataURL.path) else {
            isFirstLaunch = true
            saveNow()
            return
        }
        do {
            data = try Store.decoder.decode(AppData.self, from: Data(contentsOf: dataURL))
        } catch {
            // Keep the unreadable file for recovery instead of overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = folder.appendingPathComponent("data-unreadable-\(stamp).json")
            try? fm.moveItem(at: dataURL, to: backup)
            loadFailed = true
            Log.info("could not read data.json (\(error)); moved it to \(backup.lastPathComponent)")
        }
    }

    func saveNow() {
        do {
            let bytes = try Store.encoder.encode(data)
            try bytes.write(to: dataURL, options: .atomic)
        } catch {
            Log.info("failed to save data: \(error)")
        }
    }

    // MARK: Weekly groups

    func group(_ id: UUID) -> RotatingGroup? {
        data.groups.first { $0.id == id }
    }

    func setSlot(_ groupID: UUID, _ slot: WeekSlot, to text: String) {
        guard let index = data.groups.firstIndex(where: { $0.id == groupID }) else { return }
        data.groups[index][slot] = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shift(_ groupID: UUID) {
        AutoShift.manualShift(&data, groupID: groupID, now: Date())
        removeUnusedImages()
    }

    func shiftAll() {
        let now = Date()
        for group in data.groups where group.canShift {
            AutoShift.manualShift(&data, groupID: group.id, now: now)
        }
        removeUnusedImages()
    }

    @discardableResult
    func runAutoShift(now: Date = Date()) -> [String] {
        var copy = data
        let shifted = AutoShift.run(&copy, now: now)
        if copy != data { data = copy }
        if !shifted.isEmpty { removeUnusedImages() }
        return shifted
    }

    /// Switches a group between text and image. When it becomes an image group, a slot whose
    /// text is the path of an image file (what dropping a file into a text box gives you) gets
    /// that image. The text itself is kept, so switching back loses nothing.
    func setKind(_ groupID: UUID, _ kind: GroupKind) {
        guard let index = data.groups.firstIndex(where: { $0.id == groupID }),
              data.groups[index].kind != kind else { return }
        data.groups[index].kind = kind
        guard kind == .image else { return }
        for slot in WeekSlot.allCases where data.groups[index][image: slot] == nil {
            if let url = ImageFiles.imageFile(fromPath: data.groups[index][slot]) {
                setSlotImage(groupID, slot, fromFile: url)
            }
        }
    }

    // MARK: Weekly group images

    /// Saves an image clip (or text naming an image file) into a slot. Returns false if it
    /// isn't an image.
    @discardableResult
    func setSlotImage(_ groupID: UUID, _ slot: WeekSlot, to clip: Clip) -> Bool {
        switch clip {
        case .image(let png, let source):
            if let source, setSlotImage(groupID, slot, fromFile: source) { return true }
            return setSlotImage(groupID, slot, png: png)
        case .text(let text):
            guard let url = ImageFiles.imageFile(fromPath: text) else { return false }
            return setSlotImage(groupID, slot, fromFile: url)
        }
    }

    /// Copies the file as it is, so a JPG stays a JPG (and stays under websites' upload limits).
    @discardableResult
    func setSlotImage(_ groupID: UUID, _ slot: WeekSlot, fromFile url: URL) -> Bool {
        guard ImageFiles.isImageFile(url), let bytes = try? Data(contentsOf: url) else { return false }
        let ext = url.pathExtension.lowercased()
        return storeSlotImage(groupID, slot, bytes: bytes, fileExtension: ext.isEmpty ? "png" : ext, name: url.lastPathComponent)
    }

    @discardableResult
    func setSlotImage(_ groupID: UUID, _ slot: WeekSlot, png: Data) -> Bool {
        storeSlotImage(groupID, slot, bytes: png, fileExtension: "png", name: "")
    }

    private func storeSlotImage(_ groupID: UUID, _ slot: WeekSlot, bytes: Data, fileExtension: String, name: String) -> Bool {
        guard let index = data.groups.firstIndex(where: { $0.id == groupID }) else { return false }
        let file = UUID().uuidString + "." + fileExtension
        do {
            try bytes.write(to: imageURL(file), options: .atomic)
        } catch {
            Log.info("failed to save group image: \(error)")
            return false
        }
        data.groups[index][image: slot] = GroupImage(file: file, name: name)
        removeUnusedImages()
        return true
    }

    /// Empties a slot (text or image, depending on the group).
    func clearSlot(_ groupID: UUID, _ slot: WeekSlot) {
        guard let index = data.groups.firstIndex(where: { $0.id == groupID }) else { return }
        switch data.groups[index].kind {
        case .text:
            data.groups[index][slot] = ""
        case .image:
            data.groups[index][image: slot] = nil
            removeUnusedImages()
        }
    }

    /// A slot's image in pasteable form.
    func clip(for image: GroupImage) -> Clip? {
        let url = imageURL(image.file)
        guard let png = ImageFiles.pngData(at: url) else { return nil }
        return .image(png, source: url)
    }

    /// The name a slot's image is shown and dragged out under, e.g. "Narrow Gate.jpg".
    func displayName(of image: GroupImage, in group: RotatingGroup) -> String {
        let name = image.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return group.name + "." + (URL(fileURLWithPath: image.file).pathExtension)
    }

    func addGroup() {
        var name = "New Group"
        var n = 2
        while data.groups.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            name = "New Group \(n)"
            n += 1
        }
        data.groups.append(RotatingGroup(name: name))
    }

    func renameGroup(_ id: UUID, to rawName: String) {
        let newName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, let index = data.groups.firstIndex(where: { $0.id == id }) else { return }
        let oldName = data.groups[index].name
        guard oldName != newName else { return }
        data.groups[index].name = newName
        for i in data.combos.indices {
            data.combos[i].template = TemplateEngine.renameGroup(in: data.combos[i].template, from: oldName, to: newName)
        }
    }

    func deleteGroup(_ id: UUID) {
        data.groups.removeAll { $0.id == id }
        removeUnusedImages()
    }

    func groupBinding(_ id: UUID) -> Binding<RotatingGroup> {
        Binding(
            get: { self.data.groups.first { $0.id == id } ?? RotatingGroup(id: id, name: "") },
            set: { newValue in
                if let i = self.data.groups.firstIndex(where: { $0.id == id }) { self.data.groups[i] = newValue }
            }
        )
    }

    // MARK: Combos

    func addCombo(template: String = "{Sermon Title: Last Week} – {Last Sunday: MMMM d}") {
        data.combos.append(Combo(template: template))
    }

    func deleteCombo(_ id: UUID) {
        data.combos.removeAll { $0.id == id }
    }

    func comboBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { self.data.combos.first { $0.id == id }?.template ?? "" },
            set: { newValue in
                if let i = self.data.combos.firstIndex(where: { $0.id == id }) { self.data.combos[i].template = newValue }
            }
        )
    }

    func render(_ combo: Combo, now: Date) -> RenderedTemplate {
        TemplateEngine.render(combo.template, groups: data.groups, clock: data.settings.clock, now: now)
    }

    // MARK: Date formats

    func addFormat(_ pattern: String) {
        data.dateFormats.append(DateFormatSpec(pattern: pattern))
    }

    func deleteFormat(_ id: UUID) {
        data.dateFormats.removeAll { $0.id == id }
    }

    func moveFormat(_ id: UUID, by offset: Int) {
        guard let i = data.dateFormats.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard data.dateFormats.indices.contains(j) else { return }
        data.dateFormats.swapAt(i, j)
    }

    func formatBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { self.data.dateFormats.first { $0.id == id }?.pattern ?? "" },
            set: { newValue in
                if let i = self.data.dateFormats.firstIndex(where: { $0.id == id }) { self.data.dateFormats[i].pattern = newValue }
            }
        )
    }

    // MARK: Scratch clipboards

    func scratch(_ id: UUID) -> Scratch? {
        data.scratches.first { $0.id == id }
    }

    @discardableResult
    func addScratch(_ clip: Clip?, name: String = "", pinned: Bool = false) -> UUID {
        let scratch = Scratch(name: name, content: clip.map(content(for:)) ?? .empty, pinned: pinned)
        data.scratches.append(scratch)
        return scratch.id
    }

    func setScratch(_ id: UUID, to clip: Clip) {
        guard let i = data.scratches.firstIndex(where: { $0.id == id }) else { return }
        let old = data.scratches[i].content
        data.scratches[i].content = content(for: clip)
        data.scratches[i].updatedAt = Date()
        removeImageFile(of: old)
    }

    func updateScratch(_ id: UUID, name: String, text: String?) {
        guard let i = data.scratches.firstIndex(where: { $0.id == id }) else { return }
        data.scratches[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text {
            let old = data.scratches[i].content
            data.scratches[i].content = text.isEmpty ? .empty : .text(text)
            removeImageFile(of: old)
        }
        data.scratches[i].updatedAt = Date()
    }

    func togglePin(_ id: UUID) {
        guard let i = data.scratches.firstIndex(where: { $0.id == id }) else { return }
        data.scratches[i].pinned.toggle()
    }

    func deleteScratch(_ id: UUID) {
        guard let i = data.scratches.firstIndex(where: { $0.id == id }) else { return }
        let removed = data.scratches.remove(at: i)
        removeImageFile(of: removed.content)
    }

    func moveScratch(from source: IndexSet, to destination: Int) {
        data.scratches.move(fromOffsets: source, toOffset: destination)
    }

    func scratchNameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { self.data.scratches.first { $0.id == id }?.name ?? "" },
            set: { newValue in
                if let i = self.data.scratches.firstIndex(where: { $0.id == id }) { self.data.scratches[i].name = newValue }
            }
        )
    }

    func scratchPinnedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.data.scratches.first { $0.id == id }?.pinned ?? false },
            set: { newValue in
                if let i = self.data.scratches.firstIndex(where: { $0.id == id }) { self.data.scratches[i].pinned = newValue }
            }
        )
    }

    /// The scratch's contents in pasteable form.
    func clip(for scratch: Scratch) -> Clip? {
        switch scratch.content {
        case .empty:
            return nil
        case .text(let text):
            return .text(text)
        case .image(let file):
            guard let data = try? Data(contentsOf: imageURL(file)) else { return nil }
            return .image(data)
        }
    }

    // MARK: Images

    func imageURL(_ file: String) -> URL {
        imagesFolder.appendingPathComponent(file)
    }

    func image(_ file: String) -> NSImage? {
        if let cached = imageCache[file] { return cached }
        guard let image = NSImage(contentsOf: imageURL(file)) else { return nil }
        imageCache[file] = image
        return image
    }

    /// Small preview and pixel size of a stored image (cached).
    func thumbnail(_ file: String) -> (image: NSImage, pixelSize: CGSize)? {
        if let cached = thumbnailCache[file] { return cached }
        guard let made = ImageFiles.thumbnail(at: imageURL(file)) else { return nil }
        thumbnailCache[file] = made
        return made
    }

    /// A copy of the image named after the scratch, so websites see "Logo.png" instead of a UUID.
    func dragFileURL(for scratch: Scratch) -> URL? {
        guard let file = scratch.content.imageFile else { return nil }
        return dragFileURL(file: file, name: scratch.name + ".png")
    }

    /// A copy of a slot's image under its original name, e.g. "Narrow Gate.jpg".
    func dragFileURL(for image: GroupImage, in group: RotatingGroup) -> URL? {
        dragFileURL(file: image.file, name: displayName(of: image, in: group))
    }

    private func dragFileURL(file: String, name: String) -> URL? {
        let source = imageURL(file)
        let dragFolder = FileManager.default.temporaryDirectory.appendingPathComponent("NatkeysDrag", isDirectory: true)
        try? FileManager.default.createDirectory(at: dragFolder, withIntermediateDirectories: true)
        var base = (name as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
        if base.isEmpty { base = "Natkeys Image" }
        let destination = dragFolder.appendingPathComponent(base + "." + source.pathExtension)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return source
        }
    }

    /// Deletes files in the Images folder that nothing uses any more (for example last week's
    /// graphic after a shift). Saves first, so data.json never points at a deleted file.
    func removeUnusedImages() {
        guard !loadFailed else { return }
        saveNow()
        let used = data.referencedImageFiles
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: imagesFolder.path) else { return }
        for file in files where !used.contains(file) && !file.hasPrefix(".") {
            try? fm.removeItem(at: imageURL(file))
            imageCache[file] = nil
            thumbnailCache[file] = nil
        }
    }

    private func content(for clip: Clip) -> ScratchContent {
        switch clip {
        case .text(let text):
            // Drop the trailing newline that triple-click selections often include.
            var trimmed = text
            while let last = trimmed.last, last.isNewline { trimmed.removeLast() }
            return trimmed.isEmpty ? .empty : .text(trimmed)
        case .image(let png, _):
            let file = UUID().uuidString + ".png"
            do {
                try png.write(to: imageURL(file), options: .atomic)
                return .image(file: file)
            } catch {
                Log.info("failed to save image: \(error)")
                return .empty
            }
        }
    }

    private func removeImageFile(of content: ScratchContent) {
        guard let file = content.imageFile else { return }
        imageCache[file] = nil
        thumbnailCache[file] = nil
        try? FileManager.default.removeItem(at: imageURL(file))
    }

    // MARK: Backup

    private struct Backup: Codable {
        var format = "natkeys-backup"
        var version = 1
        var exportedAt: Date
        var data: AppData
        var images: [String: Data]
    }

    func exportBackup(to url: URL) throws {
        var images: [String: Data] = [:]
        for file in data.referencedImageFiles {
            if let bytes = try? Data(contentsOf: imageURL(file)) {
                images[file] = bytes
            }
        }
        let backup = Backup(exportedAt: Date(), data: data, images: images)
        try Store.encoder.encode(backup).write(to: url, options: .atomic)
    }

    func importBackup(from url: URL) throws {
        let backup = try Store.decoder.decode(Backup.self, from: Data(contentsOf: url))
        guard backup.format == "natkeys-backup" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for (file, bytes) in backup.images {
            try bytes.write(to: imageURL(file), options: .atomic)
        }
        imageCache.removeAll()
        thumbnailCache.removeAll()
        data = backup.data
        saveNow()
        loadFailed = false
        removeUnusedImages()
    }
}
