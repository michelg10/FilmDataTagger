//
//  ContentView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData
import CoreLocation
import UIKit

extension Notification.Name {
    static let backGestureBegan = Notification.Name("backGestureBegan")
    static let backGestureCancelled = Notification.Name("backGestureCancelled")
}

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactivePopGestureRecognizer?.addTarget(self, action: #selector(handlePopGesture(_:)))
    }

    @objc func handlePopGesture(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            NotificationCenter.default.post(name: .backGestureBegan, object: nil)
            let vcCount = viewControllers.count
            var coordinatorGoneLastTick = false
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                // Pop succeeded — VC was removed
                if self.viewControllers.count < vcCount {
                    timer.invalidate()
                    return
                }
                // Wait an extra tick after coordinator clears before deciding
                if self.transitionCoordinator == nil {
                    if coordinatorGoneLastTick {
                        timer.invalidate()
                        NotificationCenter.default.post(name: .backGestureCancelled, object: nil)
                    } else {
                        coordinatorGoneLastTick = true
                    }
                }
            }
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}

struct FinishRollButton: View {
    var action: () -> Void

    var body: some View {
        Button {
            playHaptic(.finishRoll)
            action()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .padding(.bottom, 2)
                    .frame(width: 18, height: 18, alignment: .center)
                    .padding(.leading, 15)
                Text("Finish roll")
                    .padding(.trailing, 19)
                    .font(.system(size: 17, weight: .semibold, design: .default))
            }.foregroundStyle(Color.white)
            .fontWidth(.expanded)
        }.frame(height: 44)
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
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
                Text(entry.configSubtitle)
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
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
            }.glassEffect(.regular.interactive(), in: Circle())

            Spacer()

            Button {
                trailingIconTapped()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
            }.glassEffect(.regular.interactive(), in: Circle())
        }.padding(.horizontal, 16)
        .offset(y: 16)
    }
}

enum TopBarState {
    case camera
    case roll
}

struct RollListView: View {
    var body: some View {
        ScrollView {

        }
        .navigationBarBackButtonHidden()
    }
}

struct CameraListView: View {
    var entries: [any CameraListEntry]
    @Environment(\.dismiss) private var dismiss
    @Namespace var namespace
    @State private var topBarState: TopBarState = .camera
    @State private var path = NavigationPath()
    // there's a weird iOS glitch when the `ToolbarItem` hack that we use to add a blur to the top portion of the scroll view is used where the scroll view does a little jump when you pop back. we artificially add a padding (without an animation) right as this jump occurs to counteract this glitch.
    @State private var scrollTopPadding: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(entries, id: \.id) { entry in
                            NavigationLink(value: entry.id) {
                                CameraListRow(entry: entry)
                                    .padding(.vertical, 15)
                            }
                        }
                    }.padding(.top, 13)
                }
            }
            .padding(.top, scrollTopPadding)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // there's supposed to be a title text here, but the aforementioned iOS glitch was causing it to jump around, so we moved it to an overlay that's more stable.
                    Rectangle()
                        .foregroundStyle(Color.white.opacity(0.00001))
                        .frame(height: 40)
                        .frame(width: UIScreen.main.bounds.width - 32)
                        .padding(.bottom, 30 - 15)
                        .padding(.top, 139)
                        .overlay(alignment: .topLeading) {
                            Text("Cameras")
                                .font(.system(size: 34, weight: .bold, design: .default))
                                .fontWidth(.expanded)
                                .frame(height: 40)
                                .offset(y: 139)
                                .padding(.top, scrollTopPadding)
                        }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .backGestureBegan)) { _ in
                scrollTopPadding = 16
            }
            .onReceive(NotificationCenter.default.publisher(for: .backGestureCancelled)) { _ in
                scrollTopPadding = 0
            }
            .onDisappear {
                scrollTopPadding = 16
            }
            .navigationDestination(for: UUID.self) { _ in
                RollListView()
                    .onDisappear { scrollTopPadding = 0 }
            }
        }
        .onChange(of: path.count) {
            withAnimation(.easeInOut(duration: 0.1)) {
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
                        scrollTopPadding = 16
                        path = NavigationPath()
                    }
                }, trailingIconTapped: {
                    dismiss()
                }
            )
        }
        .overlay(alignment: .bottom) {
            if topBarState == .camera {
                Button {
                    // TODO
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 26, weight: .semibold, design: .default))
                            .frame(width: 32, height: 31)
                            .padding(.leading, 16)
                        Text("New camera")
                            .font(.system(size: 19, weight: .semibold, design: .default))
                            .fontWidth(.expanded)
                            .padding(.trailing, 25)
                    }.foregroundStyle(Color.white)
                    .frame(height: 61)
                }.glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID("principal", in: namespace)
                .id("CameraListView.principal")
                .transition(.opacity)
                .buttonStyle(.plain)
                .offset(y: -1)
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: FilmLogViewModel?
    @State private var showSheet = false
    @State private var isScrolling = false

    private var logItems: [LogItem] {
        viewModel?.logItems ?? []
    }

    var body: some View {
        Group {
            ZStack(alignment: .bottom) {
                ExposureListView(
                    logItems: logItems,
                    cameraName: viewModel?.activeRoll?.camera?.name ?? "",
                    filmStock: viewModel?.activeRoll?.filmStock ?? "",
                    isScrolling: $isScrolling,
                    onDelete: { item in
                        viewModel?.deleteItem(item)
                    },
                    onMovePlaceholderBefore: { item, target in
                        viewModel?.movePlaceholder(item, before: target)
                    },
                    onMovePlaceholderAfter: { item, target in
                        viewModel?.movePlaceholder(item, after: target)
                    },
                    onMovePlaceholderToEnd: { item in
                        viewModel?.movePlaceholderToEnd(item)
                    }
                )
            }.ignoresSafeArea(.all)
            .background(Color.black)
            .onAppear {
                if viewModel == nil {
                    viewModel = FilmLogViewModel(modelContext: modelContext)
                    viewModel?.setup()
                }
            }
            .sheet(isPresented: $showSheet) {
                if let viewModel {
                    CaptureSheet(
                        viewModel: viewModel,
                        isScrolling: isScrolling,
                        frameCount: logItems.count,
                        rollCapacity: viewModel.rollCapacity,
                        lastCaptureDate: logItems.last(where: { $0.hasRealCreatedAt })?.createdAt
                    )
                    .sheet(isPresented: .constant(true)) {
                        CameraListView(entries: viewModel.allCameraListEntries())
                    }
                }
            }
            .sheetFloatingView(offset: 20 - 30) {
                FinishRollButton(action: {
                    viewModel?.finishRoll()
                })
            }
            .onAppear {
                // hack to disable sheet animation
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showSheet = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSampleData.makeContainer())
}
