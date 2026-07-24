//
//  ReadOnlyCoordinator.swift
//  Reqeast
//

#if os(macOS)
import Foundation
import CodeEditSourceEditor
import CodeEditTextView

/// Blocks text edits via the TextViewDelegate while keeping selection and copy working.
/// Workaround for CodeEditTextView where isEditable=false prevents cursor placement on click,
/// which breaks double-click word selection.
final class ReadOnlyCoordinator: TextViewCoordinator, TextViewDelegate {
    func prepareCoordinator(controller: TextViewController) {
        controller.textView.delegate = self
    }

    func textView(_ textView: TextView, shouldReplaceContentsIn range: NSRange, with string: String) -> Bool {
        false
    }
}
#endif
