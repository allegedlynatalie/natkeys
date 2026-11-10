import os

/// Diagnostics, readable with:
///   /usr/bin/log show --last 10m --predicate 'subsystem == "io.github.allegedlynatalie.natkeys"'
enum Log {
    private static let logger = Logger(subsystem: "io.github.allegedlynatalie.natkeys", category: "app")

    static func info(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
