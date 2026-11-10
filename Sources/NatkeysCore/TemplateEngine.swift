import Foundation

public struct RenderedTemplate: Equatable, Sendable {
    public var text: String
    /// Human-readable reasons the combo isn't ready, e.g. "Sermon Title · Last Week is empty".
    public var problems: [String]

    public var isComplete: Bool { problems.isEmpty }
}

/// Renders combo templates. Fields are written in braces:
///
///     {Sermon Title: Last Week}      a weekly group slot (This Week / Last Week)
///     {Last Sunday: MMMM d}          a date column + date pattern
///     {Today: MM-dd-yy}
///     {Coming Sunday: M/d/yy}
///
/// Group names and date names are case-insensitive. A date field without a pattern uses "MMMM d".
public enum TemplateEngine {
    public static let defaultDatePattern = "MMMM d"

    public static func render(
        _ template: String,
        groups: [RotatingGroup],
        clock: WeekClock,
        now: Date
    ) -> RenderedTemplate {
        var output = ""
        var problems: [String] = []
        var index = template.startIndex

        while index < template.endIndex {
            let character = template[index]
            if character == "{", let close = template[index...].firstIndex(of: "}") {
                let inner = String(template[template.index(after: index)..<close])
                switch resolve(inner, groups: groups, clock: clock, now: now) {
                case .value(let value):
                    output += value
                case .empty(let label):
                    output += "⟨\(label)⟩"
                    problems.append("\(label) is empty")
                case .unknown:
                    output += "{\(inner)}"
                    problems.append("Unknown field {\(inner)}")
                }
                index = template.index(after: close)
            } else {
                output.append(character)
                index = template.index(after: index)
            }
        }
        return RenderedTemplate(text: output, problems: problems)
    }

    public static func field(group: String, slot: WeekSlot) -> String {
        "{\(group): \(slot.label)}"
    }

    public static func field(anchor: DateAnchor, pattern: String) -> String {
        "{\(anchor.title): \(pattern)}"
    }

    /// Rewrites fields that refer to a renamed group.
    public static func renameGroup(in template: String, from oldName: String, to newName: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: oldName.trimmingCharacters(in: .whitespaces))
        guard let regex = try? NSRegularExpression(
            pattern: "\\{\\s*\(escaped)\\s*(:|\\})",
            options: [.caseInsensitive]
        ) else { return template }
        let replacement = NSRegularExpression.escapedTemplate(for: "{\(newName)") + "$1"
        let range = NSRange(template.startIndex..., in: template)
        return regex.stringByReplacingMatches(in: template, range: range, withTemplate: replacement)
    }

    private enum Resolution {
        case value(String)
        case empty(String)
        case unknown
    }

    private static func resolve(_ inner: String, groups: [RotatingGroup], clock: WeekClock, now: Date) -> Resolution {
        let parts = inner.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let source = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let argument = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        if let anchor = DateAnchor(tokenName: source) {
            let pattern = argument.isEmpty ? defaultDatePattern : argument
            let date = anchor.date(now: now, clock: clock)
            return .value(DateText.format(date, pattern: pattern, calendar: clock.calendar))
        }

        if let group = groups.first(where: { $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(source) == .orderedSame }) {
            let slot: WeekSlot
            if argument.isEmpty {
                slot = .thisWeek
            } else if let parsed = WeekSlot(tokenArgument: argument) {
                slot = parsed
            } else {
                return .unknown
            }
            let value = group[slot].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? .empty("\(group.name) · \(slot.label)") : .value(value)
        }

        return .unknown
    }
}
