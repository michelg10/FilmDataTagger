//
//  CameraListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/21/26.
//

import SwiftUI
import SwiftData

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
        
        return max(min((Double(exposureCount) + 0.01) / (Double(totalExposureCount) + 0.01), 1.0), 0.0)
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
                    trackColor: isSelected ? .init(hex: 0x3E3E3E) : .init(hex: 0x2B2B2B)
                )
                if let exposureCount = exposureCount {
                    Text(String(min(exposureCount, 999)))
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
                totalExposureCount: entry.activeRoll?.capacity
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
                            Text("\(entry.rollCount)")
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .fontWidth(.expanded)
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text("\(entry.totalExposureCount)")
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

struct CameraListView: View {
    var viewModel: FilmLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var topBarState: TopBarState = .camera
    @State private var path = NavigationPath()
    @State private var selectedCamera: Camera?
    @State private var showNewRoll = false

    private var bottomButtonIcon: String {
        if topBarState == .camera {
            return "plus.circle.fill"
        }
        let hasRolls = !(selectedCamera?.rolls?.isEmpty ?? true)
        return hasRolls ? "checkmark.arrow.trianglehead.counterclockwise" : "plus"
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                let entries = viewModel.allCameraListEntries()
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
                                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                                if index < entries.count - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.07))
                                        .frame(height: 1)
                                        .padding(.leading, 68)
                                }
                            }
                        }.animation(.easeOut(duration: 0.25), value: entries.map(\.id))
                        .padding(.top, 6)
                        .padding(.bottom, 162) // overscroll
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
                let entries = viewModel.allCameraListEntries()
                if let camera = entries.first(where: { $0.id == id }) as? Camera {
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
            NewRollSheet(viewModel: viewModel, onRollCreated: {
                dismiss()
            })
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
                        break // TODO
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
                if topBarState == .roll {
                    playHaptic(.finishRoll)
                    showNewRoll = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: bottomButtonIcon)
                        .contentTransition(.opacity)
                        .font(.system(size: 26, weight: .semibold, design: .default))
                        .frame(width: 32, height: 31)
                        .padding(.leading, 16)
                    Text(topBarState == .camera ? "New camera" : "New roll")
//                        .contentTransition(.numericText())
                        .font(.system(size: 19, weight: .semibold, design: .default))
                        .fontWidth(.expanded)
                        .padding(.trailing, 25)
                }.foregroundStyle(Color.white.opacity(0.95))
                .frame(height: 61)
                .contentShape(Rectangle())
            }
            .glassEffect(.regular.interactive(), in: Capsule())
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
