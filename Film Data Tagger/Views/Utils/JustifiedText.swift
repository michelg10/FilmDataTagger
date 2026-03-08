//
//  JustifiedText.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/25/26.
//

import SwiftUI

struct JustifiedText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let lineSpacing: CGFloat

    init(_ text: String, font: UIFont = .systemFont(ofSize: 17), textColor: UIColor = .white, lineSpacing: CGFloat = 4) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.lineSpacing = lineSpacing
    }

    func makeUIView(context: Context) -> JustifiedLabel {
        let label = JustifiedLabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }

    func updateUIView(_ label: JustifiedLabel, context: Context) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified
        paragraphStyle.lineSpacing = lineSpacing

        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }
}

class JustifiedLabel: UILabel {
    override func layoutSubviews() {
        super.layoutSubviews()
        preferredMaxLayoutWidth = bounds.width
    }

    override var intrinsicContentSize: CGSize {
        guard preferredMaxLayoutWidth > 0 else { return super.intrinsicContentSize }
        var size = super.intrinsicContentSize
        size.width = preferredMaxLayoutWidth
        return size
    }
}
