//
//  ContentView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

struct FinishRollButton: View {
    var action: () -> Void

    var body: some View {
        Button {
            playHaptic(.finishRoll)
            action()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .padding(.bottom, 2)
                    .frame(width: 18, height: 18, alignment: .center)
                    .padding(.leading, 15)
                Text("Finish roll")
                    .padding(.trailing, 19)
                    .font(.system(size: 17, weight: .semibold, design: .default))
            }.foregroundStyle(Color.white.opacity(0.95))
            .fontWidth(.expanded)
        }.frame(height: 44)
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
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
                    cameraName: viewModel?.activeRoll?.camera?.name ?? "",
                    filmStock: viewModel?.activeRoll?.filmStock ?? "",
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
                FinishRollButton(action: {
                    showNewRoll = true
                })
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
