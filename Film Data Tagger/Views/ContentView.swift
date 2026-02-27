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
    var isNearBottom: Bool
    var action: () -> Void
    let shadow1Opacity: Double = 0.36
    let shadow1Radius: Double = 24.8
    let shadow2Opacity: Double = 0.5
    let shadow2Radius: Double = 6.9

    var body: some View {
        Button {
            action()
        } label: {
            if isNearBottom {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .padding(.leading, 14)
                    Text(text)
                        .padding(.trailing, 21)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .transition(.identity)
                }.foregroundStyle(Color.white.opacity(0.95))
                    .fontWidth(.expanded)
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 48)
            }
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
    @State private var isNearBottom = true
    @State private var scrollToBottom: (() -> Void)?


    private var logItems: [LogItem] {
        viewModel?.logItems ?? []
    }

    var body: some View {
        Group {
            ZStack {
                ExposureListView(
                    logItems: logItems,
                    cameraName: viewModel?.openCamera?.name ?? "No camera selected",
                    filmStock: viewModel?.openRoll?.filmStock
                        ?? (viewModel?.openCamera != nil ? "No roll selected" : ""),
                    hasRoll: viewModel?.openRoll != nil,
                    scrollContextID: viewModel?.openRoll?.id ?? viewModel?.openCamera?.id,
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
                    onCycleExtraExposures: {
                        viewModel?.cycleExtraExposures()
                    },
                    onTitleTapped: {
                        showCameraList = true
                    },
                    onNearBottomChanged: { isNearBottom = $0 },
                    onScrollToBottomRegistered: { scrollToBottom = $0 }
                )
            }.ignoresSafeArea(.all)
            .background(Color.black)
            .sheet(isPresented: $showSheet) {
                if let viewModel {
                    CaptureSheet(
                        viewModel: viewModel,
                        frameCount: logItems.count + 1,
                        rollCapacity: viewModel.rollCapacity,
                        lastCaptureDate: logItems.last(where: { $0.hasRealCreatedAt })?.createdAt
                    )
                    .sheet(isPresented: $showCameraList) {
                        CameraListView(viewModel: viewModel)
                    }.sheet(isPresented: $showNewRoll) {
                        if let camera = viewModel.openCamera {
                            RollFormSheet(viewModel: viewModel, camera: camera)
                        }
                    }
                }
            }
            .sheetFloatingView(offset: 20, height: 48, compensationPoints: [
                (sheetHeight: CaptureSheet.compactScaledHeight, compensation: -2),
                (sheetHeight: CaptureSheet.fullScaledHeight, compensation: 4),
            ]) {
                if viewModel?.openRoll != nil {
                    FinishRollButton(isNearBottom: isNearBottom, action: {
                        if isNearBottom {
                            showNewRoll = true
                            playHaptic(.newRollOrCamera)
                        } else {
                            scrollToBottom?()
                        }
                    })
                    .animation(.easeInOut(duration: 0.25), value: isNearBottom)
                } else if viewModel?.openCamera != nil {
                    FinishRollButton(icon: "plus", text: "New roll", isNearBottom: false, action: {
                        showNewRoll = true
                        playHaptic(.newRollOrCamera)
                    })
                } else {
                    EmptyView()
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = FilmLogViewModel(modelContext: modelContext)
                    viewModel?.setup()
                }
                if !showSheet {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showSheet = true
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSampleData.makeContainer())
}
