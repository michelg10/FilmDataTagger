//
//  ExposureListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/9/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let exposureItemHeight: CGFloat = 76

private struct ExposureDropIndicatorLine: View {
    var active: Bool

    var body: some View {
        Capsule()
            .foregroundStyle(Color.white.opacity(0.27))
            .frame(height: 2)
            .padding(.horizontal, 8)
            .opacity(active ? 1 : 0)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: active)
    }
}

private struct ExposureRowDropDelegate: DropDelegate {
    let index: Int
    let logItems: [LogItem]
    @Binding var draggingPlaceholderID: UUID?
    @Binding var dropTargetIndex: Int?
    let onMovePlaceholderBefore: ((LogItem, LogItem) -> Void)?
    let onMovePlaceholderAfter: ((LogItem, LogItem) -> Void)?

    func dropEntered(info: DropInfo) {
        updateTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        let myIndices = [index, index + 1]
        if let current = dropTargetIndex, myIndices.contains(current) {
            dropTargetIndex = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropTargetIndex = nil; draggingPlaceholderID = nil }
        let targetIdx = info.location.y < exposureItemHeight / 2 ? index : index + 1
        guard let draggingPlaceholderID,
              let draggedItem = logItems.first(where: { $0.id == draggingPlaceholderID }),
              draggedItem.isPlaceholder else {
            return false
        }

        let targetItem = logItems[index]
        if targetIdx == index {
            onMovePlaceholderBefore?(draggedItem, targetItem)
        } else {
            onMovePlaceholderAfter?(draggedItem, targetItem)
        }
        return true
    }

    private func updateTarget(info: DropInfo) {
        guard let draggingPlaceholderID, draggingPlaceholderID != logItems[index].id else {
            return
        }
        let midY = exposureItemHeight / 2
        let deadZone: CGFloat = 5
        if info.location.y >= midY - deadZone && info.location.y <= midY + deadZone {
            dropTargetIndex = nil
        } else {
            dropTargetIndex = info.location.y < midY ? index : index + 1
        }
    }
}

private struct ExposureEndDropDelegate: DropDelegate {
    let endIndex: Int
    let logItems: [LogItem]
    @Binding var draggingPlaceholderID: UUID?
    @Binding var dropTargetIndex: Int?
    let onMovePlaceholderToEnd: ((LogItem) -> Void)?

    private var isAlreadyLast: Bool {
        guard let draggingPlaceholderID else { return false }
        return logItems.last?.id == draggingPlaceholderID
    }

    func dropEntered(info: DropInfo) {
        guard draggingPlaceholderID != nil else { return }
        dropTargetIndex = isAlreadyLast ? nil : endIndex
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingPlaceholderID != nil else { return nil }
        dropTargetIndex = isAlreadyLast ? nil : endIndex
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetIndex == endIndex { dropTargetIndex = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropTargetIndex = nil; draggingPlaceholderID = nil }
        guard let draggingPlaceholderID,
              let draggedItem = logItems.first(where: { $0.id == draggingPlaceholderID }),
              draggedItem.isPlaceholder,
              let onMovePlaceholderToEnd else {
            return false
        }
        onMovePlaceholderToEnd(draggedItem)
        return true
    }
}

private struct ExposureRow: View {
    let item: LogItem
    var onDelete: ((LogItem) -> Void)?
    var onCycleExtraExposures: (() -> Void)?

    var body: some View {
        ExposureLogItemView(item: item, onCycleExtraExposures: onCycleExtraExposures)
            .id(item.id)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .frame(height: exposureItemHeight, alignment: .center)
            .contextMenu {
                Button(role: .destructive) {
                    onDelete?(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

struct ExposureListView: View {
    let logItems: [LogItem]
    var cameraName: String = ""
    var filmStock: String = ""
    var hasRoll: Bool = true
    var scrollContextID: UUID? = nil
    var onDelete: ((LogItem) -> Void)?
    var onMovePlaceholderBefore: ((LogItem, LogItem) -> Void)?
    var onMovePlaceholderAfter: ((LogItem, LogItem) -> Void)?
    var onMovePlaceholderToEnd: ((LogItem) -> Void)?
    var onCycleExtraExposures: (() -> Void)?
    var onTitleTapped: (() -> Void)?
    var onNearBottomChanged: ((Bool) -> Void)?
    var onScrollToBottomRegistered: ((@escaping () -> Void) -> Void)?
    @State private var draggingPlaceholderID: UUID?
    @State private var dropTargetIndex: Int?

    private func publishScrollActivity(_ isActive: Bool) {
        ExposureListScrollActivity.setActive(isActive)
    }

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
                            VStack(spacing: 0) {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(logItems.enumerated()), id: \.element.id) { index, item in
                                        ExposureRow(
                                            item: item,
                                            onDelete: onDelete,
                                            onCycleExtraExposures: onCycleExtraExposures
                                        )
                                        .if(item.isPlaceholder) { view in
                                            view.onDrag {
                                                draggingPlaceholderID = item.id
                                                return NSItemProvider(object: item.id.uuidString as NSString)
                                            }
                                        }
                                        .overlay(alignment: .top) {
                                            ExposureDropIndicatorLine(active: dropTargetIndex == index)
                                                .offset(y: -1)
                                                .allowsHitTesting(false)
                                        }.contentShape(Rectangle())
                                        .onDrop(
                                            of: [UTType.plainText],
                                            delegate: ExposureRowDropDelegate(
                                                index: index,
                                                logItems: logItems,
                                                draggingPlaceholderID: $draggingPlaceholderID,
                                                dropTargetIndex: $dropTargetIndex,
                                                onMovePlaceholderBefore: onMovePlaceholderBefore,
                                                onMovePlaceholderAfter: onMovePlaceholderAfter
                                            )
                                        )
                                    }
                                }
                                .animation(.easeOut(duration: 0.25), value: logItems.map(\.id))
                                .padding(.horizontal, 16)
                                .offset(y: -21)

                                // Overscroll / drop zone for moving placeholders to end of list
                                Color.clear
                                    .frame(height: 396)
                                    .contentShape(Rectangle())
                                    .overlay(alignment: .top) {
                                        ExposureDropIndicatorLine(active: dropTargetIndex == logItems.count)
                                            .padding(.horizontal, 16)
                                            .offset(y: -1)
                                    }
                                    .onDrop(
                                        of: [UTType.plainText],
                                        delegate: ExposureEndDropDelegate(
                                            endIndex: logItems.count,
                                            logItems: logItems,
                                            draggingPlaceholderID: $draggingPlaceholderID,
                                            dropTargetIndex: $dropTargetIndex,
                                            onMovePlaceholderToEnd: onMovePlaceholderToEnd
                                        )
                                    )
                                    .offset(y: -21)
                                    .id("scrollAnchor")
                                
                                Spacer()
                                    .frame(height: 40 - 8)
                            }
                        }
                        .onAppear {
                            if !logItems.isEmpty {
                                proxy.scrollTo("scrollAnchor", anchor: .bottom)
                            }
                            onScrollToBottomRegistered?({
                                withAnimation {
                                    proxy.scrollTo("scrollAnchor", anchor: .bottom)
                                }
                            })
                        }
                        .onChange(of: logItems.count) { oldCount, newCount in
                            if newCount > oldCount {
                                withAnimation {
                                    proxy.scrollTo("scrollAnchor", anchor: .bottom)
                                }
                            }
                        }
                        .onScrollGeometryChange(for: Bool.self) { geo in
                            let maxOffset = geo.contentSize.height - geo.containerSize.height + geo.contentInsets.bottom
                            let currentOffset = geo.contentOffset.y + geo.contentInsets.top
                            return currentOffset >= maxOffset - 500
                        } action: { prevIsNearBottom, isNearBottom in
                            if prevIsNearBottom != isNearBottom {
                                onNearBottomChanged?(isNearBottom)
                            }
                        }
                        .onScrollPhaseChange { _, newPhase in
                            publishScrollActivity(newPhase == .interacting)
                        }
                        .onDisappear {
                            publishScrollActivity(false)
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
        }.id(scrollContextID)
    }
}

#Preview("With items") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container)
    return ExposureListView(
        logItems: items,
        cameraName: "Olympus XA",
        filmStock: "Fuji Color 400"
    )
    .modelContainer(container)
}

#Preview("Empty") {
    ExposureListView(
        logItems: [],
        cameraName: "Olympus XA",
        filmStock: "Fuji Color 400"
    )
    .modelContainer(for: [Camera.self, Roll.self, LogItem.self], inMemory: true)
}
