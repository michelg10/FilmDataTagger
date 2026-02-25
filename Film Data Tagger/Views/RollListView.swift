//
//  RollListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/21/26.
//

import SwiftUI
import SwiftData

struct BlockProgressBar: Layout {
    let elementRatio: CGFloat = 6.6
    let separatorRatio: CGFloat = 3.53

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = (subviews.count + 1) / 2 // elements; separators are the odd-indexed views
        let totalUnits = CGFloat(n) * elementRatio + CGFloat(n - 1) * separatorRatio
        let unit = bounds.width / totalUnits

        var x = bounds.minX
        for (i, subview) in subviews.enumerated() {
            let w = (i % 2 == 0) ? unit * elementRatio : unit * separatorRatio
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: w, height: bounds.height)
            )
            x += w
        }
    }
}

struct RollListRow: View {
    var roll: Roll

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .bottom, spacing: 0) {
                Text("Kodak Portra 400")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .lineHeight(.exact(points: 24))
                    .foregroundStyle(Color.white)
                Spacer(minLength: 20)
                let exposureCountText = Text("24").foregroundStyle(Color.white.opacity(0.9)) // clip this at 99+ for numbers greater than 99
                let totalExposureText = Text(" / 36").foregroundStyle(Color.white.opacity(0.5))
                Text("\(exposureCountText)\(totalExposureText)")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .opacity(roll.isActive ? 1 : 0.9)
            }
            
            BlockProgressBar {
                let allRollsMaxExposureCount = 40
                let currentRollTotalExposures = 36
                let currentRollExposed = 25
                
                ForEach(0..<allRollsMaxExposureCount, id: \.self) { i in
                    VStack(spacing: 2) {
                        Rectangle().frame(height: 2).opacity(0.25)
                        Rectangle()
                        Rectangle().frame(height: 2).opacity(0.25)
                    }.foregroundStyle(Color.white.opacity(0.95))
                    .opacity(i < currentRollTotalExposures ? 1 : 0)

                    // separator (except after last element)
                    if i < allRollsMaxExposureCount - 1 {
                        Color.clear
                    }
                }
            }.opacity(roll.isActive ? 1 : 0.75)
            
            HStack(spacing: 0) {
                let loadedText = Text("Loaded").foregroundStyle(Color.white.opacity(0.5))
                let dateLoadedText = Text("Jan 20, 2026").foregroundStyle(Color.white.opacity(0.9))
                Text("\(loadedText) \(dateLoadedText)")
                
                Spacer(minLength: 20)
                
                let usedAgoTime = Text("30d").foregroundStyle(Color.white.opacity(0.9))
                Text("used \(usedAgoTime) ago")
                    .foregroundStyle(Color.white.opacity(0.5))
            }.font(.system(size: 13, weight: .semibold, design: .default))
            .fontWidth(.expanded)
            .opacity(roll.isActive ? 1 : 0.8)
        }
    }
}

struct RollListView: View {
    var camera: Camera
    var viewModel: FilmLogViewModel
    var onDismissSheet: (() -> Void)?

    private var rolls: [Roll] {
        camera.rolls ?? []
    }

    private var activeRoll: Roll? {
        rolls.first { $0.isActive }
    }

    private var pastRolls: [Roll] {
        rolls.filter { !$0.isActive }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    @State private var rollToDelete: Roll?

    private var totalExposures: Int {
        rolls.flatMap { $0.logItems ?? [] }.count
    }

    var body: some View {
        Group {
            if !rolls.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("\(totalExposures)")
                            Text(" exposure\(totalExposures == 1 ? "" : "s") •")
                                .opacity(0.6)
                            Text(" \(rolls.count)")
                            Text(" roll\(rolls.count == 1 ? "" : "s")")
                                .opacity(0.6)
                        }.foregroundStyle(Color.white)
                            .font(.system(size: 15, weight: .heavy, design: .default))
                            .fontWidth(.expanded)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 28)
                        
                        // IMPORTANT: top padding of first element should always be 12. padding is designed in this way so that user has maximum tappable area.
                        
                        if let activeRoll {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Active roll")
                                    .font(.system(size: 15, weight: .bold, design: .default))
                                    .fontWidth(.expanded)
                                    .opacity(0.6)

                                Button {
                                    viewModel.switchToRoll(activeRoll)
                                    onDismissSheet?()
                                } label: {
                                    RollListRow(roll: activeRoll)
                                        .padding(.vertical, 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        rollToDelete = activeRoll
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }.padding(.bottom, 20)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                        }

                        if !pastRolls.isEmpty {
                            Text("Past rolls")
                                .font(.system(size: 15, weight: .bold, design: .default))
                                .fontWidth(.expanded)
                                .opacity(0.6)

                            ForEach(Array(pastRolls.enumerated()), id: \.element.id) { index, roll in
                                if index > 0 {
                                    Color.white.opacity(0.18)
                                        .frame(height: 1)
                                        .padding(.horizontal, 8)
                                }
                                
                                Button {
                                    viewModel.switchToRoll(roll)
                                    onDismissSheet?()
                                } label: {
                                    RollListRow(roll: roll)
                                        .padding(.vertical, 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                                .contextMenu {
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
                        .padding(.bottom, 162) // overscroll
                        .offset(y: -46)
                }
            } else {
                Text("no rolls logged")
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .opacity(0.4)
                    .padding(.bottom, 141)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
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
            Text("This will permanently delete \"\(rollToDelete?.filmStock ?? "")\" and its \(count) logged exposure\(count == 1 ? "" : "s") from all your devices. Data already saved to Photos or exported files won't be affected.")
        }
        .navigationBarBackButtonHidden()
        .background(Color(hex: 0x151515))
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(camera.name)
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white)
                    Spacer(minLength: 0)
                }
                .frame(width: UIScreen.main.bounds.width - 32)
                .padding(.top, 0)
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
