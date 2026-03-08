import SwiftUI

struct UIKitSegmentedControl: View {
    let segments: [String]
    @Binding var selectedIndex: Int?
    var height: CGFloat = 32
    var selectedTextAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
    ]
    var normalTextAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 13)
    ]
    var selectedTintColor: UIColor? = nil
    let controlBackgroundColor: UIColor
    var capsuleInset: CGFloat = 2

    var body: some View {
        let extraPadding = max(capsuleInset - 2, 0)
        let topInset = extraPadding
        let sideInset = extraPadding
        let bottomInset = extraPadding + 1
        let innerHeight = max(height - topInset - bottomInset, 0)
        InnerSegmentedControl(
            segments: segments,
            selectedIndex: $selectedIndex,
            selectedTextAttributes: selectedTextAttributes,
            normalTextAttributes: normalTextAttributes,
            selectedTintColor: selectedTintColor
        )
        .frame(height: innerHeight)
        .padding(.top, topInset)
        .padding(.horizontal, sideInset)
        .padding(.bottom, bottomInset)
        .background(Color(controlBackgroundColor))
        .clipShape(Capsule())
        .frame(height: height)
    }
}

private struct InnerSegmentedControl: UIViewRepresentable {
    let segments: [String]
    @Binding var selectedIndex: Int?
    let selectedTextAttributes: [NSAttributedString.Key: Any]
    let normalTextAttributes: [NSAttributedString.Key: Any]
    let selectedTintColor: UIColor?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: segments)
        control.isMomentary = false
        control.selectedSegmentIndex = selectedIndex ?? UISegmentedControl.noSegment
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:)),
            for: .valueChanged
        )
        control.setContentHuggingPriority(.required, for: .vertical)
        control.setTitleTextAttributes(normalTextAttributes, for: .normal)
        control.setTitleTextAttributes(selectedTextAttributes, for: .selected)
        control.selectedSegmentTintColor = selectedTintColor
        control.backgroundColor = .clear
        for subview in control.subviews where subview is UIImageView {
            subview.isHidden = true
        }
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        if control.numberOfSegments != segments.count {
            control.removeAllSegments()
            for (index, title) in segments.enumerated() {
                control.insertSegment(withTitle: title, at: index, animated: false)
            }
        } else {
            for (index, title) in segments.enumerated() {
                if control.titleForSegment(at: index) != title {
                    control.setTitle(title, forSegmentAt: index)
                }
            }
        }

        control.setTitleTextAttributes(normalTextAttributes, for: .normal)
        control.setTitleTextAttributes(selectedTextAttributes, for: .selected)
        control.selectedSegmentTintColor = selectedTintColor
        control.backgroundColor = .clear

        let uiIndex = selectedIndex ?? UISegmentedControl.noSegment
        if control.selectedSegmentIndex != uiIndex {
            control.selectedSegmentIndex = uiIndex
        }

        for subview in control.subviews where subview is UIImageView {
            subview.isHidden = true
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UISegmentedControl,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        let height = proposal.height ?? uiView.intrinsicContentSize.height
        return CGSize(width: width, height: height)
    }

    class Coordinator: NSObject {
        var parent: InnerSegmentedControl

        init(_ parent: InnerSegmentedControl) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: UISegmentedControl) {
            if sender.selectedSegmentIndex == UISegmentedControl.noSegment {
                parent.selectedIndex = nil
            } else {
                parent.selectedIndex = sender.selectedSegmentIndex
            }
        }
    }
}
