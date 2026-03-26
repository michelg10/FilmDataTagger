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
    let exposureNumber: Int?
    var isPreFrame: Bool = false
    var onCycleExtraExposures: (() -> Void)?
    @State private var showingLocalTime = false
    @State private var decodedImage: UIImage?

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
            previewImage: decodedImage.map { Image(uiImage: $0) },
            timeText: timeText,
            timeSecondaryText: timeSecondaryText,
            onTimeTapped: hasDifferentTimeZone ? { showingLocalTime.toggle() } : nil,
            locationText: locationText,
        )
        .task(id: item.id) {
            // Fast path: already cached (no decode needed)
            if let cached = ImageCache.shared.cachedImage(for: item.id) {
                decodedImage = cached
                return
            }
            // Slow path: decode off main thread
            guard let data = item.thumbnailData else { return }
            let id = item.id
            let image = await Task.detached {
                await ImageCache.shared.image(for: id, thumbnailData: data)
            }.value
            if !Task.isCancelled {
                decodedImage = image
            }
        }
    }

    // MARK: - Computed text

    private var timeText: Text {
        guard item.hasRealCreatedAt else { return Text("Unknown") }
        if hasDifferentTimeZone {
            return Text(showingLocalTime ? item.formattedTimeLocal : item.formattedTimeForeignTZ)
        }
        return Text(item.formattedTime)
    }

    private var timeSecondaryText: Text? {
        guard item.hasRealCreatedAt else { return nil }
        if hasDifferentTimeZone {
            let dateStr = showingLocalTime ? item.formattedDateLocal : item.formattedDateForeignTZ
            let tzLabel = showingLocalTime ? "Local" : cityName(from: item.timeZoneIdentifier ?? "")
            return Text("\(dateStr) · \(tzLabel)")
        }
        return Text(item.formattedDate)
    }

    private var locationText: Text {
        if let placeName = item.placeName {
            return Text(placeName)
        } else if item.hasLocation, let lat = item.latitude, let lon = item.longitude {
            return Text(String(format: "%.5f, %.5f", lat, lon))
        }
        return Text("Unknown")
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
