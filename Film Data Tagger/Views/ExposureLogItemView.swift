//
//  ExposureLogItemView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/9/26.
//

import SwiftUI
import SwiftData

/// Bridges a LogItem model to LogItemView
struct ExposureLogItemView: View {
    let item: LogItem

    var body: some View {
        LogItemView(
            exposureNumber: item.frameNumber,
            previewImage: item.photoData
                .flatMap { UIImage(data: $0) }
                .map { Image(uiImage: $0) },
            infoItems: infoItems
        )
        .contentShape(Rectangle())
    }

    private var infoItems: [LogItemView.LogItemInfoItem] {
        var items: [LogItemView.LogItemInfoItem] = []

        // Time
        if item.hasRealCreatedAt {
            items.append(.init(
                icon: Image(systemName: "clock.fill"),
                mainText: Text(item.createdAt, format: .dateTime.hour().minute()),
                secondaryText: Text(item.createdAt, format: .dateTime.month().day().year())
            ))
        } else {
            items.append(.init(
                icon: Image(systemName: "clock.fill"),
                mainText: Text("Unknown"),
                secondaryText: nil
            ))
        }

        // Location
        if let placeName = item.placeName {
            items.append(.init(
                icon: Image(systemName: "location.fill"),
                mainText: Text(placeName),
                secondaryText: nil
            ))
        } else if item.hasLocation, let lat = item.latitude, let lon = item.longitude {
            items.append(.init(
                icon: Image(systemName: "location.fill"),
                mainText: Text(String(format: "%.5f, %.5f", lat, lon)),
                secondaryText: nil
            ))
        } else {
            items.append(.init(
                icon: Image(systemName: "location.fill"),
                mainText: Text("Unknown"),
                secondaryText: nil
            ))
        }

        // Notes
        if let notes = item.notes, !notes.isEmpty {
            items.append(.init(
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
    return ExposureLogItemView(item: items[0])
        .padding(.horizontal, 16)
        .background(Color.black)
        .modelContainer(container)
}

#Preview("With notes") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container)
    return ExposureLogItemView(item: items[1])
        .padding(.horizontal, 16)
        .background(Color.black)
        .modelContainer(container)
}
