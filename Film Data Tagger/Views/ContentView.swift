//
//  ContentView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

struct FinishRollButton: View {
    var icon: String = "checkmark.arrow.trianglehead.counterclockwise"
    var text: String = "Finish roll"
    var action: () -> Void
    var shadow1Opacity: Double = 0.36
    var shadow1Radius: Double = 24.8
    var shadow2Opacity: Double = 0.5
    var shadow2Radius: Double = 6.9

    var body: some View {
        Button {
            playHaptic(.finishRoll)
            action()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .padding(.leading, 14)
                Text(text)
                    .padding(.trailing, 21)
                    .font(.system(size: 17, weight: .semibold, design: .default))
            }.foregroundStyle(Color.white.opacity(0.95))
            .fontWidth(.expanded)
        }.frame(height: 48)
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(shadow1Opacity), radius: shadow1Radius)
        .shadow(color: .black.opacity(shadow2Opacity), radius: shadow2Radius)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: FilmLogViewModel?
    @State private var showSheet = false
    @State private var showCameraList = false
    @State private var showNewRoll = false
    @State private var isScrolling = false


    private var logItems: [LogItem] {
        viewModel?.logItems ?? []
    }

    var body: some View {
        Group {
            ZStack(alignment: .bottom) {
                ExposureListView(
                    logItems: logItems,
                    cameraName: viewModel?.openCamera?.name ?? "No camera selected",
                    filmStock: viewModel?.openRoll?.filmStock
                        ?? (viewModel?.openCamera != nil ? "No roll selected" : ""),
                    hasRoll: viewModel?.openRoll != nil,
                    isScrolling: $isScrolling,
                    onDelete: { item in
                        viewModel?.deleteItem(item)
                    },
                    onMovePlaceholderBefore: { item, target in
                        viewModel?.movePlaceholder(item, before: target)
                    },
                    onMovePlaceholderAfter: { item, target in
                        viewModel?.movePlaceholder(item, after: target)
                    },
                    onMovePlaceholderToEnd: { item in
                        viewModel?.movePlaceholderToEnd(item)
                    },
                    onTitleTapped: {
                        showCameraList = true
                    }
                )
            }.ignoresSafeArea(.all)
            .background(Color.black)
            .onAppear {
                if viewModel == nil {
                    viewModel = FilmLogViewModel(modelContext: modelContext)
                    viewModel?.setup()
                }
            }
            .sheet(isPresented: $showSheet) {
                if let viewModel {
                    CaptureSheet(
                        viewModel: viewModel,
                        isScrolling: isScrolling,
                        frameCount: logItems.count + 1,
                        rollCapacity: viewModel.rollCapacity,
                        lastCaptureDate: logItems.last(where: { $0.hasRealCreatedAt })?.createdAt
                    )
                    .sheet(isPresented: $showCameraList) {
                        CameraListView(viewModel: viewModel)
                    }.sheet(isPresented: $showNewRoll) {
                        NewRollSheet(viewModel: viewModel)
                    }
                }
            }
            .sheetFloatingView(offset: 20 - 30) {
                if viewModel?.openRoll != nil {
                    FinishRollButton(action: {
                        showNewRoll = true
                    })
                } else if viewModel?.openCamera != nil {
                    FinishRollButton(icon: "plus", text: "New roll", action: {
                        showNewRoll = true
                    })
                } else {
                    EmptyView()
                }
            }
            .onAppear {
                // hack to disable sheet animation
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showSheet = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSampleData.makeContainer())
}
