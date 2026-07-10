import Foundation
import PerchHACore

enum PerchHAHistoryHoverFormatting {
    private static let currentDateTimeFormatter: DateFormatter = makeFormatter(
        locale: .current,
        timeZone: .current,
        showsTime: true
    )
    private static let currentDateOnlyFormatter: DateFormatter = makeFormatter(
        locale: .current,
        timeZone: .current,
        showsTime: false
    )

    static func timestamp(
        _ timestamp: Date,
        range: HistoryRange? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let showsTime = range != .week && range != .month
        if locale == .current && timeZone == .current {
            return (showsTime ? currentDateTimeFormatter : currentDateOnlyFormatter).string(from: timestamp)
        }
        return makeFormatter(locale: locale, timeZone: timeZone, showsTime: showsTime).string(from: timestamp)
    }

    private static func makeFormatter(locale: Locale, timeZone: TimeZone, showsTime: Bool) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = showsTime ? .short : .none
        return formatter
    }
}
