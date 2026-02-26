//
//  NewCameraSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/25/26.
//

import SwiftUI

private let standardCameraPlaceholders = [
    "Olymbook XC",
    "Sprokon DA2n",
    "Sprokiya C220",
    "Spronon D-1",
    "Spronon DE-1 Program",
    "Sproca CP",
]

private let instantFilmPlaceholders = [
    "Sprokaroid",
    "Sprokax",
]

private func randomCameraPlaceholder(instantFilm: Bool) -> String {
    if instantFilm {
        return Double.random(in: 0..<1) < 0.11
            ? "1mpossib1e"
            : instantFilmPlaceholders.randomElement()!
    } else {
        return standardCameraPlaceholders.randomElement()!
    }
}

struct NewCameraSheet: View {
    // The NewCameraSheet is only ever presented above another sheet
    var viewModel: FilmLogViewModel
    var onCameraCreated: ((UUID) -> Void)? = nil
    let formIsAboveAnotherSheet = true
    @Environment(\.dismiss) private var dismiss
    @State private var cameraName: String = ""
    @State private var isInstantFilm: Bool = false
    @State private var placeholder: String = randomCameraPlaceholder(instantFilm: false)

    var body: some View {
        FormSheet(title: "New camera", sheetHeight: 366, formIsAboveAnotherSheet: formIsAboveAnotherSheet) {
            VStack(spacing: 21) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Image(systemName: "questionmark.circle.fill")
                        Text(" CAMERA TYPE")
                    }.font(.system(size: 12, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.leading, 8)
                    UIKitSegmentedControl(
                        segments: ["Standard", "Instant Film"],
                        selectedIndex: Binding(
                            get: { isInstantFilm ? 1 : 0 },
                            set: { index in
                                isInstantFilm = (index == 1)
                                placeholder = randomCameraPlaceholder(instantFilm: isInstantFilm)
                            }
                        ),
                        height: 44,
                        selectedTextAttributes: [
                            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                            .foregroundColor: UIColor.white.withAlphaComponent(0.95),
                        ],
                        normalTextAttributes: [
                            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                            .foregroundColor: UIColor.white.withAlphaComponent(0.95),
                        ],
                        selectedTintColor: UIColor(formIsAboveAnotherSheet ? Color(hex: 0x6D6D6D) : Color(hex: 0x646464)),
                        controlBackgroundColor: UIColor(formIsAboveAnotherSheet ? Color(hex: 0x323232) : Color(hex: 0x2E2E2E)),
                        capsuleInset: 3
                    )
                    .shadow(color: .black.opacity(formIsAboveAnotherSheet ? 0.41 : 0), radius: 15.8)
                }
                FormSeparator(formIsAboveAnotherSheet: formIsAboveAnotherSheet)
                TextField(
                    "Camera name",
                    text: $cameraName,
                    prompt: Text(placeholder).foregroundStyle(Color.white.opacity(formIsAboveAnotherSheet ? 0.3 : 0.25))
                )
                .textFieldStyle(FormTextFieldStyle(formIsAboveAnotherSheet: formIsAboveAnotherSheet))
            }.padding(.bottom, 44)

            PrimaryButton(enabled: !cameraName.isEmpty, action: {
                playHaptic(.newRollOrCamera)
                let id: UUID
                if isInstantFilm {
                    id = viewModel.createInstantFilmGroup(name: cameraName).id
                } else {
                    id = viewModel.createCamera(name: cameraName).id
                }
                dismiss()
                onCameraCreated?(id)
            }, isAboveAnotherSheet: formIsAboveAnotherSheet) {
                Text("Add camera")
            }
        }
    }
}
