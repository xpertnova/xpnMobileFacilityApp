import SwiftUI
import UIKit

/// A meter reading `UITextField`: digits and one decimal comma, at most
/// `MeterReadingViewModel.maximumDigitCount` digits and `maximumFractionDigits`
/// (`DECIM`) after the comma. The delegate rejects an edit before UIKit
/// inserts it, so a character over the limit never shows; a SwiftUI
/// `TextField` whose binding drops the character can keep showing it.
struct MeterReadingNumberTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var maximumFractionDigits: Int? = nil
    var isFocused: Binding<Bool> = .constant(false)
    var textAlignment: NSTextAlignment = .natural
    var usesMonospacedDigits = false
    var onCommit: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .numberPad
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        textField.font = usesMonospacedDigits
            ? .monospacedDigitSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
            : bodyFont
        textField.textAlignment = textAlignment
        textField.textColor = UIColor(FacilityTheme.ink)
        textField.tintColor = UIColor(FacilityTheme.blue)
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)

        let placeholderColor = UIColor.secondaryLabel
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.isEnabled = context.environment.isEnabled
        if uiView.text != text {
            uiView.text = text
        }

        let placeholderColor = UIColor.secondaryLabel
        uiView.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MeterReadingNumberTextField

        init(_ parent: MeterReadingNumberTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            let current = textField.text ?? ""
            let sanitized = MeterReadingViewModel.sanitizeInput(current, maximumFractionDigits: parent.maximumFractionDigits)
            if current != sanitized {
                textField.text = sanitized
            }
            if parent.text != sanitized {
                parent.text = sanitized
            }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty {
                return true
            }

            let currentText = textField.text ?? ""
            guard let textRange = Range(range, in: currentText) else { return false }
            let projectedText = currentText.replacingCharacters(in: textRange, with: string)

            let sanitized = MeterReadingViewModel.sanitizeInput(projectedText, maximumFractionDigits: parent.maximumFractionDigits)

            if projectedText != sanitized {
                if currentText != sanitized {
                    textField.text = sanitized
                    parent.text = sanitized
                }
                return false
            }

            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                if !self.parent.isFocused.wrappedValue {
                    self.parent.isFocused.wrappedValue = true
                }
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                if self.parent.isFocused.wrappedValue {
                    self.parent.isFocused.wrappedValue = false
                }
            }
            parent.onCommit?()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
