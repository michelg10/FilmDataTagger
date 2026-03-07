//
//  NewCameraSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/25/26.
//

import SwiftUI

let SUPPORT_INSTANT_FILM = false

private let standardCameraPlaceholders = [
    "Olymbook XC",
    "Sprokon DA2n",
    "Sprokiya C220",
    "Spronon D-1",
    "Spronon DE-1 Program",
    "Sproca CP",
]

private let polaroidPlaceholders = [
    "Sprokaroid", // we repeat Sprokaroid twice for it to be more common
    "Sprokaroid",
    "Sprokaroid Swift"
]

private let instaxPlaceholders = [
    "Sprokax",
    "Sprokax Plus",
    "Sprokax Expanded",
]

private func randomCameraPlaceholder(instantFilm: Bool) -> String {
    if instantFilm {
        // easter egg
        if Double.random(in: 0..<1) < 0.11 {
            return "1mpossib1e"
        }
        
        // otherwise, prefer Polaroid, but allow Instax too
        if Double.random(in: 0..<1) < 0.66 {
            return polaroidPlaceholders.randomElement()!
        } else {
            return instaxPlaceholders.randomElement()!
        }
    } else {
        return standardCameraPlaceholders.randomElement()!
    }
}

struct NewCameraSheet: View {
    // The NewCameraSheet is only ever presented above another sheet
    var viewModel: FilmLogViewModel
    var editingEntry: (any CameraListEntry)? = nil
    var onCameraCreated: ((UUID) -> Void)? = nil
    let formIsAboveAnotherSheet = false
    @Environment(\.dismiss) private var dismiss
    @State private var cameraName: String = ""
    @State private var isInstantFilm: Bool = false
    @State private var placeholder: String = randomCameraPlaceholder(instantFilm: false)
    @State private var showInstantFilmInfo = false

    private var isEditing: Bool { editingEntry != nil }

    var body: some View {
        let noun = isInstantFilm ? "group" : "camera"
        FormSheet(title: isEditing ? "Edit \(noun)" : "New \(noun)", sheetHeight: isEditing ? 255 : 366, titleBarPadding: 11, formIsAboveAnotherSheet: formIsAboveAnotherSheet) {
            VStack(spacing: 21) {
                if !isEditing {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Image(systemName: "questionmark.circle.fill")
                            Text(" CAMERA TYPE")
                        }.font(.system(size: 12, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .onTapGesture {
                            showInstantFilmInfo = true
                        }
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
                }
                TextField(
                    "Camera name",
                    text: $cameraName,
                    prompt: Text(placeholder).foregroundStyle(Color.white.opacity(formIsAboveAnotherSheet ? 0.3 : 0.25))
                )
                .textFieldStyle(FormTextFieldStyle(formIsAboveAnotherSheet: formIsAboveAnotherSheet))
            }.padding(.bottom, 44)

            PrimaryButton(enabled: !cameraName.isEmpty && (SUPPORT_INSTANT_FILM || !isInstantFilm), action: {
                playHaptic(.newRollOrCamera)
                if let editingEntry {
                    if let camera = editingEntry as? Camera {
                        viewModel.renameCamera(camera, to: cameraName)
                    } else if let group = editingEntry as? InstantFilmGroup {
                        viewModel.renameInstantFilmGroup(group, to: cameraName)
                    }
                    dismiss()
                } else {
                    let id: UUID
                    if isInstantFilm {
                        id = viewModel.createInstantFilmGroup(name: cameraName).id
                    } else {
                        id = viewModel.createCamera(name: cameraName).id
                    }
                    dismiss()
                    onCameraCreated?(id)
                }
            }, isAboveAnotherSheet: formIsAboveAnotherSheet) {
                if !SUPPORT_INSTANT_FILM && isInstantFilm && !isEditing {
                    Text("Coming soon")
                } else {
                    Text(isEditing ? "Edit \(noun)" : "Add \(noun)")
                }
            }
        }
        .sheet(isPresented: $showInstantFilmInfo) {
            InstantFilmInfoSheet()
        }
        .onAppear {
            if let editingEntry {
                cameraName = editingEntry.displayName
                placeholder = editingEntry.displayName
                isInstantFilm = editingEntry.isInstantFilm
            }
        }
    }
}

struct InstantFilmInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    private static let infoText = "Instant film mode collects exposures from multiple cameras into one shared log — one place for all your shots, regardless of which camera took them. Sprokbook tracks remaining shots on all your cameras so you know when to reload."
    private static let infoFont = UIFont.systemFont(ofSize: 17, weight: .medium)
    private static let infoLineSpacing = 24 - infoFont.lineHeight

    private static var textHeight: CGFloat {
        let horizontalPadding: CGFloat = (15 + 8) * 2 + 8 + 6 // FormSheet padding + leading/trailing
        let width = UIScreen.main.bounds.width - horizontalPadding
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = infoLineSpacing
        let boundingRect = NSAttributedString(
            string: infoText,
            attributes: [.font: infoFont, .paragraphStyle: paragraphStyle]
        ).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                       options: [.usesLineFragmentOrigin, .usesFontLeading],
                       context: nil)
        return ceil(boundingRect.height)
    }

    // chrome: top padding (15) + title bar (44) + titleBarPadding (10) + text + random text space UIKit seems to consistently add (3) + text bottom padding (44) + button (63) + safe area - iOS bottom padding (8pt)
    private static var sheetHeight: CGFloat {
        15 + 44 + 10 + textHeight + 3 + 44 + 63 + bottomSafeAreaInset - 8
    }

    var body: some View {
        print(Self.sheetHeight)
        return FormSheet(title: "Instant film", sheetHeight: Self.sheetHeight, titleBarPadding: 10 + 2, formIsAboveAnotherSheet: true, bottomAlignTitle: true, adjustTopPadding: -2) {
            JustifiedText(
                Self.infoText,
                font: Self.infoFont,
                textColor: .white.withAlphaComponent(0.95),
                lineSpacing: Self.infoLineSpacing
            )
            .padding(.bottom, 44 + 2)
            .padding(.leading, 8)
            .padding(.trailing, 6)

            PrimaryButton(action: {
                dismiss()
            }, isAboveAnotherSheet: true) {
                Text("Got it")
            }
        }
    }
}
