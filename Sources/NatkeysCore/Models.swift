import Foundation

// MARK: - Weekly groups

/// One of the two slots in a weekly group.
public enum WeekSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case thisWeek
    case lastWeek

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .thisWeek: return "This Week"
        case .lastWeek: return "Last Week"
        }
    }

    /// Parses the slot part of a combo field, e.g. "Last Week" in `{Sermon Title: Last Week}`.
    public init?(tokenArgument raw: String) {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "this week", "this", "thisweek": self = .thisWeek
        case "last week", "last", "lastweek": self = .lastWeek
        default: return nil
        }
    }
}

/// A "This Week / Last Week" pair, e.g. Sermon Title. Shifting moves This Week into Last Week.
public struct RotatingGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var thisWeek: String
    public var lastWeek: String
    /// Whether the Sunday auto-shift applies to this group.
    public var autoShift: Bool
    /// Start of the Sunday whose weekly flip was already handled by a manual Shift,
    /// so the automatic shift for that Sunday is skipped (no double shift).
    public var manualShiftSunday: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        thisWeek: String = "",
        lastWeek: String = "",
        autoShift: Bool = true,
        manualShiftSunday: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.thisWeek = thisWeek
        self.lastWeek = lastWeek
        self.autoShift = autoShift
        self.manualShiftSunday = manualShiftSunday
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Group"
        thisWeek = try c.decodeIfPresent(String.self, forKey: .thisWeek) ?? ""
        lastWeek = try c.decodeIfPresent(String.self, forKey: .lastWeek) ?? ""
        autoShift = try c.decodeIfPresent(Bool.self, forKey: .autoShift) ?? true
        manualShiftSunday = try c.decodeIfPresent(Date.self, forKey: .manualShiftSunday)
    }

    public subscript(slot: WeekSlot) -> String {
        get { slot == .thisWeek ? thisWeek : lastWeek }
        set {
            switch slot {
            case .thisWeek: thisWeek = newValue
            case .lastWeek: lastWeek = newValue
            }
        }
    }

    /// Shifting an empty This Week would wipe Last Week, so it's not allowed.
    public var canShift: Bool {
        !thisWeek.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public mutating func shift() {
        lastWeek = thisWeek
        thisWeek = ""
    }
}

// MARK: - Combos

/// A one-click template such as `{Sermon Title: Last Week} – {Last Sunday: MMMM d}`.
public struct Combo: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var template: String

    public init(id: UUID = UUID(), template: String) {
        self.id = id
        self.template = template
    }
}

// MARK: - Date formats

/// A row in the date grid. `pattern` uses Unicode date pattern letters (MMMM d, MM-dd-yy, ...).
public struct DateFormatSpec: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var pattern: String

    public init(id: UUID = UUID(), pattern: String) {
        self.id = id
        self.pattern = pattern
    }
}

// MARK: - Scratch clipboards

public enum ScratchContent: Codable, Equatable, Sendable {
    case empty
    case text(String)
    /// File name of a PNG inside the app's Images folder.
    case image(file: String)

    public var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    public var imageFile: String? {
        if case .image(let file) = self { return file }
        return nil
    }
}

public struct Scratch: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Optional label. When empty, the panel shows a preview of the contents instead.
    public var name: String
    public var content: ScratchContent
    public var pinned: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "",
        content: ScratchContent = .empty,
        pinned: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.pinned = pinned
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        content = try c.decodeIfPresent(ScratchContent.self, forKey: .content) ?? .empty
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// One-line description of the contents, used when there's no name.
    public var preview: String {
        switch content {
        case .empty:
            return "Empty"
        case .image:
            return "Image"
        case .text(let text):
            let firstLine = text
                .split(whereSeparator: \.isNewline)
                .first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            return firstLine.isEmpty ? "Text" : firstLine
        }
    }

    public var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? preview : trimmed
    }
}

// MARK: - Settings

public struct AppSettings: Codable, Equatable, Sendable {
    /// Every Sunday at this time, weekly groups shift and the Last/Coming Sunday dates roll over.
    public var flipHour: Int
    public var flipMinute: Int
    /// Put the user's own clipboard back after Natkeys pastes.
    public var restoreClipboard: Bool
    public var launchAtLogin: Bool

    public init(flipHour: Int = 14, flipMinute: Int = 0, restoreClipboard: Bool = true, launchAtLogin: Bool = true) {
        self.flipHour = flipHour
        self.flipMinute = flipMinute
        self.restoreClipboard = restoreClipboard
        self.launchAtLogin = launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        flipHour = try c.decodeIfPresent(Int.self, forKey: .flipHour) ?? d.flipHour
        flipMinute = try c.decodeIfPresent(Int.self, forKey: .flipMinute) ?? d.flipMinute
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? d.restoreClipboard
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }

    public var clock: WeekClock {
        WeekClock(flipHour: flipHour, flipMinute: flipMinute)
    }

    public var flipTimeDescription: String {
        let hour12 = flipHour % 12 == 0 ? 12 : flipHour % 12
        let suffix = flipHour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, flipMinute, suffix)
    }
}

// MARK: - Everything

public struct AppData: Codable, Equatable, Sendable {
    public var version: Int
    public var groups: [RotatingGroup]
    public var combos: [Combo]
    public var dateFormats: [DateFormatSpec]
    public var scratches: [Scratch]
    public var settings: AppSettings
    /// The Sunday (start of day) whose auto-shift has already run.
    public var lastAutoShiftSunday: Date?

    public init(
        version: Int = 1,
        groups: [RotatingGroup],
        combos: [Combo],
        dateFormats: [DateFormatSpec],
        scratches: [Scratch],
        settings: AppSettings,
        lastAutoShiftSunday: Date? = nil
    ) {
        self.version = version
        self.groups = groups
        self.combos = combos
        self.dateFormats = dateFormats
        self.scratches = scratches
        self.settings = settings
        self.lastAutoShiftSunday = lastAutoShiftSunday
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppData.defaults()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        groups = try c.decodeIfPresent([RotatingGroup].self, forKey: .groups) ?? d.groups
        combos = try c.decodeIfPresent([Combo].self, forKey: .combos) ?? d.combos
        dateFormats = try c.decodeIfPresent([DateFormatSpec].self, forKey: .dateFormats) ?? d.dateFormats
        scratches = try c.decodeIfPresent([Scratch].self, forKey: .scratches) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        lastAutoShiftSunday = try c.decodeIfPresent(Date.self, forKey: .lastAutoShiftSunday)
    }

    public static let defaultDatePatterns = [
        "MMMM d",          // November 1
        "MM-dd-yy",        // 11-01-26
        "MMMM d, yyyy",    // November 1, 2026
        "M/d/yy",          // 11/1/26
        "EEEE, MMMM d",    // Sunday, November 1
    ]

    public static func defaults() -> AppData {
        AppData(
            groups: [RotatingGroup(name: "Sermon Title")],
            combos: [Combo(template: "{Sermon Title: Last Week} – {Last Sunday: MMMM d}")],
            dateFormats: defaultDatePatterns.map { DateFormatSpec(pattern: $0) },
            scratches: [],
            settings: AppSettings()
        )
    }
}
