//
//  ContentView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData
import CoreLocation

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

struct CameraConfigCameraItem: View {
    var cameraName: String
    var subtitle: String
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(cameraName)
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .opacity(0.5)
                    .lineHeight(.exact(points: 20))
            }
            Spacer(minLength: 50)
            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .bold, design: .default))
                .foregroundStyle(Color.white)
                .opacity(0.5)
        }
    }
}

struct CameraConfigView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    CameraConfigCameraItem(
                        cameraName: "Olympus XA",
                        subtitle: "Kodak Portra 400 • 7 rolls • 240 exposures • used 50m ago"
                    ).padding(.vertical, 15)
                    
                    CameraConfigCameraItem(
                        cameraName: "Polaroid",
                        subtitle: "2201 exposures • used 35m ago"
                    ).padding(.vertical, 15)
                    
                    CameraConfigCameraItem(
                        cameraName: "Nikon FM2n",
                        subtitle: "no roll loaded • 2 rolls • 71 exposures • used 3d ago"
                    ).padding(.vertical, 15)
                    
                    CameraConfigCameraItem(
                        cameraName: "Canon A-1",
                        subtitle: "Lomo Color Negative 400 • 1 roll • 0 exposures"
                    ).padding(.vertical, 15)
                    
                    CameraConfigCameraItem(
                        cameraName: "Mamiya C220",
                        subtitle: "no exposures"
                    ).padding(.vertical, 15)
                }.padding(.top, 13)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Cameras")
                                .font(.system(size: 34, weight: .bold, design: .default))
                                .fontWidth(.expanded)
                                .frame(height: 40)
                                .padding(.bottom, 30 - 15)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: UIScreen.main.bounds.width - 32)
                    .padding(.top, 139)
                }
            }
            .preferredColorScheme(.dark)
        }.overlay(alignment: .top) {
            HStack(spacing: 0) {
                Button {
                    // TODO
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                }.glassEffect(.regular.interactive(), in: Circle())
                Spacer()
                Button {
                    // TODO
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                }.glassEffect(.regular.interactive(), in: Circle())
            }.padding(.horizontal, 16)
            .offset(y: 16)
        }
        .overlay(alignment: .bottom) {
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
            .buttonStyle(.plain)
            .offset(y: -1)
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
                        CameraConfigView()
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
