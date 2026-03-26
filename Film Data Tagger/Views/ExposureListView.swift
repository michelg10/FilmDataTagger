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
    let active: Bool

    var body: some View {
        Capsule()
            .foregroundStyle(Color.white.opacity(0.6))
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
              draggedItem.isPlaceholder,
              index < logItems.count else {
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
        guard index < logItems.count,
              let draggingPlaceholderID, draggingPlaceholderID != logItems[index].id else {
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
    let exposureNumber: Int?
    var isPreFrame: Bool = false
    var onDelete: ((LogItem) -> Void)?
    var onCycleExtraExposures: (() -> Void)?

    var body: some View {
        ExposureLogItemView(item: item, exposureNumber: exposureNumber, isPreFrame: isPreFrame, onCycleExtraExposures: onCycleExtraExposures)
            .frame(height: exposureItemHeight, alignment: .center)
            .contentShape(Rectangle())
            .contextMenu {
                Button(role: .destructive) {
                    onDelete?(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

/// Isolated view that owns `@Query cameras` so that camera changes
/// only re-render the menu, not the entire ExposureListView.
private struct CameraSwitcherMenu: View {
    let cameraName: String
    let filmStock: String
    var onCameraSelected: ((Camera) -> Void)?
    @Query private var cameras: [Camera]

    private var camerasWithActiveRolls: [Camera] {
        cameras.filter { $0.activeRoll != nil }
    }

    var body: some View {
        Menu {
            ForEach(camerasWithActiveRolls) { camera in
                Button {
                    onCameraSelected?(camera)
                } label: {
                    if camera.name == cameraName {
                        Label(camera.name, systemImage: "checkmark")
                    } else {
                        Text(camera.name)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(cameraName)
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                Text(filmStock)
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white.opacity(0.6))
            }.padding(.vertical, 2)
            .frame(height: 44, alignment: .leading)
            .frame(minWidth: 250, maxWidth: UIScreen.currentWidth - 32 - 44 - 12, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Switch camera")
        .accessibilityHint("Opens a menu to switch between cameras with active rolls")
    }
}

struct ExposureListView: View {
    let logItems: [LogItem]
    var cameraName: String = ""
    var filmStock: String = ""
    var hasRoll: Bool = true
    var extraExposures: Int = 0
    var scrollContextID: UUID? = nil
    var onDelete: ((LogItem) -> Void)?
    var onMovePlaceholderBefore: ((LogItem, LogItem) -> Void)?
    var onMovePlaceholderAfter: ((LogItem, LogItem) -> Void)?
    var onMovePlaceholderToEnd: ((LogItem) -> Void)?
    var onCycleExtraExposures: (() -> Void)?
    var onNearBottomChanged: ((Bool) -> Void)?
    var onScrollToBottomRegistered: ((@escaping () -> Void) -> Void)?
    var onCameraSelected: ((Camera) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var draggingPlaceholderID: UUID?
    @State private var dropTargetIndex: Int?

    @ViewBuilder
    private func exposureScrollContent() -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(logItems.enumerated()), id: \.element.id) { index, item in
                let isPreFrame = index < extraExposures
                let frameNumber: Int? = isPreFrame ? nil : index - extraExposures + 1
                ExposureRow(
                    item: item,
                    exposureNumber: frameNumber,
                    isPreFrame: isPreFrame,
                    onDelete: onDelete,
                    onCycleExtraExposures: onCycleExtraExposures
                )
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .contentShape(Rectangle())
                .id(item.id)
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
                }.onDrop(
                    of: [UTType.plainText],
                    delegate: ExposureRowDropDelegate(
                        index: index,
                        logItems: logItems,
                        draggingPlaceholderID: $draggingPlaceholderID,
                        dropTargetIndex: $dropTargetIndex,
                        onMovePlaceholderBefore: onMovePlaceholderBefore,
                        onMovePlaceholderAfter: onMovePlaceholderAfter
                    )
                ).frame(height: exposureItemHeight)
            }
        }
        .animation(.easeOut(duration: 0.25), value: logItems.map(\.id))
        .padding(.horizontal, 16)
        .padding(.top, 119)

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
            .id("scrollAnchor")

        Color.clear
            .frame(height: 40 - 8)
    }

    var body: some View {
        Group {
            if logItems.isEmpty {
                if hasRoll {
                    Text("start your roll!")
                        .font(.system(size: 25, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 153)
                        .padding(.top, 18)
                        .offset(y: -21)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        exposureScrollContent()
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
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }.frame(width: 44, height: 44)
                    .glassEffectCompat(in: Circle())
                    .accessibilityLabel("Back")
                    CameraSwitcherMenu(
                        cameraName: cameraName,
                        filmStock: filmStock,
                        onCameraSelected: onCameraSelected
                    )
                }
                .frame(width: UIScreen.currentWidth - 32, height: 44, alignment: .leading)
            }
        }
        .preferredColorScheme(.dark)
        .id(scrollContextID)
    }
}

#Preview("With items") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container)
    return NavigationStack {
        ExposureListView(
            logItems: items,
            cameraName: "Olympus XA",
            filmStock: "Fuji Color 400"
        )
    }
    .modelContainer(container)
}

#Preview("Empty") {
    NavigationStack {
        ExposureListView(
            logItems: [],
            cameraName: "Olympus XA",
            filmStock: "Fuji Color 400"
        )
    }
    .modelContainer(for: [Camera.self, Roll.self, LogItem.self], inMemory: true)
}
