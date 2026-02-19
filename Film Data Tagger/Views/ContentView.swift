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
            }.foregroundStyle(Color.white)
                .fontWidth(.expanded)
        }.frame(height: 44)
            .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<LogItem> { $0.deletedAt == nil },
           sort: \LogItem.createdAt,
           order: .forward)
    private var logItems: [LogItem]

    @State private var viewModel: FilmLogViewModel?
    @State private var showSheet = false
    @State private var isScrolling = false

    var body: some View {
        Group {
            ZStack(alignment: .bottom) {
                ExposureListView(
                    logItems: logItems,
                    cameraName: viewModel?.activeRoll?.camera?.name ?? "",
                    filmStock: viewModel?.activeRoll?.filmStock ?? "",
                    isScrolling: $isScrolling
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
                    CaptureSheet(onCapture: {
                        viewModel?.logExposure()
                    }, isScrolling: isScrolling)
                    .sheet(isPresented: .constant(false)) {
                        Text("hello, world!")
                    }
                }
                .sheetFloatingView(offset: -10) {
                    FinishRollButton(action: {
                        viewModel?.finishRoll()
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
