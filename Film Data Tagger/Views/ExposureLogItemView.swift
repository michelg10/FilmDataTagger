//
//  ExposureLogItemView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/9/26.
//

import SwiftUI
import SwiftData

/// Extracts a city name from a time zone identifier (e.g., "America/Los_Angeles" → "Los Angeles")
private func cityName(from timeZoneIdentifier: String) -> String {
    let components = timeZoneIdentifier.split(separator: "/")
    let last = components.last.map(String.init) ?? timeZoneIdentifier
    return last.replacingOccurrences(of: "_", with: " ")
}

/// Bridges a LogItem model to LogItemView
struct ExposureLogItemView: View {
    let item: LogItem
    var exposureNumber: Int?
    var isPreFrame: Bool = false
    var onCycleExtraExposures: (() -> Void)?
    @State private var showingLocalTime = false

    /// Whether the item was captured in a different time zone than the user's current one
    private var hasDifferentTimeZone: Bool {
        guard let tzId = item.timeZoneIdentifier else { return false }
        return tzId != TimeZone.current.identifier
    }

    var body: some View {
        LogItemView(
            exposureNumber: exposureNumber,
            isPreFrame: isPreFrame,
            onFrameNumberTapped: (isPreFrame || exposureNumber == 1) ? onCycleExtraExposures : nil,
            previewImage: item.photoData
                .flatMap { UIImage(data: $0) }
                .map { Image(uiImage: $0) },
            infoItems: infoItems
        )
    }

    private var infoItems: [LogItemView.LogItemInfoItem] {
        var items: [LogItemView.LogItemInfoItem] = []

        // Time
        if item.hasRealCreatedAt {
            if hasDifferentTimeZone {
                let displayTZ: TimeZone
                let tzLabel: String
                if showingLocalTime {
                    displayTZ = .current
                    tzLabel = "Local"
                } else {
                    displayTZ = TimeZone(identifier: item.timeZoneIdentifier!) ?? .current
                    tzLabel = cityName(from: item.timeZoneIdentifier!)
                }
                var timeFormat = Date.FormatStyle.dateTime.hour().minute()
                timeFormat.timeZone = displayTZ
                var dateFormat = Date.FormatStyle.dateTime.month().day().year()
                dateFormat.timeZone = displayTZ

                let timeString = item.createdAt.formatted(timeFormat)
                let dateString = item.createdAt.formatted(dateFormat)

                items.append(.init(
                    id: "time",
                    icon: Image(systemName: "clock.fill"),
                    mainText: Text(timeString),
                    secondaryText: Text("\(dateString) · \(tzLabel)"),
                    onTap: { showingLocalTime.toggle() }
                ))
            } else {
                items.append(.init(
                    id: "time",
                    icon: Image(systemName: "clock.fill"),
                    mainText: Text(item.createdAt, format: .dateTime.hour().minute()),
                    secondaryText: Text(item.createdAt, format: .dateTime.month().day().year())
                ))
            }
        } else {
            items.append(.init(
                id: "time",
                icon: Image(systemName: "clock.fill"),
                mainText: Text("Unknown"),
                secondaryText: nil
            ))
        }

        // Location
        if let placeName = item.placeName {
            items.append(.init(
                id: "location",
                icon: Image(systemName: "location.fill"),
                mainText: Text(placeName),
                secondaryText: nil
            ))
        } else if item.hasLocation, let lat = item.latitude, let lon = item.longitude {
            items.append(.init(
                id: "location",
                icon: Image(systemName: "location.fill"),
                mainText: Text(String(format: "%.5f, %.5f", lat, lon)),
                secondaryText: nil
            ))
        } else {
            items.append(.init(
                id: "location",
                icon: Image(systemName: "location.fill"),
                mainText: Text("Unknown"),
                secondaryText: nil
            ))
        }

        // Notes
        if let notes = item.notes, !notes.isEmpty {
            items.append(.init(
                id: "notes",
                icon: Image(systemName: "note.text"),
                mainText: Text(notes),
                secondaryText: nil
            ))
        }

        return items
    }
}

#Preview("With location") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container)
    return ExposureLogItemView(item: items[0], exposureNumber: 1)
        .padding(.horizontal, 16)
        .background(Color.black)
        .modelContainer(container)
}

#Preview("With notes") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container)
    return ExposureLogItemView(item: items[1], exposureNumber: 2)
        .padding(.horizontal, 16)
        .background(Color.black)
        .modelContainer(container)
}
