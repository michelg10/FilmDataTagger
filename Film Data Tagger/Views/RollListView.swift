//
//  RollListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/21/26.
//

import SwiftUI
import SwiftData

private struct BlockProgressBar: View {
    let exposureCount: Int
    let totalCapacity: Int
    let maxCapacity: Int

    // Max gap between blocks for capacities 1–24, linearly interpolated from anchors:
    // 1–8 → 11.0, 12 → 8.0, 15 → 7.0, 24 → 5.0. Beyond 24, no cap.
    private static let maxGapTable: [CGFloat] = {
        let anchors: [(Int, CGFloat)] = [(8, 11.0), (12, 8.0), (15, 7.0), (24, 5.0)]
        var table = [CGFloat](repeating: 0, count: 25) // index 0 unused
        for i in 1...24 {
            if i <= anchors[0].0 {
                table[i] = anchors[0].1
            } else {
                for a in 0..<anchors.count - 1 {
                    let (loN, loV) = anchors[a]
                    let (hiN, hiV) = anchors[a + 1]
                    if i <= hiN {
                        let t = CGFloat(i - loN) / CGFloat(hiN - loN)
                        table[i] = loV + t * (hiV - loV)
                        break
                    }
                }
            }
        }
        return table
    }()

    var body: some View {
        Canvas { context, size in
            let n = min(maxCapacity, 200)
            guard n > 0 else { return }
            let elemRatio: CGFloat = 6.6
            let sepRatio: CGFloat = 3.53
            let unit = size.width / (CGFloat(n) * elemRatio + CGFloat(n - 1) * sepRatio)
            let gapCap = n < Self.maxGapTable.count ? Self.maxGapTable[n] : CGFloat.infinity
            let uncappedSep = unit * sepRatio
            let sepW: CGFloat
            let elemW: CGFloat
            if uncappedSep > gapCap {
                sepW = gapCap
                elemW = (size.width - CGFloat(n - 1) * gapCap) / CGFloat(n)
            } else {
                sepW = uncappedSep
                elemW = unit * elemRatio
            }
            let stride = elemW + sepW
            let notchH: CGFloat = 2
            let gap: CGFloat = 2
            let mainY = notchH + gap
            let mainH = max(size.height - 2 * (notchH + gap), 0)

            for i in 0..<min(totalCapacity, n) {
                let x = CGFloat(i) * stride
                let filled = i < exposureCount
                let alpha = (filled ? 1.0 : 0.15) * 0.95
                let notchAlpha = alpha * 0.25

                context.fill(Path(CGRect(x: x, y: 0, width: elemW, height: notchH)),
                             with: .color(.white.opacity(notchAlpha)))
                context.fill(Path(CGRect(x: x, y: mainY, width: elemW, height: mainH)),
                             with: .color(.white.opacity(alpha)))
                context.fill(Path(CGRect(x: x, y: size.height - notchH, width: elemW, height: notchH)),
                             with: .color(.white.opacity(notchAlpha)))
            }
        }
        .frame(height: 18)
    }
}

struct RollListRow: View {
    let roll: RollSnapshot
    var maxCapacity: Int = 36

    private var exposureCount: Int {
        roll.exposureCount
    }

    private var exposureCountDisplay: String {
        exposureCount > 999 ? "999+" : "\(exposureCount)"
    }

    private static let loadedDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private var lastUsedText: String {
        relativeTimeString(from: roll.lastExposureDate ?? roll.createdAt, suffix: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(roll.filmStock)
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .lineHeightCompat(points: 30, fallbackSpacing: 6.13)
                    .foregroundStyle(Color.white)
                Spacer(minLength: 15)
                let exposureCountText = Text(exposureCountDisplay).foregroundStyle(Color.white.opacity(0.9))
                let totalExposureText = Text(" / \(roll.totalCapacity)").foregroundStyle(Color.white.opacity(0.5))
                Text("\(exposureCountText)\(totalExposureText)")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
            }
            // Compensate for .lineHeightCompat making the view taller than the visible text
            .padding(.bottom, -4)

            BlockProgressBar(
                exposureCount: exposureCount,
                totalCapacity: roll.totalCapacity,
                maxCapacity: maxCapacity
            )
            
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                let loadedText = Text("Loaded").foregroundStyle(Color.white.opacity(0.5))
                let dateLoadedText = Text(Self.loadedDateFormatter.string(from: roll.createdAt)).foregroundStyle(Color.white.opacity(0.9))
                Text("\(loadedText) \(dateLoadedText)")
                
                Spacer(minLength: 0)
                
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    let usedAgoTime = Text(lastUsedText).foregroundStyle(Color.white.opacity(0.9))
                    Text("used \(usedAgoTime)")
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }.font(.system(size: 15, weight: .medium, design: .default))
            .fontWidth(.expanded)
            
            if let notes = roll.notes, !notes.isEmpty {
                (Text(Image(systemName: "text.pad.header")).foregroundStyle(Color.white.opacity(0.7)) + Text(" \(notes)").foregroundStyle(Color.white.opacity(0.5)))
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(2)
                    .lineHeightCompat(points: 23, fallbackSpacing: 5.1)
            }
        }
    }
}

struct RollListView: View {
    let viewModel: any RollsViewModel
    var onRollSelected: ((RollSnapshot) -> Void)?
    var onShowRollDetail: ((UUID) -> Void)?

    private var rollData: OpenCameraRolls? { viewModel.openCameraRolls }
    private var cameraSnap: CameraSnapshot? { viewModel.openCameraSnapshot }
    private var activeRoll: RollSnapshot? { rollData?.activeRoll }
    private var pastRolls: [RollSnapshot] { rollData?.pastRolls ?? [] }
    private var maxCapacity: Int { rollData?.maxRollCapacity ?? 36 }
    private var totalExposures: Int { cameraSnap?.totalExposureCount ?? 0 }
    private var cameraName: String { cameraSnap?.name ?? "" }

    @State private var rollToDelete: RollSnapshot?
    @State private var rollToEdit: RollSnapshot?
    @Namespace private var rollTransition

    var body: some View {
        ZStack {
            if rollData?.hasRolls ?? false {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // IMPORTANT: top padding of first element should always be 12. padding is designed in this way so that user has maximum tappable area.
                        if let activeRoll {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Loaded roll")
                                    .font(.system(size: 17, weight: .semibold, design: .default))
                                    .fontWidth(.expanded)
                                    .opacity(0.6)

                                Button {
                                    viewModel.switchToRoll(id: activeRoll.id)
                                    onRollSelected?(activeRoll)
                                } label: {
                                    RollListRow(roll: activeRoll, maxCapacity: maxCapacity)
                                        .padding(.vertical, 24)
                                        .padding(.top, -4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .matchedGeometryEffect(id: activeRoll.id, in: rollTransition)
                                .id(activeRoll.id)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -130.0)), removal: .identity))
                                .contextMenu {
                                    Button {
                                        onShowRollDetail?(activeRoll.id)
                                    } label: {
                                        Label("Details", systemImage: "info.circle")
                                    }
                                    Button {
                                        rollToEdit = activeRoll
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        rollToDelete = activeRoll
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }.padding(.bottom, 17)
                            .transition(.opacity)
                        }

                        if !pastRolls.isEmpty {
                            Text("Past rolls")
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .fontWidth(.expanded)
                                .opacity(0.6)

                            ForEach(Array(pastRolls.enumerated()), id: \.element.id) { index, roll in
                                if index > 0 {
                                    Color.white.opacity(0.15)
                                        .frame(height: 1)
                                        .padding(.horizontal, 8)
                                }

                                let isLast = index == pastRolls.count - 1
                                Button {
                                    viewModel.switchToRoll(id: roll.id)
                                    onRollSelected?(roll)
                                } label: {
                                    RollListRow(roll: roll, maxCapacity: maxCapacity)
                                        .padding(.vertical, 24)
                                        .padding(.top, index == 0 ? -4 : 0)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .matchedGeometryEffect(id: roll.id, in: rollTransition)
                                .transition(.asymmetric(
                                    insertion: .identity,
                                    removal: isLast ? .opacity : .identity
                                ))
                                .contextMenu {
                                    Button {
                                        onShowRollDetail?(roll.id)
                                    } label: {
                                        Label("Details", systemImage: "info.circle")
                                    }
                                    Button {
                                        rollToEdit = roll
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        rollToDelete = roll
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        
                    }.animation(.snappy(duration: 0.4, extraBounce: 0), value: activeRoll?.id)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 217 - 20 - bottomSafeAreaInset - 46) // overscroll
                }.animation(.snappy(duration: 0.4, extraBounce: 0), value: pastRolls.map(\.id))
            } else {
                VStack(spacing: 13) {
                    Image("no-film-icon")
                        .frame(width: 61, height: 52)
                        .opacity(0.5)
                    Text("no rolls")
                        .font(.system(size: 25, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white.opacity(0.5))
                }.padding(.bottom, 54)
            }
        }
        .animation(.easeOut(duration: 0.25), value: rollData?.hasRolls)
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
        .alert(
            "Delete \"\(rollToDelete?.filmStock ?? "")\"?",
            isPresented: Binding(
                get: { rollToDelete != nil },
                set: { if !$0 { rollToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let roll = rollToDelete {
                    viewModel.deleteRoll(id: roll.id)
                    rollToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                rollToDelete = nil
            }
        } message: {
            let count = rollToDelete?.exposureCount ?? 0
            Text("This will permanently delete \"\(rollToDelete?.filmStock ?? "")\" and its \(count.formatted()) logged exposure\(count == 1 ? "" : "s") from all your devices. Data saved to Photos or exported files won't be affected.")
        }
        .sheet(item: $rollToEdit) { roll in
            RollFormSheet(
                cameraID: cameraSnap?.id ?? UUID(),
                editingRoll: roll,
                onCreateRoll: { viewModel.createRoll(cameraID: $0, filmStock: $1, capacity: $2) },
                onEditRoll: { viewModel.editRoll(id: $0, filmStock: $1, capacity: $2) }
            )
        }
        .appToolbar {
            rollListTitle
        }
    }

    private var rollListTitle: some View {
        let exposureText = Text(" exposure\(totalExposures == 1 ? "" : "s") •").foregroundStyle(Color.white.opacity(0.5))
        let rollCount = cameraSnap?.rollCount ?? 0
        let rollText = Text(" roll\(rollCount == 1 ? "" : "s")").foregroundStyle(Color.white.opacity(0.5))
        return ToolbarTitle(primary: cameraName) {
            Text("\(totalExposures.formatted())\(exposureText) \(rollCount.formatted())\(rollText)")
                .foregroundStyle(Color.white)
        }
    }
}

#Preview {
    @Previewable @State var container = PreviewSampleData.makeContainer()

    let viewModel: FilmLogViewModel = {
        let vm = FilmLogViewModel(previewStore: PreviewSampleData.makeStore(container: container))
        let cameraID = UUID()

        let activeSnap = RollSnapshot(
            id: UUID(), cameraID: cameraID,
            filmStock: "Kodak Portra 400", capacity: 36, extraExposures: 0,
            isActive: true, createdAt: Date().addingTimeInterval(-3600),
            timeZoneIdentifier: TimeZone.current.identifier, cityName: "Los Angeles",
            notes: nil, lastExposureDate: Date().addingTimeInterval(-300),
            exposureCount: 14, totalCapacity: 36
        )
        let pastSnap1 = RollSnapshot(
            id: UUID(), cameraID: cameraID,
            filmStock: "Fuji Superia 400", capacity: 36, extraExposures: 2,
            isActive: false, createdAt: Date().addingTimeInterval(-86400 * 3),
            timeZoneIdentifier: "America/New_York", cityName: "New York",
            notes: nil, lastExposureDate: Date().addingTimeInterval(-86400 * 2),
            exposureCount: 38, totalCapacity: 38
        )
        let pastSnap2 = RollSnapshot(
            id: UUID(), cameraID: cameraID,
            filmStock: "Ilford HP5 Plus", capacity: 24, extraExposures: 0,
            isActive: false, createdAt: Date().addingTimeInterval(-86400 * 14),
            timeZoneIdentifier: "Asia/Tokyo", cityName: "Tokyo",
            notes: "Rainy day street shots", lastExposureDate: Date().addingTimeInterval(-86400 * 12),
            exposureCount: 24, totalCapacity: 24
        )

        let rolls = [activeSnap, pastSnap1, pastSnap2].map { RollState(snapshot: $0) }
        let cameraSnap = CameraSnapshot(
            id: cameraID, name: "Leica M6", createdAt: Date().addingTimeInterval(-86400 * 30),
            listOrder: 0, rollCount: rolls.count, totalExposureCount: 76
        )
        vm.previewSetCamera(CameraState(snapshot: cameraSnap, rolls: rolls))
        return vm
    }()

    NavigationStack {
        RollListView(viewModel: viewModel)
    }
    .modelContainer(container)
    .environment(viewModel)
    .preferredColorScheme(.dark)
}
