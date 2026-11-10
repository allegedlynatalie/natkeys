import Foundation

public enum AutoShift {
    /// Runs the Sunday auto-shift if a flip has passed since the last run.
    ///
    /// - The first run ever only records a baseline (nothing shifts on install day).
    /// - If several weeks were missed (Mac off), groups shift once, not once per week.
    /// - Groups with an empty This Week are left alone so Last Week isn't wiped.
    /// - Groups that were shifted manually ahead of this flip are skipped.
    ///
    /// Returns the names of the groups that shifted.
    @discardableResult
    public static func run(_ data: inout AppData, now: Date) -> [String] {
        let clock = data.settings.clock
        let sunday = clock.lastSunday(now: now)

        guard let last = data.lastAutoShiftSunday else {
            data.lastAutoShiftSunday = sunday
            return []
        }
        guard sunday > last else { return [] }

        var shifted: [String] = []
        for index in data.groups.indices {
            let manualFor = data.groups[index].manualShiftSunday
            data.groups[index].manualShiftSunday = nil
            guard data.groups[index].autoShift else { continue }
            if let manualFor, manualFor == sunday { continue }
            if data.groups[index].canShift {
                data.groups[index].shift()
                shifted.append(data.groups[index].name)
            }
        }
        data.lastAutoShiftSunday = sunday
        return shifted
    }

    /// The Shift button. Marks the upcoming flip as handled so it won't shift again.
    @discardableResult
    public static func manualShift(_ data: inout AppData, groupID: UUID, now: Date) -> Bool {
        guard let index = data.groups.firstIndex(where: { $0.id == groupID }),
              data.groups[index].canShift else { return false }
        data.groups[index].shift()
        data.groups[index].manualShiftSunday = data.settings.clock.comingSunday(now: now)
        return true
    }
}
