//
//  RichTextEditor.swift
//  Film Data Tagger
//

import SwiftUI
import UIKit

private class AdjustedSelectionRect: UITextSelectionRect {
    private let _rect: CGRect
    private let _writingDirection: NSWritingDirection
    private let _containsStart: Bool
    private let _containsEnd: Bool
    private let _isVertical: Bool

    init(rect: CGRect, writingDirection: NSWritingDirection, containsStart: Bool, containsEnd: Bool, isVertical: Bool) {
        self._rect = rect
        self._writingDirection = writingDirection
        self._containsStart = containsStart
        self._containsEnd = containsEnd
        self._isVertical = isVertical
        super.init()
    }

    override var rect: CGRect { _rect }
    override var writingDirection: NSWritingDirection { _writingDirection }
    override var containsStart: Bool { _containsStart }
    override var containsEnd: Bool { _containsEnd }
    override var isVertical: Bool { _isVertical }
}

private class RichUITextView: UITextView {
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        rect.origin.y += 6.0
        rect.size.height = 23
        return rect
    }

    // iOS uses firstRect(for:) to position the autocomplete suggestion highlight.
    // Without insets, the box follows the full paragraph line box (taller than the
    // visible glyphs), which makes the autocomplete bubble look chunky.
    override func firstRect(for range: UITextRange) -> CGRect {
        let topInset: CGFloat = 5.8
        let bottomInset: CGFloat = -0.6
        var rect = super.firstRect(for: range)
        rect.origin.y += topInset
        rect.size.height = max(0, rect.size.height - topInset - bottomInset)
        return rect
    }

    // Inset the selection rect to track the visible glyphs rather than the full line box.
    // Only crop the top of the first rect (containsStart) and the bottom of the last rect
    // (containsEnd) — middle rects keep their full line-box height so adjacent lines tile
    // without leaving a gap between them. A small negative bottom inset extends 1pt below
    // the line for a snugger fit on the descenders.
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        let topInset: CGFloat = 5.7
        let bottomInset: CGFloat = -1.0
        let rects = super.selectionRects(for: range)
        return rects.map { r in
            let top: CGFloat = r.containsStart ? topInset : 0
            let bottom: CGFloat = r.containsEnd ? bottomInset : 0
            let adjusted = CGRect(
                x: r.rect.origin.x,
                y: r.rect.origin.y + top,
                width: r.rect.width,
                height: max(0, r.rect.height - top - bottom)
            )
            return AdjustedSelectionRect(
                rect: adjusted,
                writingDirection: r.writingDirection,
                containsStart: r.containsStart,
                containsEnd: r.containsEnd,
                isVertical: r.isVertical
            )
        }
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
    var onBlur: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = RichUITextView()
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textContainerInset = UIEdgeInsets(top: 9, left: 18, bottom: 16, right: 18)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = isScrollEnabled
        textView.isEditable = isEditable
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.attributedText = makeAttributedString(from: text)
        textView.typingAttributes = makeAttributes()
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

    private func makeAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacing = paragraphSpacing
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: style,
            .baselineOffset: (lineHeight - font.lineHeight) / 4
        ]
    }

    private func makeAttributedString(from text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: makeAttributes())
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus?()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onBlur?()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
