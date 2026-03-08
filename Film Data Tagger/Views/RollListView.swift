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
    let isActive: Bool

    var body: some View {
        Canvas { context, size in
            let n = min(maxCapacity, 200)
            guard n > 0 else { return }
            let elemRatio: CGFloat = 6.6
            let sepRatio: CGFloat = 3.53
            let unit = size.width / (CGFloat(n) * elemRatio + CGFloat(n - 1) * sepRatio)
            let elemW = unit * elemRatio
            let stride = elemW + unit * sepRatio
            let notchH: CGFloat = 2
            let gap: CGFloat = 2
            let mainY = notchH + gap
            let mainH = max(size.height - 2 * (notchH + gap), 0)
            let baseAlpha: Double = isActive ? 1 : 0.75

            for i in 0..<min(totalCapacity, n) {
                let x = CGFloat(i) * stride
                let filled = i < exposureCount
                let alpha = (filled ? 1.0 : 0.15) * 0.95 * baseAlpha
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
    let roll: Roll
    var maxCapacity: Int = 36

    private var exposureCount: Int {
        (roll.logItems ?? []).count
    }

    private var exposureCountDisplay: String {
        exposureCount > 99 ? "99+" : "\(exposureCount)"
    }

    private static let loadedDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private var lastUsedText: String? {
        let lastDate = roll.lastExposureDate ?? roll.createdAt
        let interval = Date().timeIntervalSince(lastDate)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)
        if days > 0 {
            return "\(days)d"
        } else if hours > 0 {
            return "\(hours)h"
        } else if minutes >= 1 {
            return "\(minutes)m"
        } else {
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .bottom, spacing: 0) {
                Text(roll.filmStock)
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .lineHeight(.exact(points: 24))
                    .foregroundStyle(Color.white)
                Spacer(minLength: 20)
                let exposureCountText = Text(exposureCountDisplay).foregroundStyle(Color.white.opacity(0.9))
                let totalExposureText = Text(" / \(roll.totalCapacity)").foregroundStyle(Color.white.opacity(0.5))
                Text("\(exposureCountText)\(totalExposureText)")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .opacity(roll.isActive ? 1 : 0.9)
            }
            
            BlockProgressBar(
                exposureCount: exposureCount,
                totalCapacity: roll.totalCapacity,
                maxCapacity: maxCapacity,
                isActive: roll.isActive
            )
            
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                let loadedText = Text("Loaded").foregroundStyle(Color.white.opacity(0.5))
                let dateLoadedText = Text(Self.loadedDateFormatter.string(from: roll.createdAt)).foregroundStyle(Color.white.opacity(0.9))
                Text("\(loadedText) \(dateLoadedText)")
                
                Spacer(minLength: 20)
                
                let usedAgoTime = Text(lastUsedText ?? "now").foregroundStyle(Color.white.opacity(0.9))
                Text("used \(usedAgoTime)\(lastUsedText == nil ? "" : " ago")")
                    .foregroundStyle(Color.white.opacity(0.5))
            }.font(.system(size: 13, weight: .semibold, design: .default))
            .fontWidth(.expanded)
            .opacity(roll.isActive ? 1 : 0.8)
        }
    }
}

struct RollListView: View {
    let camera: Camera
    let viewModel: FilmLogViewModel
    var onRollSelected: ((Roll) -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var rolls: [Roll] {
        camera.rolls ?? []
    }

    private var activeRoll: Roll? {
        rolls.first { $0.isActive }
    }

    private var pastRolls: [Roll] {
        rolls.filter { !$0.isActive }.sorted {
            ($0.lastExposureDate ?? $0.createdAt) > ($1.lastExposureDate ?? $1.createdAt)
        }
    }

    @State private var rollToDelete: Roll?
    @State private var rollToEdit: Roll?

    private var totalExposures: Int {
        rolls.flatMap { $0.logItems ?? [] }.count
    }

    private var maxCapacity: Int {
        rolls.map(\.totalCapacity).max() ?? 36
    }

    var body: some View {
        ZStack {
            if !rolls.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // IMPORTANT: top padding of first element should always be 12. padding is designed in this way so that user has maximum tappable area.
                        if let activeRoll {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Active roll")
                                    .font(.system(size: 17, weight: .semibold, design: .default))
                                    .fontWidth(.expanded)
                                    .opacity(0.6)
                                    .padding(.bottom, 2)

                                Button {
                                    viewModel.switchToRoll(activeRoll)
                                    onRollSelected?(activeRoll)
                                } label: {
                                    RollListRow(roll: activeRoll, maxCapacity: maxCapacity)
                                        .padding(.vertical, 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
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
                            }.padding(.bottom, 20)
                            .transition(.opacity)
                        }

                        if !pastRolls.isEmpty {
                            Text("Past rolls")
                                .font(.system(size: 17, weight: .semibold, design: .default))
                                .fontWidth(.expanded)
                                .opacity(0.6)
                                .padding(.bottom, 2)

                            ForEach(Array(pastRolls.enumerated()), id: \.element.id) { index, roll in
                                if index > 0 {
                                    Color.white.opacity(0.13)
                                        .frame(height: 1)
                                        .padding(.horizontal, 8)
                                }
                                
                                let isLast = index == pastRolls.count - 1
                                Button {
                                    viewModel.switchToRoll(roll)
                                    onRollSelected?(roll)
                                } label: {
                                    RollListRow(roll: roll, maxCapacity: maxCapacity)
                                        .padding(.vertical, 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .transition(.asymmetric(insertion: .opacity, removal: isLast ? .opacity : .identity))
                                .contextMenu {
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
                        
                    }.animation(.easeOut(duration: 0.25), value: activeRoll?.id)
                    .animation(.easeOut(duration: 0.25), value: pastRolls.map(\.id))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 217 - 20 - bottomSafeAreaInset - 46) // overscroll
                }
            } else {
                // TODO: update this for onboarding
                Text("no rolls logged")
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .opacity(0.4)
                    .padding(.bottom, 135)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: rolls.isEmpty)
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
                    viewModel.deleteRoll(roll)
                    rollToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                rollToDelete = nil
            }
        } message: {
            let count = (rollToDelete?.logItems ?? []).count
            Text("This will permanently delete \"\(rollToDelete?.filmStock ?? "")\" and its \(count.formatted()) logged exposure\(count == 1 ? "" : "s") from all your devices. Data saved to Photos or exported files won't be affected.")
        }
        .navigationBarBackButtonHidden()
        .sheet(item: $rollToEdit) { roll in
            RollFormSheet(
                viewModel: viewModel,
                camera: camera,
                editingRoll: roll
            )
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .frame(width: 44, height: 44)
                    }.frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(camera.name)
                            .font(.system(size: 18, weight: .bold, design: .default))
                            .fontWidth(.expanded)
                            .foregroundStyle(Color.white)
                        let exposureTextAndSeparator = Text(" exposure\(totalExposures == 1 ? "" : "s") •").foregroundStyle(Color.white.opacity(0.6))
                        let rollTextAndSeparator = Text(" roll\(rolls.count == 1 ? "" : "s")").foregroundStyle(Color.white.opacity(0.6))
                        Text("\(totalExposures.formatted())\(exposureTextAndSeparator) \(rolls.count.formatted())\(rollTextAndSeparator)")
                            .foregroundStyle(Color.white)
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .fontWidth(.expanded)
                    }
                }.frame(width: UIScreen.currentWidth - 32, height: 44, alignment: .leading)
            }
        }
    }
}

#Preview {
    let container = PreviewSampleData.makeContainer()
    let context = container.mainContext
    let camera = try! context.fetch(FetchDescriptor<Camera>()).first!

    // Add a past roll
    let pastRoll = Roll(filmStock: "Fuji Superia 400", camera: camera)
    pastRoll.isActive = false
    context.insert(pastRoll)

    let viewModel = FilmLogViewModel(modelContext: context)
    return NavigationStack {
        RollListView(camera: camera, viewModel: viewModel)
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
