//
//  CameraListEntry.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/20/26.
//

import Foundation

/// Protocol for items that appear in the camera list (regular cameras and instant film groups).
/// Both Camera and InstantFilmGroup already conform to Identifiable via @Model.
@MainActor
protocol CameraListEntry {
    var id: UUID { get }
    var displayName: String { get }
    var isInstantFilm: Bool { get }
    var allRolls: [Roll] { get }
    var activeRoll: Roll? { get }
    var rollCount: Int { get }
    var totalExposureCount: Int { get }
    var filmStockLabel: String? { get }
    var lastUsedCompact: String? { get }
}

// MARK: - Default implementations

extension CameraListEntry {
    var rollCount: Int { allRolls.count }

    var totalExposureCount: Int {
        allRolls.flatMap { $0.logItems ?? [] }.count
    }

    var lastUsedCompact: String? {
        let allItems = allRolls.flatMap { $0.logItems ?? [] }
        guard let lastDate = allItems.map(\.createdAt).max() else { return nil }
        return compactTimeString(from: lastDate)
    }
}

// MARK: - Relative time formatting

private func compactTimeString(from date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    if days < 30 { return "\(days)d" }
    let months = days / 30
    if days < 365 { return "\(months)mo" }
    return "\(days / 365)yr"
}

func relativeTimeString(from date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "used just now" }
    let minutes = seconds / 60
    if minutes < 60 { return "used \(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "used \(hours)h ago" }
    let days = hours / 24
    if days < 30 { return "used \(days)d ago" }
    let months = days / 30
    if months < 12 { return "used \(months)mo ago" }
    let years = days / 365
    return "used \(years)y ago"
}

// MARK: - Camera conformance

extension Camera: CameraListEntry {
    var displayName: String { name }
    var isInstantFilm: Bool { false }
    var allRolls: [Roll] { rolls ?? [] }
    var activeRoll: Roll? { allRolls.first(where: { $0.isActive }) }

    var filmStockLabel: String? {
        activeRoll?.filmStock ?? (allRolls.isEmpty ? nil : "no roll loaded")
    }
}

// MARK: - Roll display helpers

private func formatLoadedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM d"
    let dayStr = formatter.string(from: date)
    let day = Calendar.current.component(.day, from: date)
    let suffix: String
    switch day {
    case 1, 21, 31: suffix = "st"
    case 2, 22: suffix = "nd"
    case 3, 23: suffix = "rd"
    default: suffix = "th"
    }
    formatter.dateFormat = "h:mma"
    formatter.amSymbol = "am"
    formatter.pmSymbol = "pm"
    let timeStr = formatter.string(from: date)
    return "\(dayStr)\(suffix), \(timeStr)"
}

extension Roll {
    var activeItemCount: Int {
        (logItems ?? []).count
    }

    var rollSummary: String {
        var desc = "\(activeItemCount) / \(totalCapacity) exposure\(totalCapacity == 1 ? "" : "s") • Loaded \(formatLoadedDate(createdAt))"
        if !isActive {
            desc += " • \(relativeTimeString(from: modifiedAt))"
        }
        return desc
    }
}

// MARK: - InstantFilmGroup conformance

extension InstantFilmGroup: CameraListEntry {
    var displayName: String { name }
    var isInstantFilm: Bool { true }
    var allRolls: [Roll] { (cameras ?? []).flatMap { $0.rolls ?? [] } }
    var activeRoll: Roll? { nil }

    var filmStockLabel: String? { nil }
}
