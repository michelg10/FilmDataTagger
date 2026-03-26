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

/// In-memory cache for formatted date strings so we don't run DateFormatter in every body evaluation.
private final class DateStringCache {
    static let shared = DateStringCache()
    private var cache: [UUID: Entry] = [:]

    struct Entry {
        let timeMain: String
        let timeSecondary: String?
        let createdAt: Date
        let showingLocalTime: Bool
        let tzIdentifier: String?
    }

    func entry(for id: UUID, createdAt: Date, showingLocalTime: Bool, tzIdentifier: String?) -> Entry? {
        guard let e = cache[id],
              e.createdAt == createdAt,
              e.showingLocalTime == showingLocalTime,
              e.tzIdentifier == tzIdentifier else { return nil }
        return e
    }

    func store(_ entry: Entry, for id: UUID) {
        cache[id] = entry
    }

    func remove(_ id: UUID) {
        cache.removeValue(forKey: id)
    }
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
                ImageCache.shared.image(for: id, thumbnailData: data)
            }.value
            if !Task.isCancelled {
                decodedImage = image
            }
        }
    }

    // MARK: - Computed text

    private var cachedDateStrings: DateStringCache.Entry {
        let cache = DateStringCache.shared
        if let entry = cache.entry(for: item.id, createdAt: item.createdAt, showingLocalTime: showingLocalTime, tzIdentifier: item.timeZoneIdentifier) {
            return entry
        }
        let main: String
        let secondary: String?
        if !item.hasRealCreatedAt {
            main = "Unknown"
            secondary = nil
        } else if hasDifferentTimeZone {
            let tz = displayTimeZone
            var timeFmt = Date.FormatStyle.dateTime.hour().minute()
            timeFmt.timeZone = tz
            main = item.createdAt.formatted(timeFmt)
            var dateFmt = Date.FormatStyle.dateTime.month().day().year()
            dateFmt.timeZone = tz
            let tzLabel = showingLocalTime ? "Local" : cityName(from: item.timeZoneIdentifier ?? "")
            secondary = "\(item.createdAt.formatted(dateFmt)) · \(tzLabel)"
        } else {
            main = item.createdAt.formatted(.dateTime.hour().minute())
            secondary = item.createdAt.formatted(.dateTime.month().day().year())
        }
        let entry = DateStringCache.Entry(timeMain: main, timeSecondary: secondary, createdAt: item.createdAt, showingLocalTime: showingLocalTime, tzIdentifier: item.timeZoneIdentifier)
        cache.store(entry, for: item.id)
        return entry
    }

    private var timeText: Text {
        Text(cachedDateStrings.timeMain)
    }

    private var timeSecondaryText: Text? {
        cachedDateStrings.timeSecondary.map { Text($0) }
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
        return item.timeZoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? .current
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
