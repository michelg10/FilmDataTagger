//
//  CameraListView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/21/26.
//

import SwiftUI

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

struct CameraListRow: View {
    var entry: any CameraListEntry

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.displayName)
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                Text(entry.listSubtitle)
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .opacity(0.5)
                    .lineHeight(.exact(points: 20))
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 50)
            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .bold, design: .default))
                .foregroundStyle(Color.white)
                .opacity(0.5)
        }
    }
}

struct CameraListView: View {
    var entries: [any CameraListEntry]
    var onSelectRoll: ((Roll) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Namespace var namespace
    @State private var topBarState: TopBarState = .camera
    @State private var path = NavigationPath()
    @State private var selectedCamera: Camera?

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
                if !entries.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(entries, id: \.id) { entry in
                                NavigationLink(value: entry.id) {
                                    CameraListRow(entry: entry)
                                        .padding(.vertical, 15)
                                }
                            }
                        }.padding(.top, 13)
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
                if let camera = entries.first(where: { $0.id == id }) as? Camera {
                    RollListView(camera: camera, onSelectRoll: { roll in
                        onSelectRoll?(roll)
                        dismiss()
                    })
                    .onAppear { selectedCamera = camera }
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
                // TODO
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
            }.glassEffect(.regular.interactive(), in: Capsule())
            .glassEffectID("principal", in: namespace)
            .buttonStyle(.plain)
            .offset(y: -1)
        }
    }
}
