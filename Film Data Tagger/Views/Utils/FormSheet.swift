//
//  FormSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/25/26.
//

import SwiftUI

struct FormSheet<Content: View>: View {
    var title: String
    var sheetHeight: CGFloat
    var titleBarPadding: CGFloat = 21
    var formIsAboveAnotherSheet: Bool = false
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(title)
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
                }.glassEffect(.regular.tint(.white.opacity(formIsAboveAnotherSheet ? 0.07 : 0.06)).interactive(), in: Circle())
            }.padding(.bottom, titleBarPadding)

            content

            Spacer(minLength: 0)
        }.padding(.horizontal, 15 + 8)
        .padding(.top, 15 + 7)
        .ignoresSafeArea(.all)
        .presentationDetents([.height(CGFloat(sheetScaleCompensationFactor * sheetHeight - bottomSafeAreaInset))])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.disabled)
        .sheetContentClip(cornerRadius: 35)
        .sheetScaleFix()
    }
}

struct FormSeparator: View {
    var formIsAboveAnotherSheet: Bool = false

    var body: some View {
        Rectangle()
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 15)
            .foregroundStyle(Color.white.opacity(formIsAboveAnotherSheet ? 0.08 : 0.07))
    }
}

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
            .shadow(color: .black.opacity(formIsAboveAnotherSheet ? 0.41 : 0), radius: 15.8)
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }
    }
}
