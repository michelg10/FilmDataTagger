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
    var configSubtitle: String { get }
}

// MARK: - Relative time formatting

private func relativeTimeString(from date: Date) -> String {
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

    var configSubtitle: String {
        let activeRolls = rolls.filter { $0.deletedAt == nil }
        let allItems = activeRolls.flatMap { $0.logItems }.filter { $0.deletedAt == nil }

        if allItems.isEmpty && activeRolls.isEmpty {
            return "no exposures"
        }

        var parts: [String] = []

        // Active roll film stock (or "no roll loaded")
        if let active = activeRolls.first(where: { $0.isActive }) {
            parts.append(active.filmStock)
        } else if !activeRolls.isEmpty {
            parts.append("no roll loaded")
        }

        // Roll count
        if activeRolls.count == 1 {
            parts.append("1 roll")
        } else if activeRolls.count > 1 {
            parts.append("\(activeRolls.count) rolls")
        }

        // Exposure count
        if allItems.isEmpty {
            parts.append("0 exposures")
        } else {
            parts.append("\(allItems.count) exposure\(allItems.count == 1 ? "" : "s")")
        }

        // Last used
        if let lastDate = allItems.map(\.createdAt).max() {
            parts.append(relativeTimeString(from: lastDate))
        }

        return parts.joined(separator: " \u{2022} ")
    }
}

// MARK: - InstantFilmGroup conformance

extension InstantFilmGroup: CameraListEntry {
    var displayName: String { name }

    var configSubtitle: String {
        let activeCameras = cameras.filter { $0.deletedAt == nil }
        let allItems = activeCameras
            .flatMap { $0.rolls }
            .filter { $0.deletedAt == nil }
            .flatMap { $0.logItems }
            .filter { $0.deletedAt == nil }

        if allItems.isEmpty {
            return "no exposures"
        }

        var parts: [String] = []

        // Exposure count
        parts.append("\(allItems.count) exposure\(allItems.count == 1 ? "" : "s")")

        // Last used
        if let lastDate = allItems.map(\.createdAt).max() {
            parts.append(relativeTimeString(from: lastDate))
        }

        return parts.joined(separator: " \u{2022} ")
    }
}
