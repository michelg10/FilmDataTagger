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
        ZStack(alignment: .bottom) {
            ExposureListView(
                logItems: logItems,
                cameraName: viewModel?.activeRoll?.camera?.name ?? "",
                filmStock: viewModel?.activeRoll?.filmStock ?? ""
            )

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
        .background(Color.black)
        .onAppear {
            if viewModel == nil {
                viewModel = FilmLogViewModel(modelContext: modelContext)
                viewModel?.setup()
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

#Preview {
    ContentView()
        .modelContainer(PreviewSampleData.makeContainer())
}
