//
//  ContentView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<LogItem> { $0.deletedAt == nil },
           sort: \LogItem.createdAt,
           order: .reverse)
    private var logItems: [LogItem]

    @State private var viewModel: FilmLogViewModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                logItemsList
                Divider()
                logExposureButton
                    .padding()
            }
            .navigationTitle("Film Log")
            .onAppear {
                if viewModel == nil {
                    viewModel = FilmLogViewModel(modelContext: modelContext)
                    viewModel?.setup()
                }
            }
        }
    }

    // MARK: - Subviews

    private var logItemsList: some View {
        List {
            if logItems.isEmpty {
                ContentUnavailableView(
                    "No Exposures Yet",
                    systemImage: "camera",
                    description: Text("Tap the button below to log your first exposure")
                )
            } else {
                ForEach(logItems) { item in
                    LogItemRow(item: item)
                }
            }
        }
    }

    private var logExposureButton: some View {
        Button {
            viewModel?.logExposure()
        } label: {
            Label("Log Exposure", systemImage: "camera.shutter.button.fill")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(viewModel?.canLogExposure != true)
    }
}

// MARK: - Log Item Row

struct LogItemRow: View {
    let item: LogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                frameLabel
                Spacer()
                timestampLabel
            }
            locationLabel
        }
        .padding(.vertical, 4)
    }

    private var frameLabel: some View {
        Group {
            if let frameNumber = item.frameNumber {
                Text("Frame \(frameNumber)")
                    .font(.headline)
            } else {
                Text("Frame")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timestampLabel: some View {
        Text(item.createdAt, format: .dateTime.hour().minute().second())
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var locationLabel: some View {
        if let placeName = item.placeName {
            Label(placeName, systemImage: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if item.hasLocation, let lat = item.latitude, let lon = item.longitude {
            Label(
                String(format: "%.5f, %.5f", lat, lon),
                systemImage: "location.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Label("No location", systemImage: "location.slash")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Camera.self, Roll.self, LogItem.self], inMemory: true)
}
