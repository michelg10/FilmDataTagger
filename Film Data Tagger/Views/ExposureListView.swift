//
//  ExposureListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/9/26.
//

import SwiftUI
import SwiftData

struct ExposureListView: View {
    let contentTopOffset: CGFloat = 27
    let titleTopOffset: CGFloat = 33
    
    let logItems: [LogItem]
    var cameraName: String = ""
    var filmStock: String = ""
    @Binding var isScrolling: Bool

    var body: some View {
        NavigationStack {
            Group {
                if logItems.isEmpty {
                    Text("start your roll!")
                        .font(.system(size: 25, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 175)
                        .padding(.top, 10 + contentTopOffset)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(logItems) { item in
                                    ExposureLogItemView(item: item)
                                        .id(item.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12 + contentTopOffset)

                            Color.clear
                                .frame(height: 396)
                                .id("scrollAnchor")

                            Spacer()
                                .frame(height: 40)
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
                        .onScrollPhaseChange { _, newPhase in
                            let wasScrolling = isScrolling
                            isScrolling = newPhase == .interacting
                        }
                    }
                }
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(cameraName)
                                .font(.system(size: 28, weight: .bold, design: .default))
                                .fontWidth(.expanded)
                                .foregroundStyle(Color.white)
                            Text(filmStock)
                                .font(.system(size: 20, weight: .bold, design: .default))
                                .foregroundStyle(Color(hex: 0xAAAAAA))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: UIScreen.main.bounds.width - 32)
                    .padding(.top, titleTopOffset)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
    }
}

#Preview("With items") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container)
    return ExposureListView(
        logItems: items,
        cameraName: "Olympus XA",
        filmStock: "Fuji Color 400",
        isScrolling: .constant(false)
    )
    .modelContainer(container)
}

#Preview("Empty") {
    ExposureListView(
        logItems: [],
        cameraName: "Olympus XA",
        filmStock: "Fuji Color 400",
        isScrolling: .constant(false)
    )
    .modelContainer(for: [Camera.self, Roll.self, LogItem.self], inMemory: true)
}
