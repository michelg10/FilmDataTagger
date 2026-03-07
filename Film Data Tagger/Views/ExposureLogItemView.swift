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
            timeText: timeText,
            timeSecondaryText: timeSecondaryText,
            onTimeTapped: hasDifferentTimeZone ? { showingLocalTime.toggle() } : nil,
            locationText: locationText,
        )
    }

    // MARK: - Computed text

    private var timeText: Text {
        guard item.hasRealCreatedAt else { return Text("Unknown") }
        if hasDifferentTimeZone {
            let tz = displayTimeZone
            var fmt = Date.FormatStyle.dateTime.hour().minute()
            fmt.timeZone = tz
            return Text(item.createdAt.formatted(fmt))
        }
        return Text(item.createdAt, format: .dateTime.hour().minute())
    }

    private var timeSecondaryText: Text? {
        guard item.hasRealCreatedAt else { return nil }
        if hasDifferentTimeZone {
            let tz = displayTimeZone
            let tzLabel = showingLocalTime ? "Local" : cityName(from: item.timeZoneIdentifier!)
            var fmt = Date.FormatStyle.dateTime.month().day().year()
            fmt.timeZone = tz
            return Text("\(item.createdAt.formatted(fmt)) · \(tzLabel)")
        }
        return Text(item.createdAt, format: .dateTime.month().day().year())
    }

    private var locationText: Text {
        if let placeName = item.placeName {
            return Text(placeName)
        } else if item.hasLocation, let lat = item.latitude, let lon = item.longitude {
            return Text(String(format: "%.5f, %.5f", lat, lon))
        }
        return Text("Unknown")
    }

    private var displayTimeZone: TimeZone {
        if showingLocalTime {
            return .current
        }
        return TimeZone(identifier: item.timeZoneIdentifier!) ?? .current
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
