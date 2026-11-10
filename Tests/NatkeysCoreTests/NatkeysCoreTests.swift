import Foundation
import Testing
@testable import NatkeysCore

private let calendar = Calendar.natkeys(timeZone: TimeZone(identifier: "America/Chicago")!)
private let clock = WeekClock(flipHour: 14, flipMinute: 0, calendar: calendar)

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func ymd(_ d: Date) -> String {
    DateText.format(d, pattern: "yyyy-MM-dd", calendar: calendar)
}

private func makeData(this: String = "", last: String = "") -> AppData {
    var data = AppData.defaults()
    data.groups[0].thisWeek = this
    data.groups[0].lastWeek = last
    return data
}

// AutoShift reads the clock from settings, which uses the current time zone.
// These tests build dates with the same zone the settings clock uses.
private let settingsCalendar = Calendar.natkeys()
private func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    settingsCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite("Sunday math")
struct WeekClockTests {
    @Test func midweek() {
        // Wednesday, November 4, 2026
        let now = date(2026, 11, 4, 10)
        #expect(ymd(clock.lastSunday(now: now)) == "2026-11-01")
        #expect(ymd(clock.today(now: now)) == "2026-11-04")
        #expect(ymd(clock.comingSunday(now: now)) == "2026-11-08")
    }

    @Test func sundayBeforeFlip() {
        let now = date(2026, 11, 8, 13, 59)
        #expect(ymd(clock.lastSunday(now: now)) == "2026-11-01")
        #expect(ymd(clock.comingSunday(now: now)) == "2026-11-08")
    }

    @Test func sundayAtAndAfterFlip() {
        for now in [date(2026, 11, 8, 14, 0), date(2026, 11, 8, 20, 0)] {
            #expect(ymd(clock.lastSunday(now: now)) == "2026-11-08")
            #expect(ymd(clock.comingSunday(now: now)) == "2026-11-15")
        }
    }

    @Test func saturdayAndMonday() {
        #expect(ymd(clock.lastSunday(now: date(2026, 11, 7, 23, 59))) == "2026-11-01")
        #expect(ymd(clock.comingSunday(now: date(2026, 11, 7, 23, 59))) == "2026-11-08")
        #expect(ymd(clock.lastSunday(now: date(2026, 11, 9, 0, 1))) == "2026-11-08")
    }

    @Test func acrossMonthAndYearBoundaries() {
        // Wednesday, December 30, 2026 -> last Sunday Dec 27, coming Sunday Jan 3, 2027
        let now = date(2026, 12, 30)
        #expect(ymd(clock.lastSunday(now: now)) == "2026-12-27")
        #expect(ymd(clock.comingSunday(now: now)) == "2027-01-03")
    }

    @Test func acrossDaylightSavingEnd() {
        // DST ends Sunday, November 1, 2026 in the US.
        let now = date(2026, 11, 1, 15)
        #expect(ymd(clock.lastSunday(now: now)) == "2026-11-01")
        #expect(ymd(clock.comingSunday(now: now)) == "2026-11-08")
        let before = date(2026, 11, 1, 9)
        #expect(ymd(clock.lastSunday(now: before)) == "2026-10-25")
    }

    @Test func nextFlip() {
        let flip = clock.nextFlip(after: date(2026, 11, 4))
        #expect(DateText.format(flip, pattern: "yyyy-MM-dd HH:mm", calendar: calendar) == "2026-11-08 14:00")
    }
}

@Suite("Date formats")
struct DateFormatTests {
    @Test func defaultPatterns() {
        let lastSunday = clock.lastSunday(now: date(2026, 11, 4))
        let rendered = AppData.defaultDatePatterns.map { DateText.format(lastSunday, pattern: $0, calendar: calendar) }
        #expect(rendered == ["November 1", "11-01-26", "November 1, 2026", "11/1/26", "Sunday, November 1"])
    }
}

@Suite("Weekly auto-shift")
struct AutoShiftTests {
    @Test func firstRunOnlyRecordsBaseline() {
        var data = makeData(this: "Grace Upon Grace", last: "The Narrow Gate")
        let names = AutoShift.run(&data, now: localDate(2026, 11, 4))
        #expect(names.isEmpty)
        #expect(data.groups[0].thisWeek == "Grace Upon Grace")
        #expect(data.lastAutoShiftSunday != nil)
    }

    @Test func shiftsAtSundayFlip() {
        var data = makeData(this: "Grace Upon Grace", last: "The Narrow Gate")
        AutoShift.run(&data, now: localDate(2026, 11, 4))
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 8, 13, 59)).isEmpty)
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 8, 14, 0)) == ["Sermon Title"])
        #expect(data.groups[0].thisWeek == "")
        #expect(data.groups[0].lastWeek == "Grace Upon Grace")
        // Running again the same week does nothing.
        data.groups[0].thisWeek = "Next Week's Title"
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 10)).isEmpty)
        #expect(data.groups[0].thisWeek == "Next Week's Title")
    }

    @Test func emptyThisWeekDoesNotWipeLastWeek() {
        var data = makeData(this: "", last: "The Narrow Gate")
        AutoShift.run(&data, now: localDate(2026, 11, 4))
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 8, 15)).isEmpty)
        #expect(data.groups[0].lastWeek == "The Narrow Gate")
    }

    @Test func catchUpShiftsOnlyOnce() {
        var data = makeData(this: "A", last: "B")
        AutoShift.run(&data, now: localDate(2026, 11, 4))
        // Mac was off for three Sundays.
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 25)) == ["Sermon Title"])
        #expect(data.groups[0].lastWeek == "A")
        #expect(data.groups[0].thisWeek == "")
    }

    @Test func manualShiftCoversTheUpcomingFlip() {
        var data = makeData(this: "Today's Sermon", last: "Old")
        AutoShift.run(&data, now: localDate(2026, 11, 4))
        // Sunday morning: shift by hand, then save next week's title.
        let id = data.groups[0].id
        #expect(AutoShift.manualShift(&data, groupID: id, now: localDate(2026, 11, 8, 11)))
        data.groups[0].thisWeek = "Next Week's Sermon"
        // The 2 PM auto-shift must not push next week's title down.
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 8, 14, 30)).isEmpty)
        #expect(data.groups[0].thisWeek == "Next Week's Sermon")
        #expect(data.groups[0].lastWeek == "Today's Sermon")
        // The following Sunday shifts normally again.
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 15, 14, 30)) == ["Sermon Title"])
        #expect(data.groups[0].lastWeek == "Next Week's Sermon")
    }

    @Test func manualShiftRefusesEmptyThisWeek() {
        var data = makeData(this: "  ", last: "Keep Me")
        #expect(!AutoShift.manualShift(&data, groupID: data.groups[0].id, now: localDate(2026, 11, 4)))
        #expect(data.groups[0].lastWeek == "Keep Me")
    }

    @Test func groupsWithAutoShiftOffAreSkipped() {
        var data = makeData(this: "A", last: "B")
        data.groups[0].autoShift = false
        AutoShift.run(&data, now: localDate(2026, 11, 4))
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 9)).isEmpty)
        #expect(data.groups[0].thisWeek == "A")
    }

    @Test func changingFlipTimeAfterShiftDoesNotShiftTwice() {
        var data = makeData(this: "A", last: "B")
        AutoShift.run(&data, now: localDate(2026, 11, 4))
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 8, 14, 5)) == ["Sermon Title"])
        data.groups[0].thisWeek = "C"
        data.settings.flipHour = 15
        #expect(AutoShift.run(&data, now: localDate(2026, 11, 8, 15, 30)).isEmpty)
        #expect(data.groups[0].thisWeek == "C")
    }
}

@Suite("Combo templates")
struct TemplateTests {
    let groups = [RotatingGroup(name: "Sermon Title", thisWeek: "Grace Upon Grace", lastWeek: "The Narrow Gate")]
    let now = date(2026, 11, 4)

    @Test func defaultCombo() {
        let combo = AppData.defaults().combos[0]
        let result = TemplateEngine.render(combo.template, groups: groups, clock: clock, now: now)
        #expect(result.text == "The Narrow Gate – November 1")
        #expect(result.isComplete)
    }

    @Test func fieldsAreCaseInsensitiveAndFlexible() {
        let result = TemplateEngine.render(
            "{last sunday:MM-dd-yy} {sermon title:this} / {Coming Sunday} / {Today: EEEE}",
            groups: groups, clock: clock, now: now
        )
        #expect(result.text == "11-01-26 Grace Upon Grace / November 8 / Wednesday")
    }

    @Test func patternsMayContainColons() {
        let result = TemplateEngine.render("{Today: h:mm a}", groups: groups, clock: clock, now: date(2026, 11, 4, 9, 5))
        #expect(result.text == "9:05 AM")
    }

    @Test func emptySlotIsReported() {
        let empty = [RotatingGroup(name: "Sermon Title")]
        let result = TemplateEngine.render("{Sermon Title: Last Week}", groups: empty, clock: clock, now: now)
        #expect(!result.isComplete)
        #expect(result.problems == ["Sermon Title · Last Week is empty"])
    }

    @Test func unknownFieldsAreKeptAndReported() {
        let result = TemplateEngine.render("Hi {Preacher} {", groups: groups, clock: clock, now: now)
        #expect(result.text == "Hi {Preacher} {")
        #expect(result.problems.count == 1)
    }

    @Test func renamingAGroupUpdatesFields() {
        let renamed = TemplateEngine.renameGroup(
            in: "{Sermon Title: Last Week} – {sermon title} {Sermon Titles: x}",
            from: "Sermon Title", to: "Message"
        )
        #expect(renamed == "{Message: Last Week} – {Message} {Sermon Titles: x}")
    }
}

@Suite("Data model")
struct ModelTests {
    @Test func roundTripsAndToleratesMissingKeys() throws {
        var data = AppData.defaults()
        data.scratches = [
            Scratch(name: "Zoom", content: .text("https://zoom.us/j/1"), pinned: true),
            Scratch(content: .image(file: "abc.png")),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppData.self, from: try encoder.encode(data))
        #expect(decoded.scratches.count == 2)
        #expect(decoded.scratches[0].displayTitle == "Zoom")
        #expect(decoded.scratches[1].content.imageFile == "abc.png")

        let sparse = try decoder.decode(AppData.self, from: Data(#"{"groups":[{"name":"Scripture"}]}"#.utf8))
        #expect(sparse.groups[0].name == "Scripture")
        #expect(sparse.groups[0].autoShift)
        #expect(sparse.dateFormats.count == AppData.defaultDatePatterns.count)
        #expect(sparse.settings.flipHour == 14)
    }

    @Test func scratchPreviewUsesFirstLine() {
        let s = Scratch(content: .text("\n  First line  \nsecond"))
        #expect(s.displayTitle == "First line")
    }
}
