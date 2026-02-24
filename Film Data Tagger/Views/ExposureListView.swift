//
//  ExposureListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/9/26.
//

import SwiftUI
import SwiftData

private struct ExposureRow: View {
    let item: LogItem
    let logItems: [LogItem]
    var onDelete: ((LogItem) -> Void)?
    var onMovePlaceholderBefore: ((LogItem, LogItem) -> Void)?
    var onMovePlaceholderAfter: ((LogItem, LogItem) -> Void)?
    var onCycleExtraExposures: (() -> Void)?

    var body: some View {
        ExposureLogItemView(item: item, onCycleExtraExposures: onCycleExtraExposures)
            .id(item.id)
            .padding(.vertical, 8) // 2 * 8pt = 16pt spacing between items; padding allows context menu hit testing
            .contextMenu {
                Button(role: .destructive) {
                    onDelete?(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .if(item.isPlaceholder) { view in
                view.draggable(item.id.uuidString)
            }
            .dropDestination(for: String.self) { droppedItems, _ in
                guard let droppedId = droppedItems.first,
                      let droppedUUID = UUID(uuidString: droppedId),
                      let droppedItem = logItems.first(where: { $0.id == droppedUUID }),
                      droppedItem.isPlaceholder,
                      droppedItem.id != item.id else { return false }
                // Dragging down (item was before target) → place after target
                // Dragging up (item was after target) → place before target
                if droppedItem.createdAt < item.createdAt {
                    onMovePlaceholderAfter?(droppedItem, item)
                } else {
                    onMovePlaceholderBefore?(droppedItem, item)
                }
                return true
            }
    }
}

struct ExposureListView: View {
    let logItems: [LogItem]
    var cameraName: String = ""
    var filmStock: String = ""
    var hasRoll: Bool = true
    @Binding var isScrolling: Bool
    var onDelete: ((LogItem) -> Void)?
    var onMovePlaceholderBefore: ((LogItem, LogItem) -> Void)?
    var onMovePlaceholderAfter: ((LogItem, LogItem) -> Void)?
    var onMovePlaceholderToEnd: ((LogItem) -> Void)?
    var onCycleExtraExposures: (() -> Void)?
    var onTitleTapped: (() -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if logItems.isEmpty {
                    if hasRoll {
                        Text("start your roll!")
                            .font(.system(size: 25, weight: .bold, design: .default))
                            .fontWidth(.expanded)
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.bottom, 227)
                            .padding(.top, 18)
                            .offset(y: -21)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(logItems) { item in
                                    ExposureRow(
                                        item: item,
                                        logItems: logItems,
                                        onDelete: onDelete,
                                        onMovePlaceholderBefore: onMovePlaceholderBefore,
                                        onMovePlaceholderAfter: onMovePlaceholderAfter,
                                        onCycleExtraExposures: onCycleExtraExposures
                                    )
                                }
                            }
                            .animation(.easeOut(duration: 0.25), value: logItems.map(\.id))
                            .padding(.horizontal, 16)
                            .offset(y: -21)

                            // Drop zone for moving placeholders to end of list
                            Color.clear
                                .frame(height: 396)
                                .contentShape(Rectangle())
                                .dropDestination(for: String.self) { droppedItems, _ in
                                    guard let droppedId = droppedItems.first,
                                          let droppedUUID = UUID(uuidString: droppedId),
                                          let droppedItem = logItems.first(where: { $0.id == droppedUUID }),
                                          droppedItem.isPlaceholder else { return false }
                                    onMovePlaceholderToEnd?(droppedItem)
                                    return true
                                }
                                .id("scrollAnchor")

                            Spacer()
                                .frame(height: 40 - 8)
                        }
                        .onAppear {
                            if !logItems.isEmpty {
                                proxy.scrollTo("scrollAnchor", anchor: .bottom)
                            }
                        }
                        .onChange(of: logItems.count) { oldCount, newCount in
                            if newCount > oldCount {
                                withAnimation {
                                    proxy.scrollTo("scrollAnchor", anchor: .bottom)
                                }
                            }
                        }
                        .onScrollPhaseChange { _, newPhase in
                            isScrolling = newPhase == .interacting
                        }
                    }
                }
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // the button was here, but hit testing with a toolbar item was funny, so we use a placeholder rectangle here to maintain the glass-y blur effect but move the button into an overlay where hit testing is reliable
                    Rectangle()
                        .frame(width: UIScreen.main.bounds.width - 32, height: 96)
                        .opacity(0.00001)
                }
            }
            .preferredColorScheme(.dark)
        }.overlay(alignment: .top) {
            Button {
                onTitleTapped?()
            } label: {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(cameraName)
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .fontWidth(.expanded)
                            .foregroundStyle(Color.white)
                            .padding(.top, 7)
                        Text(filmStock)
                            .font(.system(size: 20, weight: .bold, design: .default))
                            .foregroundStyle(Color(hex: 0xAAAAAA))
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16)
                .frame(height: 81, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 59)
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
