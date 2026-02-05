import Foundation
import SwiftUI
import AppKit

final class RichTextSelectionManager: ObservableObject {
    static let shared = RichTextSelectionManager()

    @Published var activeBlockID: UUID?
    @Published var hasSelection: Bool = false
    @Published var selectionRect: CGRect?
}

// MARK: - Date Extensions

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var formattedFull: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: self)
    }

    var formattedShort: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - String Extensions

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }

    func truncated(to length: Int, trailing: String = "...") -> String {
        if count <= length {
            return self
        }
        return String(prefix(length)) + trailing
    }

    var wordCount: Int {
        let words = components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }

    var characterCount: Int {
        count
    }

    var fileSafeName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed.replacingOccurrences(of: " ", with: "-")
        let filtered = replaced.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : ""
        }.joined()
        return filtered.isEmpty ? "file" : filtered
    }

    var isSFSymbolName: Bool {
        NSImage(systemSymbolName: self, accessibilityDescription: nil) != nil
    }
}

// MARK: - View Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Workspace Icon View

struct WorkspaceIconView: View {
    let name: String

    var body: some View {
        if name.isSFSymbolName {
            Image(systemName: name)
        } else {
            Text(name)
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int

    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)

    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, byRoundingCorners corners: RectCorner, cornerRadii: CGSize) {
        self.init()

        let topLeft = corners.contains(.topLeft)
        let topRight = corners.contains(.topRight)
        let bottomLeft = corners.contains(.bottomLeft)
        let bottomRight = corners.contains(.bottomRight)

        let radius = cornerRadii.width

        // Start at top-left
        if topLeft {
            move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        } else {
            move(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        // Top edge and top-right corner
        if topRight {
            line(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            appendArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                     radius: radius,
                     startAngle: -90,
                     endAngle: 0,
                     clockwise: false)
        } else {
            line(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        // Right edge and bottom-right corner
        if bottomRight {
            line(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            appendArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                     radius: radius,
                     startAngle: 0,
                     endAngle: 90,
                     clockwise: false)
        } else {
            line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        // Bottom edge and bottom-left corner
        if bottomLeft {
            line(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            appendArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                     radius: radius,
                     startAngle: 90,
                     endAngle: 180,
                     clockwise: false)
        } else {
            line(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        // Left edge and top-left corner
        if topLeft {
            line(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            appendArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                     radius: radius,
                     startAngle: 180,
                     endAngle: 270,
                     clockwise: false)
        } else {
            line(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        close()
    }

    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)

            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }

        return path
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    var formattedDuration: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDurationLong: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Array Extensions

extension Array where Element: Identifiable {
    mutating func update(_ element: Element) {
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        }
    }

    mutating func remove(_ element: Element) {
        removeAll { $0.id == element.id }
    }
}

// MARK: - Rich Text Editor (macOS)

struct RichTextEditorView: NSViewRepresentable {
    @Binding var plainText: String
    @Binding var richTextData: Data?
    let onCommit: () -> Void
    let onCancel: () -> Void
    let baseFont: NSFont
    let textColor: NSColor
    let isStrikethrough: Bool
    let isFocused: Binding<Bool>?
    let updatesBindingOnChange: Bool
    let blockID: UUID?
    let selectionManager: RichTextSelectionManager

    init(
        plainText: Binding<String>,
        richTextData: Binding<Data?>,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        baseFont: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize),
        textColor: NSColor = NSColor.labelColor,
        isStrikethrough: Bool = false,
        isFocused: Binding<Bool>? = nil,
        updatesBindingOnChange: Bool = true,
        blockID: UUID? = nil,
        selectionManager: RichTextSelectionManager = .shared
    ) {
        _plainText = plainText
        _richTextData = richTextData
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.baseFont = baseFont
        self.textColor = textColor
        self.isStrikethrough = isStrikethrough
        self.isFocused = isFocused
        self.updatesBindingOnChange = updatesBindingOnChange
        self.blockID = blockID
        self.selectionManager = selectionManager
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            plainText: $plainText,
            richTextData: $richTextData,
            onCommit: onCommit,
            onCancel: onCancel,
            isFocused: isFocused,
            updatesBindingOnChange: updatesBindingOnChange,
            blockID: blockID,
            selectionManager: selectionManager
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = RichTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.usesRuler = false
        textView.usesFontPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.allowsUndo = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("Rich text editor")

        if let data = richTextData,
           let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
           ) {
            textView.textStorage?.setAttributedString(attributed)
            context.coordinator.lastAppliedData = data
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: textColor
            ]
            textView.textStorage?.setAttributedString(NSAttributedString(string: plainText, attributes: attrs))
        }

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if context.coordinator.isUpdatingFromTextView {
            return
        }

        if let data = richTextData, data != context.coordinator.lastAppliedData {
            if let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            ) {
                textView.textStorage?.setAttributedString(attributed)
                context.coordinator.lastAppliedData = data
            }
        } else if richTextData == nil && textView.string != plainText {
            textView.string = plainText
        }

        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: textColor
        ]
        textView.textColor = textColor
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = true

        let length = textView.string.count
        let fullRange = NSRange(location: 0, length: length)
        if isStrikethrough {
            textView.textStorage?.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
        } else {
            textView.textStorage?.removeAttribute(.strikethroughStyle, range: fullRange)
        }

        if let isFocused, isFocused.wrappedValue, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let plainText: Binding<String>
        private let richTextData: Binding<Data?>
        private let onCommit: () -> Void
        private let onCancel: () -> Void
        private let isFocused: Binding<Bool>?
        private let updatesBindingOnChange: Bool
        private let blockID: UUID?
        private let selectionManager: RichTextSelectionManager
        var isUpdatingFromTextView = false
        var lastAppliedData: Data?

        init(
            plainText: Binding<String>,
            richTextData: Binding<Data?>,
            onCommit: @escaping () -> Void,
            onCancel: @escaping () -> Void,
            isFocused: Binding<Bool>?,
            updatesBindingOnChange: Bool,
            blockID: UUID?,
            selectionManager: RichTextSelectionManager
        ) {
            self.plainText = plainText
            self.richTextData = richTextData
            self.onCommit = onCommit
            self.onCancel = onCancel
            self.isFocused = isFocused
            self.updatesBindingOnChange = updatesBindingOnChange
            self.blockID = blockID
            self.selectionManager = selectionManager
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if updatesBindingOnChange {
                isUpdatingFromTextView = true
                plainText.wrappedValue = textView.string
                let attributed = textView.attributedString()
                if let data = try? attributed.data(
                    from: NSRange(location: 0, length: attributed.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
                ) {
                    richTextData.wrappedValue = data
                    lastAppliedData = data
                }
                isUpdatingFromTextView = false
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused?.wrappedValue = true
            selectionManager.activeBlockID = blockID
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused?.wrappedValue = false
            if selectionManager.activeBlockID == blockID {
                selectionManager.hasSelection = false
                selectionManager.activeBlockID = nil
                selectionManager.selectionRect = nil
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selectionManager.activeBlockID = blockID
            let hasSelection = textView.selectedRange.length > 0
            selectionManager.hasSelection = hasSelection
            if hasSelection {
                let screenRect = textView.firstRect(forCharacterRange: textView.selectedRange, actualRange: nil)
                selectionManager.selectionRect = screenRect
            } else {
                selectionManager.selectionRect = nil
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewline(nil)
                    return true
                }
                if !updatesBindingOnChange {
                    plainText.wrappedValue = textView.string
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

final class RichTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommand = modifiers.contains(.command)
        let isShift = modifiers.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if isCommand, let key {
            switch key {
            case "b":
                toggleFontTrait(.boldFontMask)
                return
            case "i":
                toggleFontTrait(.italicFontMask)
                return
            case "u":
                toggleUnderlineStyle()
                return
            case "k":
                perform(#selector(NSTextView.orderFrontLinkPanel(_:)))
                return
            case "m" where isShift:
                toggleFontTrait(.fixedPitchFontMask)
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
    }

}

// MARK: - NSTextView Formatting Helpers

extension NSTextView {
    func toggleFontTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange
        guard range.length > 0 else { return }
        guard let storage = textStorage else { return }
        let manager = NSFontManager.shared
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let hasTrait = manager.traits(of: font).contains(trait)
            let newFont = hasTrait
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: newFont, range: subrange)
        }
        storage.endEditing()
        didChangeText()
    }

    func toggleUnderlineStyle() {
        let range = selectedRange
        guard range.length > 0 else { return }
        guard let storage = textStorage else { return }
        let existing = storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int
        if let existing, existing != 0 {
            storage.removeAttribute(.underlineStyle, range: range)
        } else {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        didChangeText()
    }

    func toggleStrikethroughStyle() {
        let range = selectedRange
        guard range.length > 0 else { return }
        guard let storage = textStorage else { return }
        let existing = storage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int
        if let existing, existing != 0 {
            storage.removeAttribute(.strikethroughStyle, range: range)
        } else {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        didChangeText()
    }
}
