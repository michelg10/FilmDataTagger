//
//  RelativeTime.swift
//  Film Data Tagger
//

import Foundation

/// Compact relative time string from a date to now.
/// - `suffix`: when true, appends " ago" for durations >= 1m (e.g. "3d ago"). "now" never gets a suffix.
/// - `includeSeconds`: when true, shows seconds (e.g. "42s") instead of "now" for durations < 1m.
func relativeTimeString(from date: Date, suffix: Bool = false, includeSeconds: Bool = false) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 {
        if includeSeconds && seconds >= 1 {
            return suffix ? "\(seconds)s ago" : "\(seconds)s"
        }
        return "now"
    }
    let minutes = seconds / 60
    let hours = minutes / 60
    let days = hours / 24
    let compact: String
    if minutes < 60 {
        compact = "\(minutes)m"
    } else if hours < 24 {
        compact = "\(hours)h"
    } else if days < 30 {
        compact = "\(days)d"
    } else if days < 365 {
        compact = "\(days / 30)mo"
    } else {
        compact = "\(days / 365)y"
    }
    return suffix ? "\(compact) ago" : compact
}
