//
//  NewRollSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/22/26.
//

import SwiftUI

struct FormTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    var formIsAboveAnotherSheet: Bool = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundStyle(Color.white.opacity(0.95))
            .font(.system(size: 17, weight: .semibold, design: .default))
            .focused($isFocused)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(content: {
                Capsule()
                    .foregroundStyle(formIsAboveAnotherSheet ? Color(hex: 0x323232) : Color(hex: 0x2E2E2E))
            })
            .shadow(color: .black.opacity(formIsAboveAnotherSheet ? 0.24 : 0), radius: 16.5)
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }
    }
}

private let filmStockPlaceholders = [
    // Portra
    "Sproktra 160",
    "Sproktra 400",
    "Sproktra 800",
    
    // Kodak Ektar
    "Sprok Ekzip 100",
    
    // Ektachrome
    "Sprokachrome S100",
    
    // Kodak Pro Image
    "Sprok Max Image 100",
    
    // Kodak Gold
    "Sprok Bold 200",
    
    // Kodak UltraMax
    "Sprok MaxPro 400",
    
    // Kodak ColorPlus 200
    "Sprok ColorAir 200",
    
    // Kodacolor
    "Sprokacolor 200",
    
    // Kodak Tri-X 400
    "Sprok OS-X 400",
    
    // Kodak T-Max 400
    "Sprok T-Ultra 400",
    
    // Kodak T-Max P3200
    "Sprok T-Ultra P3200",
    
    // Fuji Color Negative
    "Sprokbook Color Negative 200",
    "Sprokbook Color Negative 400",
    
    // Fuji Acros 100
    "Sprokros 100",
    
    // Fuji Velvia
    "Sprok Velvia 50",
    "Sprok Velvia 100",
    
    // Fuji Provia
    "Maxvia 100F",
    
    // Ilford HP5 5 Plus
    "Sprokord HP5 Max",
    
    // Ilford FP4 Plus
    "Sprokord FP4 Max",
    
    // Ilford Delta 3200
    "Sprokord Alpha 3200",
    
    // Kentmere Pan 200
    "Sprokmere Pan 200",
    
    // Harman Phoenix
    "CodeAssign Phoenix II 200",
    "CodeAssign Phoenix 200",
    
    // Cinestill
    "SproStill 800T",
    "SproStill 400D",
    
    // Lomography Color Negative
    "Sprokography Color Negative 100",
    "Sprokography Color Negative 400",
    "Sprokography Color Negative 800",
    
    // Generics
    "Sprokbook 100",
    "Sprokbook 200",
    "Sprokbook 400",
    "Sprokbook 800"
]

struct NewRollSheet: View {
    var viewModel: FilmLogViewModel
    var camera: Camera
    var editingRoll: Roll? = nil
    var onRollCreated: (() -> Void)?
    var formIsAboveAnotherSheet: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var filmName: String = ""
    @State private var exposureCount: Int? = 36
    @State private var placeholder: String = filmStockPlaceholders.randomElement()!

    private var isEditing: Bool { editingRoll != nil }

    var body: some View {
        let rollIsValid = !filmName.isEmpty && (exposureCount ?? 0) > 0
        let extraExposures = editingRoll?.extraExposures ?? 0
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(isEditing ? "Edit roll" : "New roll")
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
                    prompt: Text(placeholder).foregroundStyle(Color.white.opacity(formIsAboveAnotherSheet ? 0.3 : 0.25))
                )
                .textFieldStyle(FormTextFieldStyle(formIsAboveAnotherSheet: formIsAboveAnotherSheet))
                // separator
                Rectangle()
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 15)
                    .foregroundStyle(Color.white.opacity(formIsAboveAnotherSheet ? 0.08 : 0.07))
                HStack(spacing: 22) {
                    TextField(
                        "Exposures",
                        value: $exposureCount,
                        format: .number.grouping(.never),
                        prompt: Text("36").foregroundStyle(Color.white.opacity(formIsAboveAnotherSheet ? 0.3 : 0.25))
                    ).keyboardType(.numberPad)
                    .textFieldStyle(FormTextFieldStyle(formIsAboveAnotherSheet: formIsAboveAnotherSheet))
                    if extraExposures > 0 {
                        Text("+\(extraExposures) exposures")
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.55))
                    } else {
                        Text("exposures")
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                UIKitSegmentedControl(
                    segments: ["12", "15", "24", "36"],
                    selectedIndex: Binding(
                        get: {
                            [12, 15, 24, 36].firstIndex(of: exposureCount)
                        },
                        set: { index in
                            exposureCount = index.map { [12, 15, 24, 36][$0] }
                        }
                    ),
                    height: 40,
                    selectedTextAttributes: [
                        .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                    ],
                    normalTextAttributes: [
                        .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                        .kern: -0.45,
                    ],
                    selectedTintColor: UIColor(formIsAboveAnotherSheet ? Color(hex: 0x6D6D6D) : Color(hex: 0x646464)),
                    controlBackgroundColor: UIColor(formIsAboveAnotherSheet ? Color(hex: 0x323232) : Color(hex: 0x2E2E2E))
                )
                .shadow(color: .black.opacity(formIsAboveAnotherSheet ? 0.24 : 0), radius: 16.5)
            }.padding(.bottom, 44)

            PrimaryButton(enabled: rollIsValid, action: {
                playHaptic(.finishRoll)
                if let editingRoll {
                    viewModel.editRoll(editingRoll, filmStock: filmName, capacity: exposureCount ?? 36)
                } else {
                    viewModel.createRoll(camera: camera, filmStock: filmName, capacity: exposureCount ?? 36)
                }
                dismiss()
                onRollCreated?()
            }, isAboveAnotherSheet: formIsAboveAnotherSheet) {
                Text(isEditing ? "Edit roll" : "Add roll")
            }
            
            Spacer(minLength: 0)
        }.padding(.horizontal, 15 + 8)
        .padding(.top, 15 + 7)
        .ignoresSafeArea(.all)
        .presentationDetents([.height(CGFloat(sheetScaleCompensationFactor * 405 - bottomSafeAreaInset))])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.disabled)
        .sheetContentClip(cornerRadius: 35)
        .sheetScaleFix()
        .onAppear {
            if let editingRoll {
                filmName = editingRoll.filmStock
                exposureCount = editingRoll.capacity
                placeholder = editingRoll.filmStock
            }
        }
    }
}
