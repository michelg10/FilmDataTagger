//
//  RollListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/21/26.
//

import SwiftUI

struct RollListRow: View {
    var roll: Roll

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(roll.filmStock)
                .font(.system(size: 20, weight: .semibold, design: .default))
                .fontWidth(.expanded)
            Text(roll.rollSummary)
                .font(.system(size: 13, weight: .medium, design: .default))
                .fontWidth(.expanded)
                .opacity(0.58)
                .multilineTextAlignment(.leading)
                .lineHeight(.exact(points: 17))
        }.frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.white)
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
                            Text("Active roll")
                                .font(.system(size: 15, weight: .bold, design: .default))
                                .fontWidth(.expanded)
                                .opacity(0.6)

                            Button {
                                viewModel.switchToRoll(activeRoll)
                                onDismissSheet?()
                            } label: {
                                RollListRow(roll: activeRoll)
                                    .padding(.top, 12)
                                    .padding(.bottom, 14)
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
                        }

                        if !pastRolls.isEmpty {
                            Text("Past rolls")
                                .font(.system(size: 15, weight: .bold, design: .default))
                                .fontWidth(.expanded)
                                .opacity(0.6)
                                .padding(.top, 14)

                            ForEach(pastRolls, id: \.id) { roll in
                                Button {
                                    viewModel.switchToRoll(roll)
                                    onDismissSheet?()
                                } label: {
                                    RollListRow(roll: roll)
                                        .padding(.top, pastRolls.first?.id == roll.id ? 12 : 14)
                                        .padding(.bottom, 14)
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
                        
                    }.animation(.easeOut(duration: 0.25), value: pastRolls.map(\.id))
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
