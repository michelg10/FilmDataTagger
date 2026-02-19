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
    static let fullDetent: PresentationDetent = .height(CGFloat(283 - iOSSheetPadding))
    
    @State private var selectedDetent: PresentationDetent = fullDetent
    
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
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .opacity(0.95)
            }
        }
    }
    
    struct CaptureSheetFullInfo<Icon: View>: View {
        var icon: Icon
        var text: String
        var subtext: String
        var textSubtextPadding: CGFloat = 0

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                icon
                    .frame(width: 21, height: 25, alignment: .center)
                    .opacity(0.8)
                VStack(alignment: .leading, spacing: textSubtextPadding) {
                    Text(text)
                        .lineLimit(2)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .opacity(0.95)
                    Text(subtext)
                        .lineLimit(1)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .opacity(0.65)
                }
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
                }.padding(.horizontal, 30)
                .padding(.bottom, 15)
                .transition(.opacity.combined(with: .offset(y: 20)))
            case CaptureSheet.fullDetent:
                HStack(spacing: 18) {
                    Image("test-image")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 143, height: 143)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(alignment: .leading, spacing: 10) {
                        CaptureSheetFullInfo(
                            icon: Image(systemName: "clock.fill")
                                .font(.system(size: 17, weight: .semibold, design: .default)),
                            text: "30m",
                            subtext: "since last capture"
                        )
                        CaptureSheetFullInfo(
                            icon: Image(systemName: "location.fill")
                                .font(.system(size: 17, weight: .semibold, design: .default)),
                            text: "The University of Hong Kong",
                            subtext: "32.1234 / 53.5213",
                            textSubtextPadding: 3.0
                        )
                    }
                }
                .padding(.bottom, 21)
                .padding(.horizontal, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .offset(y: 30)))
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
                .font(.system(size: 22, weight: .bold, design: .default))
                .fontWidth(.expanded)
            }.frame(height: 63)
            .glassEffect(.regular.tint(.white.opacity(0.87)).interactive(), in: Capsule(style: .continuous))
            .padding(.horizontal, 15)
            .padding(.bottom, 34)

        }.animation(.easeOut(duration: 0.15), value: selectedDetent)
        .padding(.horizontal, 8)
        .ignoresSafeArea()
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
        Group {
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
                }
                .sheet(isPresented: $showSheet) {
                    CaptureSheet()
                        .sheet(isPresented: .constant(false)) {
                            Text("hello, world!")
                        }
                }
                .sheetFloatingView(offset: -10) {
                    Button {
                        // TODO
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
