import SwiftUI
import UIKit

/// A text field that takes focus and selects everything in it whenever
/// `focusToken` changes — tap a seat and type, no select-all needed.
///
/// UIKit underneath because selecting programmatically right as a field
/// becomes first responder is reliable there.
struct SelectAllTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: Int
    var returnKey: UIReturnKeyType = .next
    var maxLength = 20
    var onSubmit: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.textAlignment = .center
        field.font = .systemFont(ofSize: 24, weight: .regular)
        field.textColor = UIColor(Color.ink)
        field.tintColor = UIColor(Color.ember)
        field.autocorrectionType = .no
        field.autocapitalizationType = .words
        field.spellCheckingType = .no
        field.textContentType = .name
        field.clearButtonMode = .whileEditing
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        field.returnKeyType = returnKey
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(Color.inkTertiary)]
        )
        field.reloadInputViews()

        guard context.coordinator.focusToken != focusToken else { return }
        context.coordinator.focusToken = focusToken
        // Wait for the field to be in a window before asking for focus, then
        // select on the following turn so the caret placement does not win.
        Task { @MainActor in
            if !field.isFirstResponder {
                field.becomeFirstResponder()
            }
            await Task.yield()
            field.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllTextField
        var focusToken = 0

        init(parent: SelectAllTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let swapped = Range(range, in: current) else { return true }
            return current.replacingCharacters(in: swapped, with: string).count <= parent.maxLength
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}
