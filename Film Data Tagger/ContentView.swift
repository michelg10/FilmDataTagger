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
           order: .forward)
    private var logItems: [LogItem]

    @State private var viewModel: FilmLogViewModel?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                logItemsList

                VStack(spacing: 8) {
                    logExposureButton
                    // TODO: Remove — debug only
                    Button("Clear All Exposures", role: .destructive) {
                        for item in logItems {
                            modelContext.delete(item)
                        }
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.bottom)
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
        ScrollViewReader { proxy in
            ScrollView {
                if logItems.isEmpty {
                    ContentUnavailableView(
                        "No Exposures Yet",
                        systemImage: "camera",
                        description: Text("Tap the button below to log your first exposure")
                    )
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(logItems) { item in
                            LogItemView(
                                exposureNumber: item.frameNumber,
                                previewImage: nil,
                                infoItems: infoItems(for: item)
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 16)

                    Color.clear
                        .frame(height: 260)
                        .id("scrollAnchor")

                    Spacer()
                        .frame(height: 40)
                }
            }
            .onAppear {
                if !logItems.isEmpty {
                    proxy.scrollTo("scrollAnchor", anchor: .bottom)
                }
            }
            .onChange(of: logItems.count) {
                if !logItems.isEmpty {
                    withAnimation {
                        proxy.scrollTo("scrollAnchor", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
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

    // MARK: - Info Items

    private func infoItems(for item: LogItem) -> [LogItemView.LogItemInfoItem] {
        var items: [LogItemView.LogItemInfoItem] = []

        // Time
        items.append(.init(
            icon: Image(systemName: "clock.fill"),
            mainText: Text(item.createdAt, format: .dateTime.hour().minute()),
            secondaryText: Text(item.createdAt, format: .dateTime.month().day().year())
        ))

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

#Preview {
    let container = try! ModelContainer(
        for: Camera.self, Roll.self, LogItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let camera = Camera(name: "Leica M6")
    context.insert(camera)

    let roll = Roll(filmStock: "Kodak Portra 400", camera: camera)
    context.insert(roll)

    struct FakeExposure {
        let lat: Double
        let lon: Double
        let placeName: String
        let minutesAgo: Int
        let notes: String?
    }

    let exposures: [FakeExposure] = [
        .init(lat: 34.0037, lon: -118.4810, placeName: "Dockweiler State Beach", minutesAgo: 5, notes: nil),
        .init(lat: 34.0195, lon: -118.4912, placeName: "Venice Beach Boardwalk", minutesAgo: 28, notes: "Golden hour light"),
        .init(lat: 34.0259, lon: -118.5100, placeName: "Santa Monica Pier", minutesAgo: 45, notes: nil),
        .init(lat: 34.0522, lon: -118.2437, placeName: "Grand Central Market, Los Angeles", minutesAgo: 120, notes: "Neon signs"),
        .init(lat: 34.1184, lon: -118.3004, placeName: "Griffith Observatory", minutesAgo: 180, notes: nil),
        .init(lat: 34.0407, lon: -118.2468, placeName: "Arts District, Los Angeles", minutesAgo: 240, notes: "Street mural"),
        .init(lat: 34.0669, lon: -118.3495, placeName: "The Grove", minutesAgo: 300, notes: nil),
    ]

    for exposure in exposures {
        let item = LogItem(roll: roll, camera: camera)
        item.createdAt = Date().addingTimeInterval(TimeInterval(-exposure.minutesAgo * 60))
        item.latitude = exposure.lat
        item.longitude = exposure.lon
        item.placeName = exposure.placeName
        item.notes = exposure.notes
        context.insert(item)
        roll.logItems.append(item)
    }

    return ContentView()
        .modelContainer(container)
}
