//
//  ContentView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

struct CaptureSheet: View {
    static let iOSSheetPadding = 27
    static let compactDetent: PresentationDetent = .height(CGFloat(147 - iOSSheetPadding))
    static let fullDetent: PresentationDetent = .height(CGFloat(278 - iOSSheetPadding))
    
    @State private var selectedDetent: PresentationDetent = compactDetent
    
    struct CaptureSheetCompactInfo<Icon: View>: View {
        var icon: Icon
        var text: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                icon
                    .frame(width: 21, height: 25, alignment: .center)
                    .opacity(0.8)
                Text(text)
                    .lineLimit(1)
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .opacity(0.95)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            switch selectedDetent {
            case CaptureSheet.compactDetent:
                HStack(spacing: 15) {
                    CaptureSheetCompactInfo(
                        icon: Image(systemName: "clock.fill")
                            .font(.system(size: 16, weight: .semibold, design: .default)),
                        text: "30m"
                    )
                    CaptureSheetCompactInfo(
                        icon: Image(systemName: "location.fill")
                            .font(.system(size: 15, weight: .semibold, design: .default)),
                        text: "The University of Hong Kong"
                    )
                }.padding(.horizontal, 32)
                .padding(.bottom, 16)
                
            default:
                EmptyView()
            }
            Button {
                // TODO
            } label: {
                HStack (alignment: .firstTextBaseline, spacing: 0) {
                    Spacer(minLength: 0)
                    Text("12 / 36 •")
                        .opacity(0.46)
                    Text(" Capture")
                    Spacer(minLength: 0)
                }.foregroundStyle(Color.black)
                    .font(.system(size: 23, weight: .bold, design: .default))
                    .fontWidth(.expanded)
            }.frame(height: 66)
                .glassEffect(.regular.tint(.white.opacity(0.87)).interactive(), in: Capsule(style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 27)

        }.ignoresSafeArea()
            .presentationDetents([CaptureSheet.compactDetent, CaptureSheet.fullDetent], selection: $selectedDetent)
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
            .presentationBackgroundInteraction(.enabled)
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

    var body: some View {
        ZStack(alignment: .bottom) {
            ExposureListView(
                logItems: logItems,
                cameraName: viewModel?.activeRoll?.camera?.name ?? "",
                filmStock: viewModel?.activeRoll?.filmStock ?? ""
            )
        }.ignoresSafeArea(.all)
        .background(Color.black)
        .onAppear {
            if viewModel == nil {
                viewModel = FilmLogViewModel(modelContext: modelContext)
                viewModel?.setup()
            }
        }.sheet(isPresented: $showSheet) {
            CaptureSheet()
        }.onAppear {
            // hack to disable sheet animation
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showSheet = true
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSampleData.makeContainer())
}
