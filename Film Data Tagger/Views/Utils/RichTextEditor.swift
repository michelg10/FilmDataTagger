//
//  RichTextEditor.swift
//  Film Data Tagger
//

import SwiftUI
import UIKit

private class RichUITextView: UITextView {
    var caretHeight: CGFloat?

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        if let caretHeight {
            let diff = rect.height - caretHeight
            if diff > 0 {
                rect.origin.y += diff * 7 / 8 + 1
                rect.size.height = caretHeight
            }
        }
        return rect
    }
}

struct RichTextEditor: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont = .systemFont(ofSize: 17, weight: .regular)
    var textColor: UIColor = .white
    var lineHeight: CGFloat = 24
    var paragraphSpacing: CGFloat = 8
    var isScrollEnabled: Bool = false
    var isEditable: Bool = true
    var onFocus: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = RichUITextView()
        textView.caretHeight = font.lineHeight + 1
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textContainerInset = UIEdgeInsets(top: 13, left: 20, bottom: 16, right: 20)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = isScrollEnabled
        textView.isEditable = isEditable
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.attributedText = makeAttributedString(from: text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            let selectedRange = textView.selectedRange
            textView.attributedText = makeAttributedString(from: text)
            textView.selectedRange = selectedRange
        }
        textView.isEditable = isEditable
        if !isEditable && textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    private func makeAttributedString(from text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacing = paragraphSpacing

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: style,
                .baselineOffset: (lineHeight - font.lineHeight) / 4
            ]
        )
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus?()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
