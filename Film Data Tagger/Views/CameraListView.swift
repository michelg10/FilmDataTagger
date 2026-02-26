//
//  CameraListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/21/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum TopBarState {
    case camera
    case roll
}

struct SheetTopBar: View {
    var state: TopBarState
    var leadingIconTapped: () -> Void
    var trailingIconTapped: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                leadingIconTapped()
            } label: {
                Image(systemName: state == .camera ? "gearshape.fill" : "chevron.left")
                    .contentTransition(.symbolEffect(.replace, options: .speed(2.0)))
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 44, height: 44)
            }.glassEffect(.regular.interactive(), in: Circle())

            Spacer()

            Button {
                trailingIconTapped()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 44, height: 44)
            }.glassEffect(.regular.interactive(), in: Circle())
        }.padding(.horizontal, 16)
        .offset(y: 16)
    }
}

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
                    .stroke(Color.init(hex: isSelected ? 0xD4D4D4 : 0x323232), lineWidth: 6)
                    .frame(width: 53, height: 53)
                
                Circle()
                    .stroke(Color.init(hex: isSelected ? 0x757575 : 0x2A2A2A), lineWidth: 2)
                    .frame(width: 21, height: 21)
                
                Circle()
                    .stroke(Color.init(hex: isSelected ? 0x757575 : 0x2A2A2A), lineWidth: 1.5)
                    .frame(width: 7, height: 7)
            } else {
                RingView(
                    diameter: 53,
                    strokeWidth: 6,
                    progress: exposureProgress ?? 0,
                    fillColor: isSelected ? .init(hex: 0xFFFFFF) : .init(hex: 0x747474),
                    trackColor: isSelected ? .init(hex: 0x3E3E3E) : .init(hex: 0x2B2B2B),
                    overflowShadowColor: .black.opacity(0.75),
                    overflowShadowRadius: 2.9
                )
                if let exposureCount = exposureCount {
                    Text(exposureCount > 99 ? "99+" : String(exposureCount))
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white.opacity(isSelected ? 1.0 : 0.55))
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundStyle(Color.init(hex: 0x868686))
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
                if let filmStockLabel = entry.filmStockLabel {
                    Text(filmStockLabel)
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
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(entry.totalExposureCount.formatted())
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .fontWidth(.expanded)
                            .foregroundStyle(Color.white.opacity(0.8))
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

private struct CameraListReorderDropDelegate: DropDelegate {
    let targetID: UUID?
    let currentOrder: [UUID]
    @Binding var draggingID: UUID?
    let commit: ([UUID]) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggingID = nil }
        guard let draggingID,
              let fromIndex = currentOrder.firstIndex(of: draggingID) else {
            return false
        }

        var reordered = currentOrder
        reordered.remove(at: fromIndex)

        if let targetID {
            guard let targetIndexInCurrent = currentOrder.firstIndex(of: targetID),
                  let targetIndexAfterRemoval = reordered.firstIndex(of: targetID) else {
                return false
            }
            let insertionIndex = fromIndex < targetIndexInCurrent
                ? targetIndexAfterRemoval + 1
                : targetIndexAfterRemoval
            reordered.insert(draggingID, at: insertionIndex)
        } else {
            reordered.append(draggingID)
        }

        guard reordered != currentOrder else { return false }
        commit(reordered)
        return true
    }
}

struct CameraListView: View {
    var viewModel: FilmLogViewModel
    @Environment(\.dismiss) private var dismiss
    @Query private var cameras: [Camera]
    @Query private var instantFilmGroups: [InstantFilmGroup]
    @State private var topBarState: TopBarState = .camera
    @State private var path = NavigationPath()
    @State private var selectedCamera: Camera?
    @State private var showNewRoll = false
    @State private var showNewCamera = false
    @State private var pendingCameraNavigation: UUID?
    @State private var editingEntry: (any CameraListEntry)?
    @State private var showEditCamera = false
    @State private var entryToDelete: (any CameraListEntry)?
    @State private var showDeleteAlert = false
    @State private var draggingEntryID: UUID?

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

    private var bottomButtonIcon: String {
        if topBarState == .camera {
            return "plus"
        }
        let hasActiveRoll = selectedCamera?.rolls?.contains(where: { $0.isActive }) ?? false
        return hasActiveRoll ? "checkmark.arrow.trianglehead.counterclockwise" : "plus"
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                let entries = allEntries
                let orderedIDs = entries.map(\.id)
                if !entries.isEmpty {
                    ScrollView {
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
                                    delegate: CameraListReorderDropDelegate(
                                        targetID: entry.id,
                                        currentOrder: orderedIDs,
                                        draggingID: $draggingEntryID,
                                        commit: { viewModel.reorderCameraListEntries($0) }
                                    )
                                )
                                .transition(.asymmetric(insertion: .opacity, removal: index == entries.count - 1 ? .opacity : .identity))
                                if index < entries.count - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.07))
                                        .frame(height: 1)
                                        .padding(.leading, 68)
                                }
                            }

                            Color.clear // overscroll and drop zone
                                .frame(height: 217 - 18 - bottomSafeAreaInset)
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [UTType.plainText],
                                    delegate: CameraListReorderDropDelegate(
                                        targetID: nil,
                                        currentOrder: orderedIDs,
                                        draggingID: $draggingEntryID,
                                        commit: { viewModel.reorderCameraListEntries($0) }
                                    )
                                )
                        }.animation(.easeOut(duration: 0.25), value: entries.map(\.id))
                        .padding(.top, 6)
                    }
                } else {
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
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x151515))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Cameras")
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .frame(width: UIScreen.main.bounds.width - 32, alignment: .leading)
                        .frame(height: 40)
                        .padding(.bottom, 30 - 15)
                        .padding(.top, 139)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let camera = cameras.first(where: { $0.id == id }) {
                    RollListView(
                        camera: camera,
                        viewModel: viewModel,
                        onDismissSheet: { dismiss() }
                    )
                    .onAppear { selectedCamera = camera }
                }
            }
        }
        .sheet(isPresented: $showNewRoll) {
            if let selectedCamera = selectedCamera {
                RollFormSheet(viewModel: viewModel, camera: selectedCamera, onRollCreated: {
                    dismiss()
                }, formIsAboveAnotherSheet: true)
            } else {
                Text("error: expected non-nil camera for RollFormSheet, got nil")
            }
        }
        .sheet(isPresented: $showNewCamera, onDismiss: {
            if let id = pendingCameraNavigation {
                pendingCameraNavigation = nil
                path.append(id)
            }
        }) {
            NewCameraSheet(viewModel: viewModel, onCameraCreated: { id in
                pendingCameraNavigation = id
            })
        }
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
        .onChange(of: path.count) {
            withAnimation(.easeInOut(duration: 0.2)) {
                topBarState = path.isEmpty ? .camera : .roll
            }
        }
        .overlay(alignment: .top) {
            SheetTopBar(
                state: topBarState,
                leadingIconTapped: {
                    switch topBarState {
                    case .camera:
                        // TODO
                        print("TODO: show settings pane")
                    case .roll:
                        path = NavigationPath()
                    }
                }, trailingIconTapped: {
                    dismiss()
                }
            )
        }
        .overlay(alignment: .bottom) {
            Button {
                if topBarState == .camera {
                    playHaptic(.newRollOrCamera)
                    showNewCamera = true
                } else if topBarState == .roll {
                    playHaptic(.newRollOrCamera)
                    showNewRoll = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: bottomButtonIcon)
                        .contentTransition(.opacity)
                        .font(.system(size: 26, weight: .semibold, design: .default))
                        .padding(.leading, 16)
                    Text(topBarState == .camera ? "New camera" : "New roll")
                        .font(.system(size: 19, weight: .semibold, design: .default))
                        .fontWidth(.expanded)
                        .padding(.trailing, 25)
                }.foregroundStyle(Color.white.opacity(0.95))
                .frame(height: 61)
                .contentShape(Rectangle())
            }
            .glassEffect(.regular.interactive(), in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 16.4)
            .buttonStyle(.plain)
            .offset(y: -1)
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

    Color.black.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            CameraListView(viewModel: viewModel)
        }
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
