import AppKit
import NatkeysCore
import SwiftUI

private struct SizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Root of the panel: reports its size so the window can grow downward.
struct PanelRoot: View {
    @ObservedObject var store: Store
    @ObservedObject var session: PanelSession
    let controller: PanelController
    let onSize: (CGSize) -> Void

    var body: some View {
        PanelView(store: store, session: session, controller: controller)
            .background(GeometryReader { geo in Color.clear.preference(key: SizeKey.self, value: geo.size) })
            .onPreferenceChange(SizeKey.self) { size in
                MainActor.assumeIsolated { onSize(size) }
            }
    }
}

struct PanelView: View {
    static let width: CGFloat = 500

    @ObservedObject var store: Store
    @ObservedObject var session: PanelSession
    let controller: PanelController

    private var clock: WeekClock { store.data.settings.clock }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if session.selection != nil || session.clipboard != nil {
                sources
            }
            ForEach(store.data.groups) { group in
                PanelDivider()
                groupSection(group)
            }
            if !store.data.combos.isEmpty {
                PanelDivider()
                combosSection
            }
            if !store.data.dateFormats.isEmpty {
                PanelDivider()
                datesSection
            }
            PanelDivider()
            scratchSection
        }
        .padding(12)
        .frame(width: PanelView.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
            Text("Natkeys")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !session.trusted {
                Button {
                    controller.openAccessibility()
                } label: {
                    Label("Allow auto-paste…", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
                .help("Natkeys needs Accessibility access to read selections and paste for you.")
            }
            Button {
                controller.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Natkeys Settings")
        }
        .padding(.horizontal, 4)
    }

    // MARK: Selection / clipboard chips

    private var sources: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let selection = session.selection {
                    SourceChip(title: "Selection", clip: selection, armed: session.armed == .selection) {
                        session.toggleArm(.selection)
                    }
                }
                if let clipboard = session.clipboard {
                    SourceChip(title: "Clipboard", clip: clipboard, armed: session.armed == .clipboard) {
                        session.toggleArm(.clipboard)
                    }
                }
                Spacer(minLength: 0)
            }
            Group {
                if let armed = session.armedClip {
                    Text(armed.isImage
                         ? "Click Save on a scratch slot (or +) to keep this image."
                         : "Click Save on any slot below to keep this text.")
                } else {
                    Text("Click a chip to save it into a slot.")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    // MARK: Weekly groups

    private func groupSection(_ group: RotatingGroup) -> some View {
        VStack(alignment: .leading, spacing: group.kind == .image ? 4 : 2) {
            SectionHeader(title: group.name) {
                Button {
                    controller.shift(group.id)
                } label: {
                    Label("Shift This → Last", systemImage: group.kind == .image ? "arrow.left.to.line" : "arrow.down.to.line")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(!group.canShift)
                .help("Move This Week's \(group.name.lowercased()) into Last Week. Happens automatically Sundays at \(store.data.settings.flipTimeDescription).")
            }
            switch group.kind {
            case .text:
                ForEach(WeekSlot.allCases) { slot in
                    slotRow(group, slot)
                }
            case .image:
                // Side by side, in time order: Last Week on the left, This Week on the right.
                HStack(spacing: 8) {
                    ImageSlotTile(group: group, slot: .lastWeek, store: store, session: session, controller: controller)
                    ImageSlotTile(group: group, slot: .thisWeek, store: store, session: session, controller: controller)
                }
            }
        }
    }

    private func slotRow(_ group: RotatingGroup, _ slot: WeekSlot) -> some View {
        let value = group[slot]
        return HStack(spacing: 6) {
            Button {
                controller.pasteSlot(group, slot)
            } label: {
                HStack(spacing: 8) {
                    Text(slot.label)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    if value.isEmpty {
                        Text("empty, click to type")
                            .italic()
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(value)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13))
            }
            .buttonStyle(RowButtonStyle())
            .help(value.isEmpty ? "" : "Paste “\(value)”")
            .menuActions(slotMenu(group, slot))

            if session.armedText != nil {
                SaveButton { controller.saveArmed(group: group.id, slot: slot) }
            }
        }
    }

    private func slotMenu(_ group: RotatingGroup, _ slot: WeekSlot) -> [MenuAction] {
        let value = group[slot]
        var items: [MenuAction] = []
        if !value.isEmpty {
            items.append(MenuAction(title: "Paste") { controller.pasteText(value) })
            items.append(MenuAction(title: "Copy") { controller.copy(.text(value)) })
            items.append(.separator)
        }
        items.append(MenuAction(title: "Edit…") { controller.edit(group: group.id, slot: slot) })
        if let clip = session.clipboard?.text {
            items.append(MenuAction(title: "Replace with Clipboard") { controller.store.setSlot(group.id, slot, to: clip) })
        }
        if !value.isEmpty {
            items.append(MenuAction(title: "Clear", destructive: true) { controller.clearSlot(group.id, slot) })
        }
        items.append(.separator)
        items.append(MenuAction(title: "Weekly Group Settings…") { controller.openSettings(.weekly) })
        return items
    }

    // MARK: Combos

    private var combosSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Combos") { EmptyView() }
            ForEach(store.data.combos) { combo in
                let rendered = store.render(combo, now: session.now)
                Button {
                    controller.pasteCombo(rendered)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.append")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(rendered.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(rendered.isComplete ? .primary : .secondary)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13))
                }
                .buttonStyle(RowButtonStyle())
                .help(rendered.isComplete ? "Paste “\(rendered.text)”" : rendered.problems.joined(separator: "\n"))
                .menuActions([
                    MenuAction(title: "Copy") { controller.copy(.text(rendered.text)) },
                    .separator,
                    MenuAction(title: "Edit Combos…") { controller.openSettings(.combos) },
                ])
            }
        }
    }

    // MARK: Dates

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Dates") { EmptyView() }
            Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 3) {
                GridRow {
                    ForEach(DateAnchor.allCases) { anchor in
                        Text(anchor.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                    }
                }
                ForEach(store.data.dateFormats) { format in
                    GridRow {
                        ForEach(DateAnchor.allCases) { anchor in
                            let text = DateText.format(
                                anchor.date(now: session.now, clock: clock),
                                pattern: format.pattern,
                                calendar: clock.calendar
                            )
                            Button {
                                controller.pasteText(text)
                            } label: {
                                Text(text)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .buttonStyle(CellButtonStyle())
                            .help("Paste “\(text)”")
                            .menuActions([
                                MenuAction(title: "Copy") { controller.copy(.text(text)) },
                                .separator,
                                MenuAction(title: "Edit Date Formats…") { controller.openSettings(.dates) },
                            ])
                        }
                    }
                }
            }
        }
    }

    // MARK: Scratch

    private var scratchColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
    }

    private var scratchSection: some View {
        let pinned = store.data.scratches.filter(\.pinned)
        let others = store.data.scratches.filter { !$0.pinned }

        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Scratch") { EmptyView() }
            LazyVGrid(columns: scratchColumns, spacing: 6) {
                ForEach(pinned) { scratch in
                    ScratchTile(scratch: scratch, store: store, session: session, controller: controller)
                }
                NewScratchTile(session: session, controller: controller)
            }
            if !others.isEmpty {
                Button {
                    session.showMore.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: session.showMore ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 12)
                        Text("More scratch (\(others.count))")
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(RowButtonStyle())

                if session.showMore {
                    let rows = (others.count + 1) / 2
                    let height = min(CGFloat(rows) * ScratchTile.height + CGFloat(max(rows - 1, 0)) * 6, 200)
                    ScrollView {
                        LazyVGrid(columns: scratchColumns, spacing: 6) {
                            ForEach(others) { scratch in
                                ScratchTile(scratch: scratch, store: store, session: session, controller: controller)
                            }
                        }
                    }
                    .frame(height: height)
                }
            }
        }
    }
}

// MARK: - Pieces

private struct PanelDivider: View {
    var body: some View {
        Divider().opacity(0.6)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            trailing
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 18)
    }
}

struct SaveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Save", systemImage: "square.and.arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help("Save here")
    }
}

private struct SourceChip: View {
    let title: String
    let clip: Clip
    let armed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: armed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(armed ? Color.accentColor : Color.secondary)
                Text(title)
                    .fontWeight(.semibold)
                switch clip {
                case .image(let data, _):
                    if let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(clip.preview).foregroundStyle(.secondary)
                case .text:
                    Text("“\(clip.preview)”")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(maxWidth: 232, alignment: .leading)
            .background(Capsule().fill(armed ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.07)))
            .overlay(Capsule().strokeBorder(armed ? Color.accentColor.opacity(0.6) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(armed ? "Saving this. Click to turn off." : "Click to save this into a slot")
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(configuration.isPressed ? 0.35 : (hovering && isEnabled ? 0.16 : 0)))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct CellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CellBody(configuration: configuration)
    }

    private struct CellBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(configuration.isPressed
                              ? Color.accentColor.opacity(0.35)
                              : (hovering ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05)))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct ScratchTile: View {
    static let height: CGFloat = 44

    let scratch: Scratch
    @ObservedObject var store: Store
    @ObservedObject var session: PanelSession
    let controller: PanelController

    @State private var hovering = false
    @State private var dropTarget = false

    private var thumbnail: NSImage? {
        scratch.content.imageFile.flatMap { store.image($0) }
    }

    private var hasName: Bool {
        !scratch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(scratch.content.isEmpty && !hasName ? "Empty scratch" : scratch.displayTitle)
                        .font(.system(size: 12, weight: hasName ? .semibold : .regular))
                        .italic(scratch.content.isEmpty && !hasName)
                        .foregroundStyle(scratch.content.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    if hasName {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(
                TileInteraction(
                    onClick: { controller.pasteScratch(scratch) },
                    dragPayload: dragPayload,
                    menu: { menu },
                    onDrop: { clip in controller.dropped(clip, on: scratch.id) },
                    onHover: { hovering = $0 },
                    onDropTarget: { dropTarget = $0 },
                    onDragBegan: { controller.dragOutBegan() },
                    onDragEnded: { controller.dragOutEnded(dropped: $0) }
                )
            )

            if session.armedClip != nil {
                SaveButton { controller.saveArmed(scratch: scratch.id) }
                    .padding(.trailing, 6)
            }
        }
        .frame(height: ScratchTile.height)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(dropTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .help(helpText)
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: scratch.content.isEmpty ? "square.dashed" : "doc.plaintext")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
    }

    private var subtitle: String {
        switch scratch.content {
        case .empty: return "Empty"
        case .image:
            if let thumbnail, let rep = thumbnail.representations.first {
                return "Image \(rep.pixelsWide)×\(rep.pixelsHigh)"
            }
            return "Image"
        case .text: return scratch.preview
        }
    }

    private var helpText: String {
        switch scratch.content {
        case .empty: return "Empty. Click to type, or drop text or an image here."
        case .image: return "Click to paste the image, or drag it into a website or document."
        case .text(let text): return "Click to paste: \(text.prefix(200))"
        }
    }

    private var dragPayload: (() -> DragPayload?)? {
        switch scratch.content {
        case .empty:
            return nil
        case .image:
            return {
                guard let url = store.dragFileURL(for: scratch), let image = NSImage(contentsOf: url) else { return nil }
                return DragPayload(writer: url as NSURL, image: DragImages.forImage(image))
            }
        case .text(let text):
            return { DragPayload(writer: text as NSString, image: DragImages.forText(text)) }
        }
    }

    private var menu: [MenuAction] {
        var items: [MenuAction] = []
        if !scratch.content.isEmpty {
            items.append(MenuAction(title: "Paste") { controller.pasteScratch(scratch) })
            items.append(MenuAction(title: "Copy") { controller.copyScratch(scratch) })
            items.append(.separator)
        }
        items.append(MenuAction(title: scratch.content.imageFile == nil ? "Edit…" : "Rename…") { controller.edit(scratch: scratch.id) })
        items.append(MenuAction(title: scratch.pinned ? "Unpin" : "Pin") { controller.togglePin(scratch.id) })
        if session.clipboard != nil || Clipboard.read(.general) != nil {
            items.append(MenuAction(title: "Replace with Clipboard") { controller.replaceWithClipboard(scratch.id) })
        }
        items.append(.separator)
        items.append(MenuAction(title: "Delete", destructive: true) { controller.deleteScratch(scratch.id) })
        return items
    }
}

/// One slot of an image weekly group: a thumbnail you can click to paste, drag out to a
/// website's upload box, or drop a new image onto.
struct ImageSlotTile: View {
    static let height: CGFloat = 58

    let group: RotatingGroup
    let slot: WeekSlot
    @ObservedObject var store: Store
    @ObservedObject var session: PanelSession
    let controller: PanelController

    @State private var hovering = false
    @State private var dropTarget = false

    private var image: GroupImage? { group[image: slot] }

    private var preview: (image: NSImage, pixelSize: CGSize)? {
        image.flatMap { store.thumbnail($0.file) }
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    if let image {
                        Text((store.displayName(of: image, in: group) as NSString).deletingPathExtension)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(details(image))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Drag image here")
                            .font(.system(size: 12))
                            .italic()
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 7)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(
                TileInteraction(
                    onClick: { controller.pasteSlot(group, slot) },
                    dragPayload: dragPayload,
                    menu: { menu },
                    onDrop: { clip in controller.dropped(clip, onImageSlot: slot, of: group.id) },
                    onHover: { hovering = $0 },
                    onDropTarget: { dropTarget = $0 },
                    onDragBegan: { controller.dragOutBegan() },
                    onDragEnded: { controller.dragOutEnded(dropped: $0) }
                )
            )

            if session.armedIsImage {
                SaveButton { controller.saveArmed(group: group.id, slot: slot) }
                    .padding(.trailing, 6)
            }
        }
        .frame(height: ImageSlotTile.height)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? Color.accentColor.opacity(0.16) : Color.primary.opacity(image == nil ? 0.02 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    dropTarget ? Color.accentColor : (image == nil ? Color.secondary.opacity(0.45) : Color.clear),
                    style: StrokeStyle(lineWidth: dropTarget ? 2 : 1, dash: dropTarget || image != nil ? [] : [4, 3])
                )
        )
        .help(helpText)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let preview {
            Image(nsImage: preview.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 72, maxHeight: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.12)))
                .frame(width: 72, height: 44)
        } else {
            Image(systemName: image == nil ? "photo.badge.plus" : "exclamationmark.triangle")
                .font(.system(size: 18))
                .foregroundStyle(.tertiary)
                .frame(width: 72, height: 44)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
        }
    }

    private func details(_ image: GroupImage) -> String {
        let type = URL(fileURLWithPath: image.file).pathExtension.uppercased()
        guard let size = preview?.pixelSize else { return type.isEmpty ? "Image" : type }
        return "\(Int(size.width))×\(Int(size.height)) · \(type)"
    }

    private var helpText: String {
        if image == nil {
            return "Drop an image here, or click to choose a file."
        }
        return "Drag into a website's upload box or a document. Click to paste. Drop another image to replace it."
    }

    private var dragPayload: (() -> DragPayload?)? {
        guard let image else { return nil }
        return {
            guard let url = store.dragFileURL(for: image, in: group) else { return nil }
            let picture = store.thumbnail(image.file)?.image ?? NSImage(contentsOf: url) ?? NSImage()
            return DragPayload(writer: url as NSURL, image: DragImages.forImage(picture))
        }
    }

    private var menu: [MenuAction] {
        var items: [MenuAction] = []
        if image != nil {
            items.append(MenuAction(title: "Paste") { controller.pasteSlot(group, slot) })
            items.append(MenuAction(title: "Copy") { controller.copySlotImage(group, slot) })
            items.append(MenuAction(title: "Show in Finder") { controller.revealSlotImage(group, slot) })
            items.append(.separator)
        }
        items.append(MenuAction(title: image == nil ? "Choose Image…" : "Replace with File…") {
            controller.edit(group: group.id, slot: slot)
        })
        if session.clipboard?.isImage == true {
            items.append(MenuAction(title: "Replace with Clipboard") {
                controller.replaceSlotImageWithClipboard(group.id, slot)
            })
        }
        if image != nil {
            items.append(MenuAction(title: "Clear", destructive: true) { controller.clearSlot(group.id, slot) })
        }
        items.append(.separator)
        items.append(MenuAction(title: "Weekly Group Settings…") { controller.openSettings(.weekly) })
        return items
    }
}

private struct NewScratchTile: View {
    @ObservedObject var session: PanelSession
    let controller: PanelController

    @State private var hovering = false
    @State private var dropTarget = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
            Text(session.armedClip != nil ? "Save as new scratch" : "New scratch")
                .font(.system(size: 12))
            Spacer(minLength: 0)
        }
        .foregroundStyle(session.armedClip != nil ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 10)
        .frame(height: ScratchTile.height)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    dropTarget ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: dropTarget ? 2 : 1, dash: dropTarget ? [] : [4, 3])
                )
        )
        .overlay(
            TileInteraction(
                onClick: { controller.newScratchTapped() },
                dragPayload: nil,
                menu: { [] },
                onDrop: { clip in controller.dropped(clip, on: nil) },
                onHover: { hovering = $0 },
                onDropTarget: { dropTarget = $0 }
            )
        )
        .help("Click to add a scratch clipboard, or drop text or an image here")
    }
}
