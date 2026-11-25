import SwiftUI
import UIKit

/// A digits-only `UITextField`, like `MeterReadingNumberTextField`.
/// `keyboardType` is only a keyboard preference on iPad, so the delegate
/// rejects letters from a hardware keyboard, and digits beyond `maxLength`,
/// before UIKit inserts them; a paste keeps only the digits that fit. Every
/// accepted edit reaches the binding synchronously. A SwiftUI `TextField` with
/// its own buffer mirrored the value through `onChange` one render late, so
/// fast typing raced the full-form re-render and the field lagged.
struct DigitsOnlyTextField: UIViewRepresentable {
    @Binding var text: String
    var maxLength: Int?

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .numberPad
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = UIColor(FacilityTheme.ink)
        textField.tintColor = UIColor(FacilityTheme.blue)
        textField.borderStyle = .none
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        textField.isEnabled = context.environment.isEnabled
        if textField.text != text {
            textField.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DigitsOnlyTextField

        init(_ parent: DigitsOnlyTextField) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = (textField.text ?? "") as NSString
            var accepted = string.filter(\.isNumber)
            if let maxLength = parent.maxLength {
                let keptCount = (current as String).count - current.substring(with: range).count
                accepted = String(accepted.prefix(max(0, maxLength - keptCount)))
            }
            guard accepted != string else { return true }
            guard !accepted.isEmpty else { return false }

            textField.text = current.replacingCharacters(in: range, with: accepted)
            let caretOffset = range.location + (accepted as NSString).length
            if let caret = textField.position(from: textField.beginningOfDocument, offset: caretOffset) {
                textField.selectedTextRange = textField.textRange(from: caret, to: caret)
            }
            textDidChange(textField)
            return false
        }

        @objc func textDidChange(_ textField: UITextField) {
            var digits = String((textField.text ?? "").filter(\.isNumber))
            if let maxLength = parent.maxLength {
                digits = String(digits.prefix(maxLength))
            }
            if textField.text != digits {
                textField.text = digits
            }
            if parent.text != digits {
                parent.text = digits
            }
        }
    }
}
