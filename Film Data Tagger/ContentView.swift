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

    @Query(filter: #Predicate<Roll> { $0.deletedAt == nil })
    private var rolls: [Roll]

    @Query(filter: #Predicate<Camera> { $0.deletedAt == nil })
    private var cameras: [Camera]

    @State private var locationManager = LocationManager()
    @State private var activeRoll: Roll?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Log items list
                List {
                    if logItems.isEmpty {
                        ContentUnavailableView(
                            "No Captures Yet",
                            systemImage: "camera",
                            description: Text("Tap the capture button to log your first frame")
                        )
                    } else {
                        ForEach(logItems) { item in
                            LogItemRow(item: item)
                        }
                    }
                }

                Divider()

                // Capture button
                captureButton
                    .padding()
            }
            .navigationTitle("Film Log")
            .onAppear {
                setupIfNeeded()
                locationManager.requestPermission()
            }
        }
    }

    private var captureButton: some View {
        Button(action: logExposure) {
            Label("Log Exposure", systemImage: "camera.shutter.button.fill")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(activeRoll == nil)
    }

    private func logExposure() {
        guard let roll = activeRoll else { return }

        let item = LogItem(roll: roll)

        // Capture location if available
        if let location = locationManager.currentLocation {
            item.setLocation(location)
        }

        modelContext.insert(item)
        roll.logItems.append(item)
        roll.touch()
    }

    /// Creates test camera and roll on first launch
    private func setupIfNeeded() {
        // Use existing roll if available
        if let existingRoll = rolls.first {
            activeRoll = existingRoll
            return
        }

        // Create test camera
        let camera = Camera(name: "Test Camera")
        modelContext.insert(camera)

        // Create test roll
        let roll = Roll(filmStock: "Kodak Portra 400", camera: camera)
        modelContext.insert(roll)

        activeRoll = roll
    }
}

struct LogItemRow: View {
    let item: LogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let frameNumber = item.frameNumber {
                    Text("Frame \(frameNumber)")
                        .font(.headline)
                } else {
                    Text("Frame")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(item.createdAt, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.hasLocation, let lat = item.latitude, let lon = item.longitude {
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
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Camera.self, Roll.self, LogItem.self], inMemory: true)
}
