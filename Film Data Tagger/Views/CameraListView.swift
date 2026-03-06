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
    var isSelected: Bool
    var isInstantFilm: Bool
    var exposureCount: Int?
    var totalExposureCount: Int?
    
    var exposureProgress: Double? {
        guard let exposureCount = exposureCount, let totalExposureCount = totalExposureCount else {
            return nil
        }
        
        return max((Double(exposureCount) + 0.01) / (Double(totalExposureCount) + 0.01), 0.0)
    }
    
    
    var body: some View {
        ZStack {
            if isInstantFilm {
                Circle()
                    .stroke(Color.white.opacity(isSelected ? 0.85 : 0.15), lineWidth: 6)
                    .frame(width: 53, height: 53)
                
                Circle()
                    .stroke(Color.white.opacity(isSelected ? 0.5 : 0.1), lineWidth: 2)
                    .frame(width: 21, height: 21)
                
                Circle()
                    .stroke(Color.white.opacity(isSelected ? 0.5 : 0.1), lineWidth: 1.5)
                    .frame(width: 7, height: 7)
            } else {
                RingView(
                    diameter: 53,
                    strokeWidth: 6,
                    progress: exposureProgress ?? 0,
                    fillColor: Color.init(hex: isSelected ? 0xFFFFFF : 0x8A8A8A),
                    trackColor: Color.white.opacity(isSelected ? 0.13 : 0.08),
                    overflowShadowColor: .black.opacity(0.75),
                    overflowShadowRadius: 2.9
                )
                if let exposureCount = exposureCount {
                    Text(exposureCount > 99 ? "99+" : String(exposureCount))
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white.opacity(isSelected ? 1.0 : 0.5))
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }.frame(width: 59, height: 59)
    }
}

struct CameraListRow: View {
    var entry: any CameraListEntry
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            CameraRollProgress(
                isSelected: isSelected,
                isInstantFilm: entry.isInstantFilm,
                exposureCount: entry.activeRoll.map { ($0.logItems ?? []).count },
                totalExposureCount: entry.activeRoll?.totalCapacity
            ).padding(.trailing, 17)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.displayName)
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .padding(.bottom, 6)
                    .lineLimit(1)
                if !entry.isInstantFilm {
                    Text(entry.filmStockLabel ?? "No roll loaded")
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white)
                        .opacity(0.6)
                        .lineLimit(1)
                }
                HStack(spacing: 16) {
                    if !entry.isInstantFilm {
                        HStack(spacing: 7) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundStyle(Color.white.opacity(0.4))
                            Text(entry.rollCount.formatted())
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .fontWidth(.expanded)
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(entry.totalExposureCount.formatted())
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .fontWidth(.expanded)
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }.frame(height: 18)
                .padding(.top, 8)
            }
            Spacer(minLength: 20)
            HStack(spacing: 9) {
                if let lastUsed = entry.lastUsedCompact {
                    Text(lastUsed)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .fontWidth(.expanded)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold, design: .default))
            }.foregroundStyle(Color.white.opacity(0.5))
        }.frame(height: 75)
    }
}

private let cameraRowHeight: CGFloat = 111

private struct CameraDropIndicatorLine: View {
    var active: Bool

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
    var viewModel: FilmLogViewModel
    @Query private var cameras: [Camera]
    @Query private var instantFilmGroups: [InstantFilmGroup]
    @State private var editingEntry: (any CameraListEntry)?
    @State private var showEditCamera = false
    @State private var entryToDelete: (any CameraListEntry)?
    @State private var showDeleteAlert = false
    @State private var draggingEntryID: UUID?
    @State private var dropTargetIndex: Int?

    private var allEntries: [any CameraListEntry] {
        let entries: [any CameraListEntry] = cameras + instantFilmGroups
        return entries.sorted { a, b in
            if a.listOrder != b.listOrder {
                return a.listOrder < b.listOrder
            }
            if a.createdAt != b.createdAt {
                return a.createdAt < b.createdAt
            }
            return a.id.uuidString < b.id.uuidString
        }
    }

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
                    CameraListRow(
                        entry: entry,
                        isSelected: entry.id == viewModel.openRoll?.camera?.id
                            || entry.id == viewModel.activeInstantFilmGroup?.id
                    )
                        .padding(.vertical, 18)
                }
                .overlay(alignment: .top) {
                    CameraDropIndicatorLine(active: dropTargetIndex == index)
                        .offset(y: -0.5)
                }
                .contextMenu {
                    Button {
                        editingEntry = entry
                        showEditCamera = true
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
                        commit: { viewModel.reorderCameraListEntries($0) }
                    )
                )
                .transition(.asymmetric(insertion: .opacity, removal: index == entries.count - 1 ? .opacity : .identity))
                if index < entries.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.13))
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
                        commit: { viewModel.reorderCameraListEntries($0) }
                    )
                )
        }.animation(.easeOut(duration: 0.25), value: entries.map(\.id))
        .padding(.horizontal, 16)
    }

    var body: some View {
        Group {
            let entries = allEntries
            let orderedIDs = entries.map(\.id)
            if !entries.isEmpty {
                ScrollView {
                    cameraScrollContent(entries: entries, orderedIDs: orderedIDs)
                }
                .scrollClipDisabled()
                .padding(.top, 68)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top <= 0
                } action: { _, atTop in
                    titleVisible = atTop
                }
            } else {
                // TODO: replace this for onboarding
                Text("no cameras\nadded")
                    .multilineTextAlignment(.center)
                    .lineHeight(.exact(points: 32))
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .opacity(0.4)
                    .padding(.bottom, 117)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { titleOverlay }
        .overlay(alignment: .top) { statusBarGradient }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEditCamera) {
            if let editingEntry {
                NewCameraSheet(viewModel: viewModel, editingEntry: editingEntry)
            }
        }
        .alert(
            "Delete \"\(entryToDelete?.displayName ?? "")\"?",
            isPresented: $showDeleteAlert
        ) {
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete {
                    withAnimation {
                        if let camera = entry as? Camera {
                            viewModel.deleteCamera(camera)
                        } else if let group = entry as? InstantFilmGroup {
                            viewModel.deleteInstantFilmGroup(group)
                        }
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
                    Text("This will permanently delete \"\(entry.displayName)\" from all your devices. Data saved to Photos or exported files won't be affected.")
                } else if exposures == 0 {
                    Text("This will permanently delete \"\(entry.displayName)\" and its \(rolls.formatted()) roll\(rolls == 1 ? "" : "s") from all your devices. Data saved to Photos or exported files won't be affected.")
                } else {
                    Text("This will permanently delete \"\(entry.displayName)\", its \(rolls.formatted()) roll\(rolls == 1 ? "" : "s"), and all \(exposures.formatted()) exposure\(exposures == 1 ? "" : "s") from all your devices. Data saved to Photos or exported files won't be affected.")
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var container = PreviewSampleData.makeContainer()

    let viewModel: FilmLogViewModel = {
        let vm = FilmLogViewModel(modelContext: container.mainContext)

        let camera2 = Camera(name: "Olympus XA")
        container.mainContext.insert(camera2)
        let roll2 = Roll(filmStock: "Fuji Superia 400", camera: camera2)
        container.mainContext.insert(roll2)
        camera2.rolls = [roll2]

        return vm
    }()

    NavigationStack {
        CameraListView(viewModel: viewModel)
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
