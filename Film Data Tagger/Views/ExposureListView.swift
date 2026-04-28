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
              draggedItem.exposureType.isReorderable,
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
              draggedItem.exposureType.isReorderable,
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
    var frameNumberTapCount: Int = 1
    var menuContext: (any ExposureMenuContext)?
    var onCameraSwitched: ((UUID) -> Void)?
    var onDelete: ((LogItemSnapshot) -> Void)?
    var onCycleExtraExposures: (() -> Void)?

    static func == (lhs: ExposureRow, rhs: ExposureRow) -> Bool {
        lhs.item == rhs.item &&
        lhs.exposureNumber == rhs.exposureNumber &&
        lhs.isPreFrame == rhs.isPreFrame &&
        lhs.frameNumberTapCount == rhs.frameNumberTapCount
    }

    var body: some View {
        ExposureLogItemView(item: item, exposureNumber: exposureNumber, isPreFrame: isPreFrame, frameNumberTapCount: frameNumberTapCount, onCycleExtraExposures: frameNumberTapCount > 0 ? onCycleExtraExposures : nil)
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
    let isActiveRoll: Bool
    let menuContext: any ExposureMenuContext
    var onCameraSwitched: ((UUID) -> Void)?

    private var cameraID: UUID? { menuContext.currentCameraID }
    private var currentCameraIndicator: String { isActiveRoll ? "checkmark" : "circle.fill" }

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
                        Label(camera.name, systemImage: currentCameraIndicator)
                    } else {
                        Text(camera.name)
                    }
                    Text(Self.subtitle(for: camera))
                }
            }
        } label: {
            ToolbarTitle(primary: cameraName, secondary: filmStock)
                .padding(.vertical, 2)
                .frame(height: 44, alignment: .leading)
                .frame(minWidth: min(250, UIScreen.currentWidth - 32 - 44 - 44 - 12 - 12), maxWidth: UIScreen.currentWidth - 32 - 44 - 44 - 12 - 12, alignment: .leading)
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
    var onShowRollDetail: (() -> Void)?
    var canUndoDelete: Bool = false
    var onUndoDelete: (() -> Void)?
    var scrollTargetItemID: UUID?
    @State private var draggingPlaceholderID: UUID?
    @State private var dropTargetIndex: Int?
    
    var totalBottomPadding: CGFloat {
        // full height of capture sheet + bottom padding of capture sheet + finish roll button spacing + finish roll button height + desired overscroll amount
        isActiveRoll ? CaptureSheet.fullHeight + 8 + 20 + 48 + 48: pastRollOverscroll
    }
    
    var totalOverscroll: CGFloat {
        totalBottomPadding - (CaptureSheet.fullHeight - bottomInset)
    }

    @ViewBuilder
    private func exposureScrollContent() -> some View {
        VStack(spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(logItems.enumerated()), id: \.element.id) { index, item in
                    let isPreFrame = index < extraExposures
                    let frameNumber: Int? = isPreFrame ? nil : index - extraExposures + 1
                    let canCycle = index < 4 && AppSettings.shared.preFramesEnabled
                    ExposureRow(
                        item: item,
                        exposureNumber: frameNumber,
                        isPreFrame: isPreFrame,
                        frameNumberTapCount: canCycle ? (isActiveRoll ? 1 : 2) : 1,
                        menuContext: menuContext,
                        onCameraSwitched: onCameraSwitched,
                        onDelete: onDelete,
                        onCycleExtraExposures: canCycle ? onCycleExtraExposures : nil
                    )
                    .equatable()
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.12)),
                        removal: index == logItems.count - 1 ? .opacity : .identity
                    ))
                    .contentShape(Rectangle())
                    .id(item.id)
                    .if(item.exposureType.isReorderable) { view in
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
            }.frame(height: exposureItemHeight * CGFloat(logItems.count))
            .padding(.top, 118)
            .padding(.leading, 16 - 12)
            .padding(.trailing, 16)
            
            // Overscroll / drop zone for moving placeholders to end of list
            Color.clear
                .frame(height: max(totalOverscroll, 0))
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
                .padding(.horizontal, 16)
            // we have two "overscroll"s so that we maintain consistent padding regardless of whether the Capture controls are collapsed or expanded
            Color.clear // Color.red to test proper scroll init
                .frame(height: totalBottomPadding - max(totalOverscroll, 0))
        }
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
                            .frame(minHeight: UIScreen.currentHeight, alignment: .top)
                    }
                    .animation(.snappy(duration: 0.25, extraBounce: 0), value: logItems.map(\.id))
                    .defaultScrollAnchor(.init(x: 0.5, y: {
                        guard isActiveRoll else {
                            return 1.0 // just scroll to the bottom for inactive rolls
                        }
                        
                        // for a full capture sheet, we don't need this entire dance
                        // to scroll to the right overscroll spot. use fp-aware comparison.
                        guard abs(CaptureSheet.fullHeight - bottomInset) > 0.001 else {
                            return 1.0
                        }
                        /*
                         reference: iPhone 15 Pro screen height, 852 pt
                         
                         **fucking SwiftUI**, there's some weird behavior here. testing:
                         
                         testing with 130 items, collapsed Capture sheet:
                         0.999 -> offset 10494
                         0.9999 -> offset 10504.00000
                         0.99995 -> offset 10504.33333
                         0.99996 -> offset 9808 ???
                         0.999955 -> offset 9808
                         0.999952 -> offset 10504.33333
                         
                         okay, so it seems like exceeding 10504.33 overshoots some internal value and overflows the scrollview
                         10504.33 in pixels is 10504.33 * 3 = 31513 pixels.
                         
                         our reported scrollview maxOffset is 9808. calculating by hand:
                         
                         118 (top padding) + 78 * 130 (content) = 10258
                         10258 + 278 (full capture sheet height on 15 Pro) + 8 + 20 + 48 + 48 (reference formula above) = 10258 + 402 = 10660
                         10660 - 852 (screen height) = 9808. okay. that makes sense.
                         
                         but what's with 10504.33? that's
                         
                         10660 - 10504.33 = 155.67. it seems to be in pixels.
                         
                         so 467 pixels. might be safe area?
                         
                         ---
                         
                         let's try with different items. trying with 50.
                         
                         height: reported max offset = 3568, 3568 + 852 = 4420
                         
                         hypothesis: if it's safe area, then we should see 4420 - 155.67 = 4,264.33
                         0.99 -> 4222.33333
                         0.999 -> 4260.66667
                         0.9999 -> 3568, overshot
                         0.9995 -> 4263
                         0.9997 -> 4263.66667
                         0.9998 -> 4263.66667
                         0.99985 -> 4263.66667
                         
                         interesting. we're within rounding error. the new value is 4420 - 4263.66667 = 156.33 .
                         
                         hypothesis: there's some internal rounding going on. we should probably use less items to get a more precise measurement.
                         
                         testing with 6 items:
                         maxOffset = 136. 136 + 852 = 988
                         based on previous: 988 - 156.33 = 831.67
                         
                         0.99 -> 824.66667
                         0.999 -> 832.33333
                         0.9995 -> 136, nope
                         0.9992 -> 832.33333
                         0.9993 -> 832.33333
                         0.9994 -> 136, nope
                         0.99935 -> 832.33333
                         
                         interesting. so we get a new value: 832.33333. it's 988 - 832.33 = 155.67. same as the first one.
                         
                         okay, the actual value seems to be something like 156 points.
                         
                         so iOS' logic appears to be:
                         
                         maximum = viewsize - 156
                         try to scroll to proportion * (viewsize - 156). if it rounds to the max, then clip to viewSize - deviceHeight (the actual bottom of the scroll view)
                         
                         somebody at Apple really fucked up. but it's okay. we reverse-engineered their buggy logic, we use it.
                         */
                        
                        // careful: don't target an area too far, or you'll get yeeted into oblivion
                        let MAGIC_SAFE_AREA: CGFloat = 156
                        
                        /*
                         so we want to scroll to totalTargetHeight - screen height.
                         
                         so x * (totalScrollViewHeight + MAGIC_SAFE_AREA) = totalTargetHeight - screen height
                         so (totalTargetHeight - screen height) / (totalScrollViewHeight + MAGIC_SAFE_AREA)
                         
                         yep. very normal.
                        */
                        
                        let totalContentHeight: CGFloat = 118 + exposureItemHeight * CGFloat(logItems.count)
                        let totalTargetHeight: CGFloat = totalContentHeight + totalOverscroll - UIScreen.currentHeight
                        let totalScrollViewHeight: CGFloat = totalContentHeight + totalBottomPadding
                        
//                        print("computed target", totalTargetHeight)
//                        print("computed content", totalContentHeight)
//                        print("computed scroll view", totalScrollViewHeight)
                        
                        let computedResult = (totalTargetHeight) / (totalScrollViewHeight - MAGIC_SAFE_AREA)
                        
//                        print(computedResult)
                        return computedResult
                    }()), for: .initialOffset)
                    .defaultScrollAnchor(.bottom, for: .sizeChanges)
                    .defaultScrollAnchor(.bottom, for: .alignment)
                    .onAppear {
                        onScrollToBottomRegistered?({
                            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                                proxy.scrollTo("scrollAnchor", anchor: .bottom)
                            }
                        })
                    }
                    .onChange(of: logItems.count) { oldCount, newCount in
                        if newCount > oldCount {
                            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                                if let target = scrollTargetItemID {
                                    proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.35))
                                } else {
                                    proxy.scrollTo("scrollAnchor", anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        let maxOffset = geo.contentSize.height - geo.containerSize.height + geo.contentInsets.bottom
                        let currentOffset = geo.contentOffset.y + geo.contentInsets.top
//                        print("[scroll] maxOffset=\(String(format: "%.5f", maxOffset)) currentOffset=\(String(format: "%.5f", currentOffset)) threshold=\(nearBottomThreshold) nearBottom=\(currentOffset >= maxOffset - nearBottomThreshold)")
                        return currentOffset >= maxOffset - nearBottomThreshold
                    } action: { _, isNearBottom in
                        onNearBottomChanged?(isNearBottom)
                    }
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .appToolbar {
            if let menuContext {
                CameraSwitcherMenu(
                    cameraName: cameraName,
                    filmStock: filmStock,
                    isActiveRoll: isActiveRoll,
                    menuContext: menuContext,
                    onCameraSwitched: onCameraSwitched
                )
            }
        } trailing: {
            rollOptionsMenu
        }
        .id(scrollContextID)
    }

    private var rollOptionsMenu: some View {
        Menu {
            if canUndoDelete {
                Button {
                    onUndoDelete?()
                } label: {
                    Label("Undo delete", systemImage: "arrow.uturn.backward")
                }
                Divider()
            }
            Button {
                onShowRollDetail?()
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
            // Lost frames record "now" as their real timestamp — so they only make sense on the active roll.
            if isActiveRoll {
                Button {
                    playHaptic(.addPlaceholder)
                    onAddLostFrame?()
                } label: {
                    Label("Add lost frame", systemImage: "xmark.square")
                }
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
    .preferredColorScheme(.dark)
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
    .preferredColorScheme(.dark)
    .modelContainer(for: [Camera.self, Roll.self, LogItem.self], inMemory: true)
}
