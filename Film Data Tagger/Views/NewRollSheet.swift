//
//  NewRollSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/22/26.
//

import SwiftUI

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

struct NewRollSheet: View {
    var viewModel: FilmLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var filmName: String = ""
    @State private var exposureCount: Int? = 36

    var body: some View {
        let rollIsValid = !filmName.isEmpty && (exposureCount ?? 0) > 0
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("New Roll")
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .padding(.leading, 8)
                    .foregroundStyle(Color.white.opacity(0.95))
                Spacer()
                Button {
                    dismiss()
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
                    text: $filmName,
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
                        value: $exposureCount,
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
                    selection: $exposureCount,
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
                guard let camera = viewModel.activeCamera else { return }
                viewModel.createRoll(camera: camera, filmStock: filmName, capacity: exposureCount ?? 36)
                dismiss()
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
