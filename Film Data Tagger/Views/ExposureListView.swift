//
//  ExposureListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/9/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let exposureItemHeight: CGFloat = 78

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
    let logItems: [LogItemSnapshot]
    @Binding var draggingPlaceholderID: UUID?
    @Binding var dropTargetIndex: Int?
    let onMovePlaceholderBefore: ((LogItemSnapshot, LogItemSnapshot) -> Void)?
    let onMovePlaceholderAfter: ((LogItemSnapshot, LogItemSnapshot) -> Void)?

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
        guard dropTargetIndex != nil else { return false }
        guard let draggingPlaceholderID,
              let draggedItem = logItems.first(where: { $0.id == draggingPlaceholderID }),
              draggedItem.exposureType.isPlaceholderLike,
              index < logItems.count else {
            return false
        }

        let targetIdx = info.location.y < exposureItemHeight / 2 ? index : index + 1
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
        let deadZone: CGFloat = 8
        if info.location.y >= midY - deadZone && info.location.y <= midY + deadZone {
            dropTargetIndex = nil
        } else {
            dropTargetIndex = info.location.y < midY ? index : index + 1
        }
    }
}

private struct ExposureEndDropDelegate: DropDelegate {
    let endIndex: Int
    let logItems: [LogItemSnapshot]
    @Binding var draggingPlaceholderID: UUID?
    @Binding var dropTargetIndex: Int?
    let onMovePlaceholderToEnd: ((LogItemSnapshot) -> Void)?

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
        guard dropTargetIndex != nil else { return false }
        guard let draggingPlaceholderID,
              let draggedItem = logItems.first(where: { $0.id == draggingPlaceholderID }),
              draggedItem.exposureType.isPlaceholderLike,
              let onMovePlaceholderToEnd else {
            return false
        }
        onMovePlaceholderToEnd(draggedItem)
        return true
    }
}

private struct ExposureRow: View, Equatable {
    let item: LogItemSnapshot
    let exposureNumber: Int?
    var isPreFrame: Bool = false
    var canCycleExtraExposures: Bool = false
    var canDoubleTapCycleExtraExposures: Bool = false
    var menuContext: (any ExposureMenuContext)?
    var onCameraSwitched: ((UUID) -> Void)?
    var onDelete: ((LogItemSnapshot) -> Void)?
    var onCycleExtraExposures: (() -> Void)?

    static func == (lhs: ExposureRow, rhs: ExposureRow) -> Bool {
        lhs.item == rhs.item &&
        lhs.exposureNumber == rhs.exposureNumber &&
        lhs.isPreFrame == rhs.isPreFrame &&
        lhs.canCycleExtraExposures == rhs.canCycleExtraExposures &&
        lhs.canDoubleTapCycleExtraExposures == rhs.canDoubleTapCycleExtraExposures
    }

    var body: some View {
        ExposureLogItemView(item: item, exposureNumber: exposureNumber, isPreFrame: isPreFrame, onCycleExtraExposures: canCycleExtraExposures ? onCycleExtraExposures : nil, onDoubleTapCycleExtraExposures: canDoubleTapCycleExtraExposures ? onCycleExtraExposures : nil)
            .frame(height: exposureItemHeight, alignment: .center)
            .contentShape(Rectangle())
            .contextMenu {
                if let menuContext {
                    Menu {
                        MoveToRollMenu(item: item, menuContext: menuContext, onCameraSwitched: onCameraSwitched)
                    } label: {
                        Label("Move", systemImage: "rectangle.portrait.and.arrow.forward")
                    }
                }
                Button(role: .destructive) {
                    onDelete?(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }.frame(height: exposureItemHeight)
    }
}

/// Context menu content for moving an exposure to another roll.
/// Reads from ExposureMenuContext — only re-renders when cameras/rolls change, not when items change.
private struct MoveToRollMenu: View {
    let item: LogItemSnapshot
    let menuContext: any ExposureMenuContext
    var onCameraSwitched: ((UUID) -> Void)?

    private func rollSubtitle(_ roll: MenuRollEntry) -> String {
        var parts = "\(roll.exposureCount) / \(roll.totalCapacity)"
        if let lastDate = roll.lastExposureDate {
            let ago = relativeTimeString(from: lastDate, suffix: true)
            parts += " · \(ago)"
        }
        return parts
    }

    var body: some View {
        // Other cameras with active rolls
        let otherCameras = menuContext.menuCameras.filter { $0.id != menuContext.currentCameraID && $0.activeRollID != nil }
        ForEach(otherCameras) { camera in
            if let rollID = camera.activeRollID {
                Button {
                    menuContext.moveItem(item, toRollID: rollID)
                    onCameraSwitched?(camera.id)
                } label: {
                    Text(camera.name)
                    Text(camera.activeRollName ?? "")
                }
            }
        }

        // Current camera's other rolls
        let otherRolls = menuContext.menuRolls
            .filter { $0.id != menuContext.currentRollID }
            .sorted { ($0.lastExposureDate ?? .distantPast) > ($1.lastExposureDate ?? .distantPast) }
        if !otherRolls.isEmpty, let cameraName = menuContext.menuCameras.first(where: { $0.id == menuContext.currentCameraID })?.name {
            Menu {
                ForEach(otherRolls) { roll in
                    Button {
                        menuContext.moveItem(item, toRollID: roll.id)
                    } label: {
                        Text(roll.name)
                        Text(rollSubtitle(roll))
                    }
                }
            } label: {
                Text(cameraName)
            }
        }
    }
}

/// Camera switcher menu. Reads from ExposureMenuContext — only re-renders when camera list changes.
private struct CameraSwitcherMenu: View {
    let cameraName: String
    let filmStock: String
    let menuContext: any ExposureMenuContext
    var onCameraSwitched: ((UUID) -> Void)?

    private var cameraID: UUID? { menuContext.currentCameraID }

    private var camerasWithActiveRolls: [MenuCameraEntry] {
        menuContext.menuCameras.filter { $0.activeRollID != nil }
    }

    private static func subtitle(for camera: MenuCameraEntry) -> String {
        guard camera.activeRollID != nil else { return "" }
        var result = "Frame \(camera.activeRollExposureCount - camera.activeRollExtraExposures + 1)"
        if let lastDate = camera.lastUsedDate {
            let ago = relativeTimeString(from: lastDate, suffix: true)
            result += " · \(ago)"
        }
        return result
    }

    var body: some View {
        Menu {
            ForEach(camerasWithActiveRolls) { camera in
                Button {
                    menuContext.switchToCameraActiveRoll(camera.id)
                    onCameraSwitched?(camera.id)
                } label: {
                    if camera.id == cameraID {
                        Label(camera.name, systemImage: "checkmark")
                    } else {
                        Text(camera.name)
                    }
                    Text(Self.subtitle(for: camera))
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
            .frame(minWidth: 250, maxWidth: UIScreen.currentWidth - 32 - 44 - 44 - 12 - 12, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Switch camera")
        .accessibilityHint("Opens a menu to switch between cameras with active rolls")
    }
}

struct ExposureListView: View {
    let logItems: [LogItemSnapshot]
    var cameraName: String = ""
    var filmStock: String = ""
    var extraExposures: Int = 0
    var isActiveRoll: Bool = true
    var bottomInset: CGFloat = CaptureSheet.fullHeight
    var nearBottomThreshold: CGFloat = 300
    let pastRollOverscroll: CGFloat = 150
    var scrollContextID: UUID? = nil
    var onDelete: ((LogItemSnapshot) -> Void)?
    var onMovePlaceholderBefore: ((LogItemSnapshot, LogItemSnapshot) -> Void)?
    var onMovePlaceholderAfter: ((LogItemSnapshot, LogItemSnapshot) -> Void)?
    var onMovePlaceholderToEnd: ((LogItemSnapshot) -> Void)?
    var onCycleExtraExposures: (() -> Void)?
    var onNearBottomChanged: ((Bool) -> Void)?
    var onScrollToBottomRegistered: ((@escaping () -> Void) -> Void)?
    var menuContext: (any ExposureMenuContext)?
    var onCameraSwitched: ((UUID) -> Void)?
    var onUnloadRoll: (() -> Void)?
    var onLoadRoll: (() -> Void)?
    var onAddPlaceholder: (() -> Void)?
    var onAddLostFrame: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var draggingPlaceholderID: UUID?
    @State private var dropTargetIndex: Int?

    var totalBottomPadding: CGFloat {
        isActiveRoll ? 278 + 118 + 40 - 8 : pastRollOverscroll
    }
    var overscrollHeight: CGFloat {
        isActiveRoll ? bottomInset + 118 : pastRollOverscroll
    }

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
                    canCycleExtraExposures: index < 4 && isActiveRoll && AppSettings.shared.preFramesEnabled,
                    canDoubleTapCycleExtraExposures: index < 4 && !isActiveRoll && AppSettings.shared.preFramesEnabled,
                    menuContext: menuContext,
                    onCameraSwitched: onCameraSwitched,
                    onDelete: onDelete,
                    onCycleExtraExposures: onCycleExtraExposures
                )
                .equatable()
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.12)), removal: .identity))
                .contentShape(Rectangle())
                .id(item.id)
                .if(item.exposureType.isPlaceholderLike) { view in
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
        .padding(.leading, 16 - 12)
        .padding(.trailing, 16)
        .padding(.top, 118)

        // Overscroll / drop zone for moving placeholders to end of list
        Color.clear
            .frame(height: overscrollHeight)
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
            .frame(height: totalBottomPadding - overscrollHeight)
    }

    var body: some View {
        Group {
            if logItems.isEmpty {
                Text("start your roll!")
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 153)
                    .padding(.top, 18)
                    .offset(y: -15)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        exposureScrollContent()
                            .frame(minHeight: UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.height ?? 800, alignment: .top) // align to top
                    }
                    .defaultScrollAnchor(.bottom)
                    .onAppear {
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
                        return currentOffset >= maxOffset - nearBottomThreshold
                    } action: { _, isNearBottom in
                        onNearBottomChanged?(isNearBottom)
                    }
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }.frame(width: 44, height: 44)
                    .glassEffectCompat(in: Circle())
                    .accessibilityLabel("Back")
                    .padding(.trailing, 12)
                    if let menuContext {
                        CameraSwitcherMenu(
                            cameraName: cameraName,
                            filmStock: filmStock,
                            menuContext: menuContext,
                            onCameraSwitched: onCameraSwitched
                        )
                        .padding(.trailing, 12)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button {
                            // TODO: Details
                        } label: {
                            Label("Details", systemImage: "info.circle")
                        }
                        if isActiveRoll {
                            Button {
                                onUnloadRoll?()
                            } label: {
                                Label("Unload roll", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
                            }
                        } else {
                            Button {
                                onLoadRoll?()
                            } label: {
                                Label("Load roll", systemImage: "arrow.clockwise")
                            }
                        }
                        Button {
                            playHaptic(.addPlaceholder)
                            onAddPlaceholder?()
                        } label: {
                            Label("Add placeholder", systemImage: "questionmark.square.dashed")
                        }
                        Button {
                            playHaptic(.addPlaceholder)
                            onAddLostFrame?()
                        } label: {
                            Label("Add lost frame", systemImage: "xmark.square")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .glassEffectCompat(in: Circle())
                    }
                    .accessibilityLabel("Roll options")
                }
                .frame(width: UIScreen.currentWidth - 32, height: 44)
            }
        }
        .preferredColorScheme(.dark)
        .id(scrollContextID)
    }
}

#Preview("With items") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container).map { $0.snapshot }
    NavigationStack {
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
