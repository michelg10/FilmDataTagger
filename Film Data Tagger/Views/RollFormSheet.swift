//
//  RollFormSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/22/26.
//

import SwiftUI

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

// TODO: audit
struct RollFormSheet: View {
    let viewModel: FilmLogViewModel
    let cameraID: UUID
    var editingRoll: RollSnapshot? = nil
    var defaultFilmStock: String? = nil
    var defaultCapacity: Int? = nil
    var allowSubmitWithPlaceholder: Bool = false
    var onRollCreated: (() -> Void)?
    var formIsAboveAnotherSheet: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var filmName: String = ""
    @State private var exposureCount: Int? = nil
    @State private var placeholder: String = filmStockPlaceholders.randomElement()!

    private var isEditing: Bool { editingRoll != nil }
    private var effectiveFilmName: String {
        filmName.isEmpty && allowSubmitWithPlaceholder ? placeholder : filmName
    }
    private var placeholderCapacity: Int { defaultCapacity ?? 36 }
    private var effectiveExposureCount: Int { exposureCount ?? (allowSubmitWithPlaceholder ? placeholderCapacity : 0) }

    var body: some View {
        let rollIsValid = !effectiveFilmName.isEmpty && effectiveExposureCount > 0 && effectiveExposureCount <= 144
        let extraExposures = editingRoll?.extraExposures ?? 0
        let placeholderOpacity = allowSubmitWithPlaceholder && filmName.isEmpty
            ? 0.55
            : (formIsAboveAnotherSheet ? 0.3 : 0.25)
        FormSheet(title: isEditing ? "Edit roll" : "New roll", sheetHeight: 405, formIsAboveAnotherSheet: formIsAboveAnotherSheet) {
            VStack(spacing: 21) {
                TextField(
                    "Roll name",
                    text: $filmName,
                    prompt: Text(placeholder).foregroundStyle(Color.white.opacity(placeholderOpacity))
                )
                .textFieldStyle(FormTextFieldStyle(formIsAboveAnotherSheet: formIsAboveAnotherSheet))
                FormSeparator(formIsAboveAnotherSheet: formIsAboveAnotherSheet)
                HStack(spacing: 22) {
                    TextField(
                        "Exposures",
                        value: $exposureCount,
                        format: .number.grouping(.never),
                        prompt: Text("\(placeholderCapacity)").foregroundStyle(Color.white.opacity(
                            defaultCapacity != nil ? 0.55 : (formIsAboveAnotherSheet ? 0.3 : 0.25)))
                    ).keyboardType(.numberPad)
                    .textFieldStyle(FormTextFieldStyle(formIsAboveAnotherSheet: formIsAboveAnotherSheet))
                    if extraExposures > 0 {
                        Text("+ \(extraExposures) exposures")
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
                            [12, 15, 24, 36].firstIndex(of: effectiveExposureCount)
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
                .shadow(color: .black.opacity(formIsAboveAnotherSheet ? aboveSheetShadowOpacity : sheetShadowOpacity), radius: formIsAboveAnotherSheet ? aboveSheetShadowRadius : sheetShadowRadius)
            }.padding(.bottom, 44)

            PrimaryButton(enabled: rollIsValid, action: {
                playHaptic(.newRollOrCamera)
                let capacity = effectiveExposureCount
                if let editingRoll {
                    viewModel.editRoll(id: editingRoll.id, filmStock: effectiveFilmName, capacity: capacity)
                } else {
                    viewModel.createRoll(cameraID: cameraID, filmStock: effectiveFilmName, capacity: capacity)
                }
                dismiss()
                onRollCreated?()
            }, isAboveAnotherSheet: formIsAboveAnotherSheet) {
                Text(isEditing ? "Edit roll" : "Add roll")
            }
        }
        .onAppear {
            if let editingRoll {
                filmName = editingRoll.filmStock
                exposureCount = editingRoll.capacity
                placeholder = editingRoll.filmStock
            } else {
                if let defaultFilmStock {
                    placeholder = defaultFilmStock
                }
                if defaultCapacity == nil {
                    exposureCount = 36
                }
            }
        }
    }
}
