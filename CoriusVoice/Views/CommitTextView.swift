import SwiftUI
import SwiftUI
import AppKit

struct CommitTextView: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    let font: NSFont
    let textColor: NSColor
    let isStrikethrough: Bool
    let isFocused: Binding<Bool>?
    let updatesBindingOnChange: Bool

    init(
        text: Binding<String>,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize),
        textColor: NSColor = NSColor.labelColor,
        isStrikethrough: Bool = false,
        isFocused: Binding<Bool>? = nil,
        updatesBindingOnChange: Bool = true
    ) {
        _text = text
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.font = font
        self.textColor = textColor
        self.isStrikethrough = isStrikethrough
        self.isFocused = isFocused
        self.updatesBindingOnChange = updatesBindingOnChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onCommit: onCommit,
            onCancel: onCancel,
            isFocused: isFocused,
            updatesBindingOnChange: updatesBindingOnChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = font
        textView.textColor = textColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("Commit text editor")
        textView.string = text

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = font
        textView.textColor = textColor
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        if isStrikethrough {
            textView.textStorage?.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: textView.string.count))
        } else {
            textView.textStorage?.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: textView.string.count))
        }

        if let isFocused, isFocused.wrappedValue, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let onCommit: () -> Void
        private let onCancel: () -> Void
        private let isFocused: Binding<Bool>?
        private let updatesBindingOnChange: Bool

        init(
            text: Binding<String>,
            onCommit: @escaping () -> Void,
            onCancel: @escaping () -> Void,
            isFocused: Binding<Bool>?,
            updatesBindingOnChange: Bool
        ) {
            self.text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
            self.isFocused = isFocused
            self.updatesBindingOnChange = updatesBindingOnChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if updatesBindingOnChange {
                text.wrappedValue = textView.string
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.typingAttributes[.strikethroughStyle] = 0
            isFocused?.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused?.wrappedValue = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewline(nil)
                    return true
                }
                if !updatesBindingOnChange {
                    text.wrappedValue = textView.string
                }
                onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                textView.insertNewline(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel()
                return true
            }
            return false
        }
    }
}
