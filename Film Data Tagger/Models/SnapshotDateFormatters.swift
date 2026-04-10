//
//  SnapshotDateFormatters.swift
//  Film Data Tagger
//

import Foundation

/// Reusable formatter cache for bulk snapshot creation. Avoids constructing
/// a new `Date.FormatStyle` for every item in `loadAll()`.
final class SnapshotDateFormatters {
    let localTime = Date.FormatStyle.dateTime.hour().minute()
    let localDate = Date.FormatStyle.dateTime.month().day().year()
    private var capturedCache: [String: (time: Date.FormatStyle, date: Date.FormatStyle)] = [:]

    func captured(for tz: TimeZone) -> (time: Date.FormatStyle, date: Date.FormatStyle) {
        let key = tz.identifier
        if let cached = capturedCache[key] { return cached }
        var timeFmt = Date.FormatStyle.dateTime.hour().minute()
        timeFmt.timeZone = tz
        var dateFmt = Date.FormatStyle.dateTime.month().day().year()
        dateFmt.timeZone = tz
        let pair = (timeFmt, dateFmt)
        capturedCache[key] = pair
        return pair
    }

    /// Resolves the captured time zone and computes whether it differs from the device TZ,
    /// returning a human-readable label if so.
    func timeZoneInfo(for date: Date, tzIdentifier: String?, cityName: String?) -> (capturedTZ: TimeZone, hasDifferent: Bool, label: String?) {
        let capturedTZ = tzIdentifier.flatMap { TimeZone(identifier: $0) } ?? .current
        let hasDifferent = capturedTZ.secondsFromGMT(for: date) != TimeZone.current.secondsFromGMT(for: date)
        let label: String? = if hasDifferent {
            cityName ?? tzIdentifier.map { Self.cityName(from: $0) }
        } else {
            nil
        }
        return (capturedTZ, hasDifferent, label)
    }

    /// Extracts a city name from a time zone identifier (e.g., "America/Los_Angeles" → "Los Angeles")
    private static func cityName(from timeZoneIdentifier: String) -> String {
        let components = timeZoneIdentifier.split(separator: "/")
        let last = components.last.map(String.init) ?? timeZoneIdentifier
        return last.replacingOccurrences(of: "_", with: " ")
    }
}
