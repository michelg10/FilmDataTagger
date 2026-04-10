//
//  ExposureLogItemView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/9/26.
//

import SwiftUI
import SwiftData

/// Bridges a LogItemSnapshot to LogItemView
struct ExposureLogItemView: View {
    @Environment(FilmLogViewModel.self) private var viewModel
    let item: LogItemSnapshot
    let exposureNumber: Int?
    var isPreFrame: Bool = false
    var onCycleExtraExposures: (() -> Void)?
    var onDoubleTapCycleExtraExposures: (() -> Void)?
    @State private var showingLocalTime = false
    @State private var previewImage: Image?

    var body: some View {
        LogItemView(
            exposureNumber: exposureNumber,
            isPreFrame: isPreFrame,
            onFrameNumberTapped: onCycleExtraExposures,
            onFrameNumberDoubleTapped: onDoubleTapCycleExtraExposures,
            previewImage: previewImage,
            isFromShortcut: item.source == ExposureSource.shortcut.rawValue,
            exposureType: item.exposureType,
            timeText: timeText,
            timeSecondaryText: timeSecondaryText,
            onTimeTapped: item.hasDifferentTimeZone ? { showingLocalTime.toggle() } : nil,
            locationText: locationText,
        )
        .task(id: item.hasThumbnail) {
            guard item.hasThumbnail else { previewImage = nil; return }
            // Fast path: already cached (no decode needed)
            if let cached = ImageCache.shared.cachedImage(for: item.id) {
                previewImage = Image(uiImage: cached)
                return
            }
            // Disk cache (BGRA then JPEG)
            let id = item.id
            let image = await Task.detached(priority: .userInitiated) {
                await ImageCache.shared.loadFromDiskAndCache(for: id)
            }.value
            if !Task.isCancelled, let image {
                previewImage = Image(uiImage: image)
                return
            }
            // Cache miss — recover from SwiftData (disk cache may have been purged by iOS)
            guard !Task.isCancelled else { return }
            let storeTask = viewModel.storeTask
            let recovered = await Task.detached(priority: .userInitiated) {
                let store = await storeTask.value
                guard let data = await store.fetchThumbnailData(for: id) else { return nil as UIImage? }
                return await ImageCache.shared.decodeAndCache(for: id, data: data)
            }.value
            if !Task.isCancelled, let recovered {
                previewImage = Image(uiImage: recovered)
            }
        }
    }

    // MARK: - Computed text (all pre-computed on the snapshot — zero work here)

    private var timeText: Text {
        guard item.hasRealCreatedAt else {
            return Text(item.exposureType == .lostFrame ? "n/a" : "Unknown")
        }
        if item.hasDifferentTimeZone && showingLocalTime {
            return Text(item.localFormattedTime)
        }
        return Text(item.formattedTime)
    }

    private var timeSecondaryText: Text? {
        guard item.hasRealCreatedAt else { return nil }
        if item.hasDifferentTimeZone {
            if showingLocalTime {
                return Text("\(item.localFormattedDate) · Local")
            } else {
                return Text("\(item.formattedDate) · \(item.capturedTZLabel ?? "")")
            }
        }
        return Text(item.formattedDate)
    }

    private var locationText: Text {
        if let placeName = item.placeName {
            return Text(placeName)
        } else if let lat = item.latitude, let lon = item.longitude {
            return Text(String(format: "%.5f, %.5f", lat, lon))
        }
        return Text(item.exposureType == .lostFrame ? "n/a" : "Unknown")
    }
}

#Preview("With location") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container)
    let vm = FilmLogViewModel(previewStore: PreviewSampleData.makeStore(container: container))
    return ExposureLogItemView(item: items[0].snapshot, exposureNumber: 1)
        .padding(.horizontal, 16)
        .background(Color.black)
        .modelContainer(container)
        .environment(vm)
}

#Preview("With notes") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container)
    let vm = FilmLogViewModel(previewStore: PreviewSampleData.makeStore(container: container))
    return ExposureLogItemView(item: items[1].snapshot, exposureNumber: 2)
        .padding(.horizontal, 16)
        .background(Color.black)
        .modelContainer(container)
        .environment(vm)
}
