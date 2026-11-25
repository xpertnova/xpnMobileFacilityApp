import SwiftUI
import UIKit

/// Reports how much of the view it backs is covered by the docked keyboard,
/// with the duration of the keyboard's animation.
///
/// It reads the keyboard frame UIKit announces before the keyboard moves, so
/// a view can make room in step with it instead of reacting to a safe-area
/// change that reaches scroll views at a different moment. A floating
/// keyboard covers nothing that could be made room for and reports zero; a
/// hardware keyboard reports only its shortcut bar.
struct KeyboardOverlapReader: UIViewRepresentable {
    let onChange: (_ overlap: CGFloat, _ animationDuration: Double) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    /// How far a keyboard at `keyboardFrame` reaches into `viewFrame`, both in
    /// window coordinates.
    static func overlap(keyboardFrame: CGRect, viewFrame: CGRect, windowBounds: CGRect) -> CGFloat {
        guard !keyboardFrame.isEmpty,
              // A floating keyboard does not reach the window's bottom edge.
              keyboardFrame.maxY >= windowBounds.maxY - 1,
              keyboardFrame.intersects(viewFrame) else { return 0 }
        return max(0, viewFrame.maxY - keyboardFrame.minY)
    }

    final class ReaderView: UIView {
        var onChange: ((CGFloat, Double) -> Void)?
        /// The keyboard's announced end frame in screen coordinates, or `nil`
        /// while it is hidden.
        private var keyboardScreenFrame: CGRect?
        private var reportedOverlap: CGFloat = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHide(_:)),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // The view itself moved or resized; SwiftUI is mid-layout, so
            // report on the next turn of the run loop.
            DispatchQueue.main.async { [weak self] in
                self?.reportOverlap(animationDuration: 0)
            }
        }

        @objc private func keyboardWillChangeFrame(_ notification: Notification) {
            keyboardScreenFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
                .cgRectValue
            reportOverlap(animationDuration: animationDuration(of: notification))
        }

        @objc private func keyboardWillHide(_ notification: Notification) {
            keyboardScreenFrame = nil
            reportOverlap(animationDuration: animationDuration(of: notification))
        }

        private func reportOverlap(animationDuration: Double) {
            let overlap = currentOverlap()
            guard overlap != reportedOverlap else { return }
            reportedOverlap = overlap
            onChange?(overlap, animationDuration)
        }

        private func currentOverlap() -> CGFloat {
            guard let window, let keyboardScreenFrame else { return 0 }
            // Screen and window coordinates differ in Split View and Stage
            // Manager windows.
            return KeyboardOverlapReader.overlap(
                keyboardFrame: window.convert(keyboardScreenFrame, from: window.screen.coordinateSpace),
                viewFrame: convert(bounds, to: window),
                windowBounds: window.bounds
            )
        }

        private func animationDuration(of notification: Notification) -> Double {
            (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
                .doubleValue ?? 0
        }
    }
}
