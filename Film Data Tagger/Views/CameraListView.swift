//
//  CameraListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/21/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CameraRollProgress: View {
    let exposureCount: Int?
    let totalExposureCount: Int?
    let size: CGFloat = 60

    var exposureProgress: Double? {
        guard let exposureCount = exposureCount, let totalExposureCount = totalExposureCount else {
            return nil
        }
        
        return max((Double(exposureCount) + 0.01) / (Double(totalExposureCount) + 0.01), 0.0)
    }
    
    
    var body: some View {
        ZStack {
            RingView(
                diameter: size - 6,
                strokeWidth: 6,
                progress: exposureProgress ?? 0,
                fillColor: Color.white.opacity(0.95),
                trackColor: Color.white.opacity(0.13),
                overflowShadowColor: .black.opacity(0.75),
                overflowShadowRadius: 2.9
            )
            if let exposureCount = exposureCount {
                Text(exposureCount > 99 ? "99+" : String(exposureCount))
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }.frame(width: size, height: size)
    }
}

struct CameraListRow: View {
    let entry: any CameraListEntry
    var body: some View {
        HStack(spacing: 0) {
            CameraRollProgress(
                exposureCount: entry.activeExposureCount,
                totalExposureCount: entry.activeCapacity
            ).padding(.trailing, 17)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name)
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .padding(.bottom, 7)
                    .lineLimit(1)
                if !entry.isInstantFilm {
                    Text(entry.filmStockLabel ?? "No roll loaded")
                        .font(.system(size: 17, weight: .medium, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white)
                        .opacity(0.6)
                        .lineLimit(1)
                }
                HStack(spacing: 16) {
                    if !entry.isInstantFilm {
                        HStack(spacing: 7) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 17, weight: .medium, design: .default))
                                .foregroundStyle(Color.white.opacity(0.4))
                            Text(entry.rollCount.formatted())
                                .font(.system(size: 17, weight: .medium, design: .default))
                                .fontWidth(.expanded)
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 17, weight: .medium, design: .default))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(entry.totalExposureCount.formatted())
                            .font(.system(size: 17, weight: .medium, design: .default))
                            .fontWidth(.expanded)
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 20)
            HStack(spacing: 9) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    if let lastUsed = entry.lastUsedCompact {
                        Text(lastUsed)
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .fontWidth(.expanded)
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }.frame(height: cameraRowHeight)
    }
}

private let cameraRowHeight: CGFloat = 124

private struct CameraDropIndicatorLine: View {
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

private struct CameraRowDropDelegate: DropDelegate {
    let index: Int
    let currentOrder: [UUID]
    @Binding var draggingID: UUID?
    @Binding var dropTargetIndex: Int?
    let commit: ([UUID]) -> Void

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
        defer { dropTargetIndex = nil; draggingID = nil }
        guard let draggingID,
              let dropTargetIndex,
              let fromIndex = currentOrder.firstIndex(of: draggingID) else {
            return false
        }

        var reordered = currentOrder
        reordered.remove(at: fromIndex)
        let insertAt = dropTargetIndex > fromIndex ? dropTargetIndex - 1 : dropTargetIndex
        reordered.insert(draggingID, at: min(insertAt, reordered.count))

        guard reordered != currentOrder else { return false }
        commit(reordered)
        return true
    }

    private func updateTarget(info: DropInfo) {
        guard let draggingID,
              let fromIndex = currentOrder.firstIndex(of: draggingID) else { return }
        let midY = cameraRowHeight / 2
        let deadZone: CGFloat = 12
        if info.location.y >= midY - deadZone && info.location.y <= midY + deadZone {
            dropTargetIndex = nil
        } else {
            let proposed = info.location.y < midY ? index : index + 1
            dropTargetIndex = (proposed == fromIndex || proposed == fromIndex + 1) ? nil : proposed
        }
    }
}

private struct CameraEndDropDelegate: DropDelegate {
    let endIndex: Int
    let currentOrder: [UUID]
    @Binding var draggingID: UUID?
    @Binding var dropTargetIndex: Int?
    let commit: ([UUID]) -> Void

    private var isAlreadyLast: Bool {
        guard let draggingID else { return false }
        return currentOrder.last == draggingID
    }

    func dropEntered(info: DropInfo) {
        guard draggingID != nil else { return }
        dropTargetIndex = isAlreadyLast ? nil : endIndex
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingID != nil else { return nil }
        dropTargetIndex = isAlreadyLast ? nil : endIndex
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetIndex == endIndex { dropTargetIndex = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropTargetIndex = nil; draggingID = nil }
        guard let draggingID,
              let fromIndex = currentOrder.firstIndex(of: draggingID) else {
            return false
        }

        var reordered = currentOrder
        reordered.remove(at: fromIndex)
        reordered.append(draggingID)

        guard reordered != currentOrder else { return false }
        commit(reordered)
        return true
    }
}

struct CameraListView: View {
    let viewModel: FilmLogViewModel
    @State private var editingEntry: (any CameraListEntry)?
    @State private var entryToDelete: (any CameraListEntry)?
    @State private var showDeleteAlert = false
    @State private var draggingEntryID: UUID?
    @State private var dropTargetIndex: Int?

    private var cameras: [CameraSnapshot] { viewModel.cameraList }

    @State private var titleVisible = true

    private var titleOverlay: some View {
        Text("Sprokbook")
            .font(.system(size: 34, weight: .bold, design: .default))
            .fontWidth(.expanded)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .opacity(titleVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: titleVisible)
            .allowsHitTesting(false)
    }

    private var statusBarGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.6), location: 0.5),
                .init(color: .black.opacity(0), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: topSafeAreaInset)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cameraScrollContent(entries: [any CameraListEntry], orderedIDs: [UUID]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                NavigationLink(value: entry.id) {
                    CameraListRow(entry: entry)
                }
                .overlay(alignment: .top) {
                    CameraDropIndicatorLine(active: dropTargetIndex == index)
                        .offset(y: -0.5)
                }
                .contextMenu {
                    Button {
                        editingEntry = entry
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        entryToDelete = entry
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .onDrag {
                    draggingEntryID = entry.id
                    return NSItemProvider(object: entry.id.uuidString as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: CameraRowDropDelegate(
                        index: index,
                        currentOrder: orderedIDs,
                        draggingID: $draggingEntryID,
                        dropTargetIndex: $dropTargetIndex,
                        commit: { viewModel.reorderCameras($0) }
                    )
                )
                .transition(.asymmetric(insertion: .opacity, removal: index == entries.count - 1 ? .opacity : .identity))
                if index < entries.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                        .padding(.leading, 68)
                }
            }

            Color.clear
                .frame(height: 217 - 18 - bottomSafeAreaInset)
                .contentShape(Rectangle())
                .overlay(alignment: .top) {
                    CameraDropIndicatorLine(active: dropTargetIndex == entries.count)
                        .offset(y: -1)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: CameraEndDropDelegate(
                        endIndex: entries.count,
                        currentOrder: orderedIDs,
                        draggingID: $draggingEntryID,
                        dropTargetIndex: $dropTargetIndex,
                        commit: { viewModel.reorderCameras($0) }
                    )
                )
        }.animation(.easeOut(duration: 0.25), value: entries.map(\.id))
        .padding(.horizontal, 16)
    }

    var body: some View {
        Group {
            let entries = cameras
            let orderedIDs = entries.map(\.id)
            let forceOnboarding = false // debug: set to true to preview onboarding text
            if !entries.isEmpty && !forceOnboarding {
                ScrollView {
                    cameraScrollContent(entries: entries, orderedIDs: orderedIDs)
                }
                .scrollClipDisabled()
                .padding(.top, 64)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top <= 0
                } action: { _, atTop in
                    titleVisible = atTop
                }
            } else {
                VStack(spacing: 11) {
                    Text("Welcome to Sprokbook")
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                    Text("Add a camera to get started")
                        .font(.system(size: 17, weight: .medium, design: .default))
                        .fontWidth(.expanded)
                        .multilineTextAlignment(.center)
                        .lineHeightCompat(points: 21, fallbackSpacing: 0.7)
                        .foregroundStyle(Color.white.opacity(0.5))
                }.padding(.horizontal, 16)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            let terminalColor = Color.black.opacity(bottomGradientOpacity)
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), terminalColor], startPoint: .top, endPoint: .bottom)
                    .frame(height: 60)
                terminalColor.frame(height: bottomSafeAreaInset - 6 + 0.25 * 60)
            }
            .frame(height: bottomSafeAreaInset - 6 + 1.25 * 60)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .offset(y: bottomSafeAreaInset)
        }
        .overlay(alignment: .top) { titleOverlay }
        .overlay(alignment: .top) { statusBarGradient }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { editingEntry != nil },
            set: { if !$0 { editingEntry = nil } }
        )) {
            if let editingEntry {
                NewCameraSheet(
                    editingEntry: editingEntry,
                    onRenameCamera: { viewModel.renameCamera(id: $0, name: $1) }
                )
            }
        }
        .alert(
            "Delete \"\(entryToDelete?.name ?? "")\"?",
            isPresented: $showDeleteAlert
        ) {
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete {
                    withAnimation {
                        viewModel.deleteCamera(id: entry.id)
                    }
                    entryToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            if let entry = entryToDelete {
                let rolls = entry.rollCount
                let exposures = entry.totalExposureCount
                if rolls == 0 && exposures == 0 {
                    Text("This will permanently delete \"\(entry.name)\" from all your devices. Data saved to Photos or exported files won't be affected.")
                } else if exposures == 0 {
                    Text("This will permanently delete \"\(entry.name)\" and its \(rolls.formatted()) roll\(rolls == 1 ? "" : "s") from all your devices. Data saved to Photos or exported files won't be affected.")
                } else {
                    Text("This will permanently delete \"\(entry.name)\", its \(rolls.formatted()) roll\(rolls == 1 ? "" : "s"), and all \(exposures.formatted()) exposure\(exposures == 1 ? "" : "s") from all your devices. Data saved to Photos or exported files won't be affected.")
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var container = PreviewSampleData.makeContainer()

    let viewModel: FilmLogViewModel = {
        let camera2 = Camera(name: "Olympus XA")
        container.mainContext.insert(camera2)
        let roll2 = Roll(filmStock: "Fuji Superia 400", camera: camera2)
        container.mainContext.insert(roll2)

        let vm = FilmLogViewModel(store: PreviewSampleData.makeStore(container: container))
        vm.setup()
        return vm
    }()

    NavigationStack {
        CameraListView(viewModel: viewModel)
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
