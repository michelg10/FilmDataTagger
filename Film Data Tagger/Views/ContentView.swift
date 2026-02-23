//
//  ContentView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

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
            }.foregroundStyle(Color.white.opacity(0.95))
            .fontWidth(.expanded)
        }.frame(height: 44)
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
    }
}

struct FormTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundStyle(Color.white.opacity(0.95))
            .font(.system(size: 17, weight: .semibold, design: .default))
            .focused($isFocused)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(content: {
                Capsule()
                    .foregroundStyle(Color(hex: 0x2E2E2E))
            })
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: FilmLogViewModel?
    @State private var showSheet = false
    @State private var showCameraList = false
    @State private var isScrolling = false
    
    @State private var testFilmName: String = ""
    @State private var testExposureCount: Int? = 36

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
                    },
                    onTitleTapped: {
                        showCameraList = true
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
                        frameCount: logItems.count + 1,
                        rollCapacity: viewModel.rollCapacity,
                        lastCaptureDate: logItems.last(where: { $0.hasRealCreatedAt })?.createdAt
                    )
                    .sheet(isPresented: $showCameraList) {
                        CameraListView(
                            entries: viewModel.allCameraListEntries(),
                            onSelectRoll: { roll in
                                viewModel.switchToRoll(roll)
                                showCameraList = false
                            }
                        )
                    }.sheet(isPresented: .constant(true)) {
                        let rollIsValid = !testFilmName.isEmpty && (testExposureCount ?? 0) > 0
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Text("New Roll")
                                    .font(.system(size: 22, weight: .bold, design: .default))
                                    .fontWidth(.expanded)
                                    .padding(.leading, 8)
                                    .foregroundStyle(Color.white.opacity(0.95))
                                Spacer()
                                Button {
                                    // TODO
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 20, weight: .semibold, design: .default))
                                        .foregroundStyle(Color.white.opacity(0.95))
                                        .frame(width: 44, height: 44)
                                }.glassEffect(.regular.tint(.white.opacity(0.06)).interactive(), in: Circle())
                            }.padding(.bottom, 21)
                            
                            VStack(spacing: 21) {
                                TextField(
                                    "Roll name",
                                    text: $testFilmName,
                                    prompt: Text("Sprokbook 400").foregroundStyle(Color.white.opacity(0.25))
                                )
                                .textFieldStyle(FormTextFieldStyle())
                                // separator
                                Rectangle()
                                    .frame(height: 1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 15)
                                    .foregroundStyle(Color.white.opacity(0.07))
                                HStack(spacing: 22) {
                                    TextField(
                                        "Exposures",
                                        value: $testExposureCount,
                                        format: .number.grouping(.never),
                                        prompt: Text("36").foregroundStyle(Color.white.opacity(0.25))
                                    ).keyboardType(.numberPad)
                                    .textFieldStyle(FormTextFieldStyle())
                                    Text("exposures")
                                        .font(.system(size: 17, weight: .semibold, design: .default))
                                        .foregroundStyle(Color.white.opacity(0.55))
                                }
                                Picker(
                                    "Exposures",
                                    selection: $testExposureCount,
                                    content: {
                                        Text("12").tag(12)
                                        Text("15").tag(15)
                                        Text("24").tag(24)
                                        Text("36").tag(36)
                                    }
                                ).pickerStyle(.segmented)
                            }.padding(.bottom, 42)
                            Button {
                                playHaptic(.capture)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Spacer(minLength: 0)
                                    Text("Add roll")
                                    Spacer(minLength: 0)
                                }.foregroundStyle(rollIsValid ? Color.black : Color.white.opacity(0.3))
                                .font(.system(size: 22, weight: .bold, design: .default))
                                .fontWidth(.expanded)
                            }.frame(height: 63)
                            .disabled(!rollIsValid)
                            .glassEffect(.regular.tint(.white.opacity(rollIsValid ? 0.91 : 0.055)).interactive(rollIsValid), in: Capsule(style: .continuous))
                            .contentShape(Capsule())
                            .animation(.easeInOut(duration: 0.12), value: rollIsValid)
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 15 + 8)
                        .padding(.top, 15 + 7)
                        .ignoresSafeArea(.all)
                        .presentationDetents([.height(378)])
                        .presentationDragIndicator(.hidden)
                        .presentationBackgroundInteraction(.disabled)
                        .sheetContentClip(cornerRadius: 35)
                        .sheetScaleFix()
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
