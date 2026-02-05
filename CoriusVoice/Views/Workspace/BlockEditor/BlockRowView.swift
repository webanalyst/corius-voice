import SwiftUI
import AVKit
import AppKit
import Foundation
import UniformTypeIdentifiers
#if canImport(QuickLookThumbnailing)
import QuickLookThumbnailing
#endif

// MARK: - Meeting Block Utilities

private extension String {
    func meetingNormalizedLines(defaultPrefix: String) -> String {
        let lines = split(separator: "\n", omittingEmptySubsequences: false)
        return lines
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return "" }
                if trimmed.hasPrefix("-") || trimmed.hasPrefix("•") || trimmed.hasPrefix("✅") || trimmed.hasPrefix("→") {
                    return String(line)
                }
                return "\(defaultPrefix)\(trimmed)"
            }
            .joined(separator: "\n")
    }
}

// MARK: - Block Row View

/// Single block row with drag handle, content, and actions
struct BlockRowView: View {
    @Binding var block: Block
    let index: Int
    let isFocused: Bool
    let onFocus: () -> Void
    let onInsertBelow: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onChangeType: () -> Void
    let onDuplicate: () -> Void
    
    @State private var isHovered = false
    @State private var showingMenu = false
    @ObservedObject private var selectionManager = RichTextSelectionManager.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // Drag handle and menu (show on hover)
            HStack(spacing: 2) {
                // Add button
                Button(action: onInsertBelow) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                
                // Drag handle / Menu
                Menu {
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    Divider()
                    
                    Button(action: onMoveUp) {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    
                    Button(action: onMoveDown) {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    
                    Divider()
                    
                    Button(action: onChangeType) {
                        Label("Turn into...", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Divider()
                    
                    Button(action: onDuplicate) {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .opacity(isHovered ? 1 : 0)
            }
            .frame(width: 40)
            
            // Block content
            VStack(alignment: .leading, spacing: 6) {
                blockContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isFocused ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onFocus() }
        .overlay(
            GeometryReader { proxy in
                if shouldShowFloatingBar, let position = floatingBarPosition(in: proxy.frame(in: .global)) {
                    RichTextFormatBar()
                        .position(position)
                        .transition(.opacity)
                }
            }
        )
    }

    private var supportsRichTextToolbar: Bool {
        switch block.type {
        case .paragraph,
             .heading1,
             .heading2,
             .heading3,
             .bulletList,
             .numberedList,
             .todo,
             .toggle,
             .quote,
             .callout:
            return true
        default:
            return false
        }
    }

    private var shouldShowFloatingBar: Bool {
        isFocused &&
        supportsRichTextToolbar &&
        selectionManager.activeBlockID == block.id &&
        selectionManager.hasSelection &&
        selectionManager.selectionRect != nil
    }

    private func floatingBarPosition(in blockFrame: CGRect) -> CGPoint? {
        guard let selectionRect = selectionManager.selectionRect else { return nil }
        let x = max(12, min(blockFrame.width - 12, selectionRect.midX - blockFrame.minX))
        let y = max(8, selectionRect.maxY - blockFrame.minY + 8)
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Block Content
    
    @ViewBuilder
    private var blockContent: some View {
        switch block.type {
        case .paragraph:
            ParagraphBlockView(block: $block)
            
        case .heading1:
            HeadingBlockView(block: $block, level: 1)
            
        case .heading2:
            HeadingBlockView(block: $block, level: 2)
            
        case .heading3:
            HeadingBlockView(block: $block, level: 3)
            
        case .bulletList:
            BulletListBlockView(block: $block)
            
        case .numberedList:
            NumberedListBlockView(block: $block, index: index)
            
        case .todo:
            TodoBlockView(block: $block)
            
        case .toggle:
            ToggleBlockView(block: $block)
            
        case .quote:
            QuoteBlockView(block: $block)
            
        case .callout:
            CalloutBlockView(block: $block)
            
        case .code:
            CodeBlockView(block: $block)
            
        case .divider:
            DividerBlockView()
            
        case .image:
            ImageBlockView(block: $block)

        case .audio:
            AudioBlockView(block: $block)

        case .video:
            VideoBlockView(block: $block)

        case .file:
            FileBlockView(block: $block)

        case .bookmark:
            BookmarkBlockView(block: $block)

        case .embed:
            EmbedBlockView(block: $block)
            
        case .sessionEmbed:
            SessionEmbedBlockView(block: $block)

        case .databaseEmbed:
            DatabaseEmbedBlockView(block: $block)

        case .pageLink:
            PageLinkBlockView(block: $block)

        case .table:
            TableBlockView(block: $block)

        case .columnList:
            ColumnListBlockView(block: $block)

        case .column:
            ColumnBlockView(column: $block)

        case .syncedBlock:
            SyncedBlockView(block: $block)

        case .meetingAgenda:
            MeetingAgendaBlockView(block: $block)

        case .meetingNotes:
            MeetingNotesBlockView(block: $block)

        case .meetingDecisions:
            MeetingDecisionsBlockView(block: $block)

        case .meetingActionItems:
            MeetingActionItemsBlockView(block: $block)

        case .meetingNextSteps:
            MeetingNextStepsBlockView(block: $block)

        case .meetingAttendees:
            MeetingAttendeesBlockView(block: $block)
            
        default:
            // Fallback for unimplemented types
            ParagraphBlockView(block: $block)
        }
    }
}

// MARK: - Rich Text Block Editor

private struct RichTextBlockEditor: View {
    @Binding var block: Block
    var font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    var textColor: NSColor = NSColor.labelColor
    var isStrikethrough: Bool = false
    var minHeight: CGFloat? = nil

    var body: some View {
        RichTextEditorView(
            plainText: $block.content,
            richTextData: $block.richTextData,
            onCommit: { block.updatedAt = Date() },
            onCancel: { },
            baseFont: font,
            textColor: textColor,
            isStrikethrough: isStrikethrough,
            blockID: block.id
        )
        .if(minHeight != nil) { view in
            view.frame(minHeight: minHeight)
        }
    }
}

// MARK: - Rich Text Format Bar

private struct RichTextFormatBar: View {
    @State private var showingLinkPopover = false
    @State private var linkInput = ""

    var body: some View {
        HStack(spacing: 8) {
            formatButton(systemImage: "bold", action: toggleBold)
            formatButton(systemImage: "italic", action: toggleItalic)
            formatButton(systemImage: "underline", action: toggleUnderline)
            formatButton(systemImage: "strikethrough", action: toggleStrikethrough)
            Button(action: toggleHighlight) {
                Image(systemName: "highlighter")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            Divider()
                .frame(height: 16)
            Button(action: {
                linkInput = currentLinkString() ?? ""
                showingLinkPopover = true
            }) {
                Image(systemName: "link")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingLinkPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Link")
                        .font(.headline)
                    TextField("https://example.com", text: $linkInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                    HStack {
                        Button("Remove") {
                            applyLink(nil)
                            showingLinkPopover = false
                        }
                        Spacer()
                        Button("Apply") {
                            applyLink(linkInput.trimmingCharacters(in: .whitespacesAndNewlines))
                            showingLinkPopover = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
            }
            formatButton(systemImage: "chevron.left.forwardslash.chevron.right", action: toggleMonospace)
        }
        .font(.caption)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }

    private func formatButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
    }

    private func currentTextView() -> NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    private func currentLinkString() -> String? {
        guard let textView = currentTextView() else { return nil }
        let range = textView.selectedRange
        guard range.length > 0 else { return nil }
        if let url = textView.textStorage?.attribute(.link, at: range.location, effectiveRange: nil) as? URL {
            return url.absoluteString
        }
        if let string = textView.textStorage?.attribute(.link, at: range.location, effectiveRange: nil) as? String {
            return string
        }
        return nil
    }

    private func toggleHighlight() {
        guard let textView = currentTextView() else { return }
        let range = textView.selectedRange
        guard range.length > 0 else { return }
        let storage = textView.textStorage
        let existing = storage?.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor
        if existing != nil {
            storage?.removeAttribute(.backgroundColor, range: range)
        } else {
            storage?.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: range)
        }
        textView.didChangeText()
    }

    private func toggleBold() {
        guard let textView = currentTextView() else { return }
        textView.toggleFontTrait(.boldFontMask)
    }

    private func toggleItalic() {
        guard let textView = currentTextView() else { return }
        textView.toggleFontTrait(.italicFontMask)
    }

    private func toggleMonospace() {
        guard let textView = currentTextView() else { return }
        textView.toggleFontTrait(.fixedPitchFontMask)
    }

    private func toggleUnderline() {
        guard let textView = currentTextView() else { return }
        textView.toggleUnderlineStyle()
    }

    private func toggleStrikethrough() {
        guard let textView = currentTextView() else { return }
        textView.toggleStrikethroughStyle()
    }

    private func applyLink(_ urlString: String?) {
        guard let textView = currentTextView() else { return }
        let range = textView.selectedRange
        guard range.length > 0 else { return }
        let storage = textView.textStorage
        guard let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            storage?.removeAttribute(.link, range: range)
            textView.didChangeText()
            return
        }
        let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
        if let url {
            storage?.addAttribute(.link, value: url, range: range)
            textView.didChangeText()
        }
    }
}

// MARK: - Paragraph Block

struct ParagraphBlockView: View {
    @Binding var block: Block
    
    var body: some View {
        SlashCommandMenuHost(block: $block) {
            RichTextBlockEditor(block: $block)
        }
    }
}

// MARK: - Heading Block

struct HeadingBlockView: View {
    @Binding var block: Block
    let level: Int
    
    private var font: Font {
        switch level {
        case 1: return .system(size: 28, weight: .bold)
        case 2: return .system(size: 22, weight: .semibold)
        case 3: return .system(size: 18, weight: .medium)
        default: return .body
        }
    }
    
    var body: some View {
        SlashCommandMenuHost(block: $block) {
            RichTextBlockEditor(
                block: $block,
                font: NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
            )
        }
    }

    private var fontSize: CGFloat {
        switch level {
        case 1: return 28
        case 2: return 22
        case 3: return 18
        default: return NSFont.systemFontSize
        }
    }

    private var fontWeight: NSFont.Weight {
        switch level {
        case 1: return .bold
        case 2: return .semibold
        case 3: return .medium
        default: return .regular
        }
    }

    private var placeholder: String {
        "Heading \(level)"
    }
}

// MARK: - Bullet List Block

struct BulletListBlockView: View {
    @Binding var block: Block
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)

            SlashCommandMenuHost(block: $block) {
                RichTextBlockEditor(block: $block)
            }
        }
    }
}

// MARK: - Numbered List Block

struct NumberedListBlockView: View {
    @Binding var block: Block
    let index: Int
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1).")
                .foregroundColor(.secondary)
                .frame(minWidth: 20, alignment: .trailing)

            SlashCommandMenuHost(block: $block) {
                RichTextBlockEditor(block: $block)
            }
        }
    }
}

// MARK: - Todo Block

struct TodoBlockView: View {
    @Binding var block: Block
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: { block.isChecked.toggle() }) {
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(block.isChecked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            SlashCommandMenuHost(block: $block) {
                RichTextBlockEditor(
                    block: $block,
                    textColor: block.isChecked ? NSColor.secondaryLabelColor : NSColor.labelColor,
                    isStrikethrough: block.isChecked
                )
            }
        }
    }
}

// MARK: - Toggle Block

struct ToggleBlockView: View {
    @Binding var block: Block
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: { withAnimation { block.toggleExpand() } }) {
                    Image(systemName: block.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)

                SlashCommandMenuHost(block: $block) {
                    RichTextBlockEditor(
                        block: $block,
                        font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
                    )
                }
            }
            
            if block.isExpanded {
                ToggleChildrenView(parent: $block)
                    .padding(.leading, 24)
            }
        }
    }
}

// MARK: - Toggle Children Editor

struct ToggleChildrenView: View {
    @Binding var parent: Block
    @State private var focusedChildID: UUID?
    @State private var draggedChildID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(parent.children.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 6) {
                    Button(action: { deleteChild(at: index) }) {
                        Image(systemName: "minus.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(parent.children.count > 1 ? 1 : 0)

                    InlineBlockContentView(block: $parent.children[index], index: index)
                        .onTapGesture { focusedChildID = parent.children[index].id }

                    Spacer(minLength: 0)

                    Menu {
                        Button("Move Up") { moveChild(from: index, direction: -1) }
                        Button("Move Down") { moveChild(from: index, direction: 1) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.borderlessButton)
                }
                .onDrag {
                    let id = parent.children[index].id
                    draggedChildID = id
                    return NSItemProvider(object: id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: BlockReorderDropDelegate(
                    blocks: $parent.children,
                    draggedID: $draggedChildID,
                    targetID: parent.children[index].id,
                    onReorder: { parent.updatedAt = Date() }
                ))
                .padding(.vertical, 2)
            }

            Button(action: addChild) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption)
                    Text("Add toggle item")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .opacity(0.8)
        }
    }

    private func addChild() {
        let newChild = Block(type: .paragraph, content: "")
        parent.children.append(newChild)
        focusedChildID = newChild.id
        parent.updatedAt = Date()
    }

    private func deleteChild(at index: Int) {
        guard parent.children.indices.contains(index) else { return }
        parent.children.remove(at: index)
        parent.updatedAt = Date()
    }

    private func moveChild(from index: Int, direction: Int) {
        let newIndex = index + direction
        guard parent.children.indices.contains(index), parent.children.indices.contains(newIndex) else { return }
        parent.children.swapAt(index, newIndex)
        parent.updatedAt = Date()
    }
}

// MARK: - Inline Block Content

struct InlineBlockContentView: View {
    @Binding var block: Block
    let index: Int

    var body: some View {
        switch block.type {
        case .paragraph:
            ParagraphBlockView(block: $block)
        case .heading1:
            HeadingBlockView(block: $block, level: 1)
        case .heading2:
            HeadingBlockView(block: $block, level: 2)
        case .heading3:
            HeadingBlockView(block: $block, level: 3)
        case .bulletList:
            BulletListBlockView(block: $block)
        case .numberedList:
            NumberedListBlockView(block: $block, index: index)
        case .todo:
            TodoBlockView(block: $block)
        case .quote:
            QuoteBlockView(block: $block)
        case .callout:
            CalloutBlockView(block: $block)
        case .code:
            CodeBlockView(block: $block)
        case .divider:
            DividerBlockView()
        case .meetingAgenda:
            MeetingAgendaBlockView(block: $block)
        case .meetingNotes:
            MeetingNotesBlockView(block: $block)
        case .meetingDecisions:
            MeetingDecisionsBlockView(block: $block)
        case .meetingActionItems:
            MeetingActionItemsBlockView(block: $block)
        case .meetingNextSteps:
            MeetingNextStepsBlockView(block: $block)
        case .meetingAttendees:
            MeetingAttendeesBlockView(block: $block)
        default:
            ParagraphBlockView(block: $block)
        }
    }
}

// MARK: - Quote Block

struct QuoteBlockView: View {
    @Binding var block: Block
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 3)

            SlashCommandMenuHost(block: $block) {
                RichTextBlockEditor(
                    block: $block,
                    font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize), toHaveTrait: .italicFontMask)
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Meeting Blocks

struct MeetingAgendaBlockView: View {
    @Binding var block: Block

    var body: some View {
        MeetingSectionBlock(
            title: "Agenda",
            subtitle: "List the topics to cover",
            placeholder: "Agenda item",
            icon: "list.bullet.rectangle",
            addLabel: "Add agenda item",
            autoPrefix: "• ",
            block: $block
        )
    }
}

struct MeetingNotesBlockView: View {
    @Binding var block: Block

    var body: some View {
        MeetingSectionBlock(
            title: "Notes",
            subtitle: "Capture discussion details",
            placeholder: "Add meeting notes",
            icon: "note.text",
            addLabel: "Add note",
            autoPrefix: "",
            block: $block
        )
    }
}

struct MeetingDecisionsBlockView: View {
    @Binding var block: Block

    var body: some View {
        MeetingSectionBlock(
            title: "Decisions",
            subtitle: "Record decisions and outcomes",
            placeholder: "Decision",
            icon: "checkmark.seal",
            addLabel: "Add decision",
            autoPrefix: "✅ ",
            block: $block
        )
    }
}

struct MeetingActionItemsBlockView: View {
    @Binding var block: Block

    var body: some View {
        MeetingSectionBlock(
            title: "Action Items",
            subtitle: "Turn tasks into follow-ups",
            placeholder: "[ ] Action item",
            icon: "checkmark.circle",
            addLabel: "Add action item",
            autoPrefix: "- [ ] ",
            block: $block
        )
    }
}

struct MeetingNextStepsBlockView: View {
    @Binding var block: Block

    var body: some View {
        MeetingSectionBlock(
            title: "Next Steps",
            subtitle: "Capture follow-up steps",
            placeholder: "Next step",
            icon: "arrow.forward.circle",
            addLabel: "Add next step",
            autoPrefix: "→ ",
            block: $block
        )
    }
}

struct MeetingAttendeesBlockView: View {
    @Binding var block: Block

    var body: some View {
        MeetingSectionBlock(
            title: "Attendees",
            subtitle: "Track who attended",
            placeholder: "Attendee name",
            icon: "person.2",
            addLabel: "Add attendee",
            autoPrefix: "• ",
            block: $block
        )
    }
}

private struct MeetingSectionBlock: View {
    let title: String
    let subtitle: String
    let placeholder: String
    let icon: String
    let addLabel: String
    let autoPrefix: String
    @Binding var block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            SlashCommandMenuHost(block: $block) {
                CommitTextView(
                    text: $block.content,
                    onCommit: { block.updatedAt = Date(); normalize() },
                    onCancel: { },
                    font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
                )
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .onAppear {
                    normalize()
                }
            }

            Button(action: appendLine) {
                Label(addLabel, systemImage: "plus")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .onAppear {
            normalize()
        }
    }

    private func appendLine() {
        let trimmed = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let newLine = trimmed.isEmpty ? "" : "\n"
        block.content += "\(newLine)\(autoPrefix)"
        block.updatedAt = Date()
    }

    private func normalize() {
        guard !autoPrefix.isEmpty else { return }
        block.content = block.content.meetingNormalizedLines(defaultPrefix: autoPrefix)
    }
}

// MARK: - Callout Block

struct CalloutBlockView: View {
    @Binding var block: Block
    
    private var iconText: String {
        block.icon?.isEmpty == false ? block.icon! : "💡"
    }
    
    private var bgColor: String {
        block.color?.isEmpty == false ? block.color! : "#FEF3C7"
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(iconText)
                .font(.title2)

            SlashCommandMenuHost(block: $block) {
                RichTextBlockEditor(block: $block)
            }

        }
        .padding(12)
        .background(Color(hex: bgColor).opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Code Block

struct CodeBlockView: View {
    @Binding var block: Block
    
    private let languages = ["swift", "python", "javascript", "typescript", "rust", "go", "java", "kotlin", "ruby", "shell"]
    
    private var languageBinding: Binding<String> {
        Binding(
            get: { block.language ?? "swift" },
            set: { block.language = $0 }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language selector
            HStack {
                Picker("", selection: languageBinding) {
                    ForEach(languages, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                
                Spacer()
                
                Button(action: copyCode) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Code editor
            SlashCommandMenuHost(block: $block, activation: .leadingOnly) {
                CommitTextView(
                    text: $block.content,
                    onCommit: { block.updatedAt = Date() },
                    onCancel: { },
                    font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                )
                .padding(12)
                .frame(minHeight: 100)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.content, forType: .string)
    }
}

// MARK: - Divider Block

struct DividerBlockView: View {
    var body: some View {
        Divider()
            .padding(.vertical, 8)
    }
}

// MARK: - Image Block

struct ImageBlockView: View {
    @Binding var block: Block
    @State private var isHovered = false
    @State private var loadFailed = false

    private var resolvedURL: URL? {
        AttachmentService.shared.resolveURL(block.url)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = resolvedURL {
                    if url.isFileURL {
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 400)
                                .cornerRadius(8)
                        } else {
                            imagePlaceholder(error: true)
                        }
                    } else {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 400)
                                    .cornerRadius(8)
                            case .failure:
                                imagePlaceholder(error: true)
                            case .empty:
                                ProgressView()
                                    .frame(height: 200)
                            @unknown default:
                                imagePlaceholder(error: false)
                            }
                        }
                    }
                } else {
                    imagePlaceholder(error: loadFailed)
                }
            }
            .onTapGesture {
                if resolvedURL == nil {
                    pickImage()
                }
            }

            HStack(spacing: 8) {
                Button(resolvedURL == nil ? "Add image" : "Replace image") {
                    pickImage()
                }
                .buttonStyle(.bordered)

                if resolvedURL != nil {
                    Button("Remove") {
                        block.url = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
        }
        .onHover { isHovered = $0 }
    }
    
    private func imagePlaceholder(error: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: error ? "exclamationmark.triangle" : "photo")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text(error ? "Failed to load image" : "Click to add image")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func pickImage() {
#if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let stored = try AttachmentService.shared.importFile(from: url)
                block.url = stored
                if block.content.isEmpty {
                    block.content = url.lastPathComponent
                }
                loadFailed = false
            } catch {
                loadFailed = true
            }
        }
#endif
    }
}

// MARK: - Bookmark Block

struct BookmarkBlockView: View {
    @Binding var block: Block

    private var resolvedURL: URL? {
        guard let urlString = block.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return nil }
        if let url = URL(string: urlString), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(urlString)")
    }

    private var hostText: String {
        resolvedURL?.host ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlockURLInput(url: $block.url, placeholder: "Paste URL to create a bookmark")

            if let url = resolvedURL {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.content.isEmpty ? url.absoluteString : block.content)
                            .fontWeight(.medium)
                            .lineLimit(2)
                        if !hostText.isEmpty {
                            Text(hostText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Link("Open", destination: url)
                        .font(.caption)
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            } else {
                placeholderCard(icon: "bookmark", title: "Bookmark", subtitle: "Add a link to preview")
            }
        }
    }
}

// MARK: - File Block

struct FileBlockView: View {
    @Binding var block: Block

    private var resolvedURL: URL? {
        AttachmentService.shared.resolveURL(block.url)
    }

    private var fileName: String {
        AttachmentService.shared.displayName(for: block.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlockURLInput(url: $block.url, placeholder: "Paste file URL or path")

            if let url = resolvedURL {
                if url.isFileURL {
                    FilePreviewView(url: url)
                }

                HStack(spacing: 12) {
                    Image(systemName: "doc")
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.content.isEmpty ? fileName : block.content)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(url.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if let size = fileSizeText(for: url) {
                            Text(size)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Link("Open", destination: url)
                        .font(.caption)
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                
                HStack(spacing: 8) {
                    Button("Replace file") {
                        pickFile()
                    }
                    .buttonStyle(.bordered)

                    Button("Remove") {
                        block.url = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    placeholderCard(icon: "doc", title: "File", subtitle: "Attach a file or link")
                    Button("Attach file") {
                        pickFile()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func pickFile() {
#if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let stored = try AttachmentService.shared.importFile(from: url)
                block.url = stored
                if block.content.isEmpty {
                    block.content = url.lastPathComponent
                }
            } catch {
                // Ignore for now, we can add UI later
            }
        }
#endif
    }

    private func fileSizeText(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

// MARK: - File Preview

private struct FilePreviewView: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @State private var isLoading = false

    private let size = CGSize(width: 280, height: 180)

    var body: some View {
        ZStack {
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: size.height)
                    .cornerRadius(8)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: size.height)
            } else {
                placeholder
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Preview")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: size.height)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func generateThumbnail() {
        guard thumbnail == nil else { return }
        isLoading = true

        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .image),
           let image = NSImage(contentsOf: url) {
            thumbnail = image
            isLoading = false
            return
        }

        #if canImport(QuickLookThumbnailing)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            DispatchQueue.main.async {
                if let representation {
                    thumbnail = representation.nsImage
                } else {
                    thumbnail = NSWorkspace.shared.icon(forFile: url.path)
                }
                isLoading = false
            }
        }
        #else
        thumbnail = NSWorkspace.shared.icon(forFile: url.path)
        isLoading = false
        #endif
    }
}

// MARK: - Audio Block

struct AudioBlockView: View {
    @Binding var block: Block

    private var resolvedURL: URL? {
        guard let urlString = block.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlockURLInput(url: $block.url, placeholder: "Paste audio URL")

            if let url = resolvedURL {
                AudioPlayerView(url: url)
                    .frame(height: 44)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            } else {
                placeholderCard(icon: "waveform", title: "Audio", subtitle: "Embed an audio file")
            }
        }
    }
}

// MARK: - Video Block

struct VideoBlockView: View {
    @Binding var block: Block

    private var resolvedURL: URL? {
        guard let urlString = block.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlockURLInput(url: $block.url, placeholder: "Paste video URL")

            if let url = resolvedURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .cornerRadius(8)
            } else {
                placeholderCard(icon: "play.rectangle", title: "Video", subtitle: "Embed a video")
            }
        }
    }
}

// MARK: - Embed Block

struct EmbedBlockView: View {
    @Binding var block: Block

    private var resolvedURL: URL? {
        guard let urlString = block.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return nil }
        if let url = URL(string: urlString), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(urlString)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlockURLInput(url: $block.url, placeholder: "Paste URL to embed")

            if let url = resolvedURL {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.content.isEmpty ? url.absoluteString : block.content)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(url.host ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Link("Open", destination: url)
                        .font(.caption)
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            } else {
                placeholderCard(icon: "link", title: "Embed", subtitle: "Embed any URL")
            }
        }
    }
}

// MARK: - Database Embed Block

struct DatabaseEmbedBlockView: View {
    @Binding var block: Block
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var statusMessage: String?
    @State private var showingPicker = false
    @State private var showingLinkedPicker = false

    private var databaseID: UUID? {
        guard let raw = block.metadata["databaseID"] else { return nil }
        return UUID(uuidString: raw)
    }

    private var linkedDatabase: Database? {
        if let id = databaseID {
            return storage.database(withID: id)
        }
        return nil
    }

    private var relationPropertyName: String? {
        block.metadata["relationProperty"]
    }

    private var relationTargetID: UUID? {
        guard let raw = block.metadata["relationTargetID"] else { return nil }
        return UUID(uuidString: raw)
    }

    private var relationTargetPage: WorkspaceItem? {
        guard let id = relationTargetID else { return nil }
        return storage.items.first { $0.id == id }
    }

    private var relationProperties: [PropertyDefinition] {
        guard let database = linkedDatabase else { return [] }
        return database.properties.filter { $0.type == .relation }
    }

    private var viewType: DatabaseViewType {
        if let raw = block.metadata["viewType"], let value = DatabaseViewType(rawValue: raw) {
            return value
        }
        return linkedDatabase?.defaultView ?? .kanban
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Database name or ID", text: $block.content)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { resolveDatabase() }

                Button("Select") {
                    showingPicker = true
                }
                .buttonStyle(.borderless)
            }

            if let database = linkedDatabase {
                HStack(spacing: 12) {
                    Image(systemName: database.icon)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(database.name)
                            .fontWeight(.medium)
                        Text("\(storage.items(inDatabase: database.id).count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Menu {
                        ForEach(DatabaseViewType.allCases, id: \.self) { type in
                            Button(type.displayName) {
                                block.metadata["viewType"] = type.rawValue
                            }
                        }
                    } label: {
                        Text(viewType.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                linkedControls(for: database)

                embeddedPreview(for: database)
            } else {
                placeholderCard(icon: "rectangle.split.3x1", title: "Database", subtitle: "Type a database name or ID")
            }

            if let message = statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: block.content) { _, _ in
            statusMessage = nil
        }
        .sheet(isPresented: $showingPicker) {
            DatabasePickerView(
                databases: storage.databases,
                onSelect: { database in
                    linkDatabase(database)
                    showingPicker = false
                }
            )
        }
        .sheet(isPresented: $showingLinkedPicker) {
            PagePickerView(
                pages: storage.items.filter { $0.itemType == .page && !$0.isArchived },
                onSelect: { page in
                    block.metadata["relationTargetID"] = page.id.uuidString
                    showingLinkedPicker = false
                }
            )
        }
    }

    private func resolveDatabase() {
        let query = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let id = UUID(uuidString: query), let database = storage.database(withID: id) {
            linkDatabase(database)
            return
        }

        if let database = storage.databases.first(where: { $0.name.lowercased() == query.lowercased() }) {
            linkDatabase(database)
            return
        }

        statusMessage = "Database not found"
    }

    private func linkDatabase(_ database: Database) {
        block.metadata["databaseID"] = database.id.uuidString
        block.content = database.name
        statusMessage = "Linked to \(database.name)"
    }

    @ViewBuilder
    private func linkedControls(for database: Database) -> some View {
        if !relationProperties.isEmpty {
            HStack(spacing: 8) {
                Text("Linked")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Menu {
                    Button("None") {
                        block.metadata.removeValue(forKey: "relationProperty")
                        block.metadata.removeValue(forKey: "relationTargetID")
                    }
                    Divider()
                    ForEach(relationProperties) { property in
                        Button(property.name) {
                            block.metadata["relationProperty"] = property.name
                        }
                    }
                } label: {
                    Text(relationPropertyName ?? "Relation property")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)

                Button(action: { showingLinkedPicker = true }) {
                    Text(relationTargetPage?.displayTitle ?? "Select page")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(relationPropertyName == nil)

                Spacer()
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func embeddedPreview(for database: Database) -> some View {
        let items = filteredItems(for: database).sorted { $0.updatedAt > $1.updatedAt }
        switch viewType {
        case .list:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.prefix(8)) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.itemType == .task ? "checkmark.circle" : "doc.text")
                            .foregroundColor(.secondary)
                        Text(item.displayTitle)
                            .lineLimit(1)
                        Spacer()
                        if let status = statusValue(for: item, database: database) {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(item.updatedAt.relativeString)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if items.count > 8 {
                    Text("+\(items.count - 8) more items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(8)

        case .table:
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Status")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Due")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach(items.prefix(6)) { item in
                    GridRow {
                        Text(item.displayTitle)
                            .lineLimit(1)
                        Text(statusValue(for: item, database: database) ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(dueDateText(for: item, database: database))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(8)

        case .kanban:
            HStack(spacing: 8) {
                ForEach(database.sortedColumns.prefix(4)) { column in
                    let count = storage.items(inDatabase: database.id, withStatus: column.name).count
                    VStack(spacing: 4) {
                        Text(column.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("\(count)")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(6)
                }
            }

        case .gallery:
            let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(items.prefix(6)) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)

                        if let status = statusValue(for: item, database: database) {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        let dueText = dueDateText(for: item, database: database)
                        if !dueText.isEmpty {
                            Text(dueText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                }
            }

        case .calendar:
            CalendarPreviewView(items: items, database: database)

        default:
            Text("Preview not available for \(viewType.displayName) yet")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .cornerRadius(8)
        }
    }

    private func filteredItems(for database: Database) -> [WorkspaceItem] {
        var results = storage.items(inDatabase: database.id)
        guard let propertyName = relationPropertyName,
              let targetID = relationTargetID else { return results }
        let key = storageKey(for: propertyName, in: database)
        results = results.filter { item in
            switch item.properties[key] {
            case .relation(let id):
                return id == targetID
            case .relations(let ids):
                return ids.contains(targetID)
            default:
                return false
            }
        }
        return results
    }

    private func storageKey(for name: String, in database: Database) -> String {
        if let definition = database.properties.first(where: { $0.name == name }) {
            return definition.storageKey
        }
        return PropertyDefinition.legacyKey(for: name)
    }

    private func statusValue(for item: WorkspaceItem, database: Database) -> String? {
        if let definition = database.properties.first(where: { $0.type == .status }) {
            if case .select(let status) = (item.properties[definition.storageKey]
                ?? item.properties[PropertyDefinition.legacyKey(for: definition.name)]
                ?? .empty) {
                return status
            }
        }
        return item.statusValue
    }

    private func dueDateText(for item: WorkspaceItem, database: Database) -> String {
        guard let definition = database.properties.first(where: { $0.type == .date }) else { return "" }
        let key = definition.storageKey
        if case .date(let date) = (item.properties[key] ?? item.properties[PropertyDefinition.legacyKey(for: definition.name)] ?? .empty) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return ""
    }
}

struct CalendarPreviewView: View {
    let items: [WorkspaceItem]
    let database: Database

    private var calendar: Calendar { Calendar.current }

    private var monthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: components) ?? Date()
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    private var firstWeekdayOffset: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday + 6) % 7
    }

    private var itemsByDay: [Int: [WorkspaceItem]] {
        var result: [Int: [WorkspaceItem]] = [:]
        let definition = database.properties.first(where: { $0.type == .date })
        let key = definition?.storageKey ?? ""
        let legacyKey = definition.map { PropertyDefinition.legacyKey(for: $0.name) } ?? ""
        for item in items {
            let value = item.properties[key]
                ?? item.properties[legacyKey]
                ?? item.properties["dueDate"]
            guard case .date(let date) = value else { continue }
            let day = calendar.component(.day, from: date)
            if calendar.isDate(date, equalTo: monthStart, toGranularity: .month) {
                result[day, default: []].append(item)
            }
        }
        return result
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Color.clear.frame(height: 48)
                }

                ForEach(1...daysInMonth, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(day)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let dayItems = itemsByDay[day], let first = dayItems.first {
                            Text(first.displayTitle)
                                .font(.caption2)
                                .lineLimit(1)
                            if dayItems.count > 1 {
                                Text("+\(dayItems.count - 1)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
    }
}

// MARK: - Page Link Block

struct PageLinkBlockView: View {
    @Binding var block: Block
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var statusMessage: String?
    @State private var showingPicker = false

    private var pageID: UUID? {
        guard let raw = block.metadata["pageID"] else { return nil }
        return UUID(uuidString: raw)
    }

    private var linkedPage: WorkspaceItem? {
        if let id = pageID {
            return storage.items.first(where: { $0.id == id })
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Page title or ID", text: $block.content)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { resolvePage() }

                Button("Select") {
                    showingPicker = true
                }
                .buttonStyle(.borderless)
            }

            if let page = linkedPage {
                HStack(spacing: 12) {
                    Text(page.icon)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.displayTitle)
                            .fontWeight(.medium)
                        Text(page.itemType == .page ? "Page" : "Item")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(page.updatedAt.relativeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            } else {
                placeholderCard(icon: "doc.text", title: "Page link", subtitle: "Link to another page")
            }

            if let message = statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: block.content) { _, _ in
            statusMessage = nil
        }
        .sheet(isPresented: $showingPicker) {
            PagePickerView(
                pages: storage.items.filter { $0.itemType == .page && !$0.isArchived },
                onSelect: { page in
                    linkPage(page)
                    showingPicker = false
                }
            )
        }
    }

    private func resolvePage() {
        let query = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let id = UUID(uuidString: query), let page = storage.items.first(where: { $0.id == id }) {
            linkPage(page)
            return
        }

        if let page = storage.items.first(where: { $0.displayTitle.lowercased() == query.lowercased() }) {
            linkPage(page)
            return
        }

        statusMessage = "Page not found"
    }

    private func linkPage(_ page: WorkspaceItem) {
        block.metadata["pageID"] = page.id.uuidString
        block.content = page.displayTitle
        statusMessage = "Linked to \(page.displayTitle)"
    }
}

// MARK: - Table Block

struct TableBlockView: View {
    @Binding var block: Block
    @State private var tableData: EnhancedTableData = .defaultTable
    @State private var editingCell: (row: UUID, column: UUID)?
    @State private var hoveredRow: UUID?
    @State private var hoveredColumn: UUID?
    @State private var showColumnMenu: UUID?
    @State private var draggedRow: UUID?
    @State private var draggedColumn: UUID?
    @State private var isResizingColumn: UUID?
    @State private var resizeStartWidth: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Table header bar
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .foregroundColor(.secondary)
                Text("Table")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // View options
                Menu {
                    Toggle("Show Header", isOn: $tableData.showHeader)
                    Divider()
                    Button("Add Column") { addColumn() }
                    Button("Add Row") { addRow() }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Table content
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    // Column headers
                    if tableData.showHeader {
                        HStack(spacing: 0) {
                            // Row handle placeholder
                            Color.clear.frame(width: 28)
                            
                            ForEach(tableData.columns) { column in
                                TableColumnHeader(
                                    column: column,
                                    isHovered: hoveredColumn == column.id,
                                    showMenu: showColumnMenu == column.id,
                                    onSort: { sortByColumn(column.id) },
                                    onRename: { newName in renameColumn(column.id, newName) },
                                    onChangeType: { newType in changeColumnType(column.id, newType) },
                                    onDelete: { deleteColumn(column.id) },
                                    onMenuToggle: { showColumnMenu = showColumnMenu == column.id ? nil : column.id }
                                )
                                .frame(width: column.width)
                                .onHover { isHovered in
                                    hoveredColumn = isHovered ? column.id : nil
                                }
                                
                                // Column resizer
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 4)
                                    .contentShape(Rectangle())
                                    .cursor(.resizeLeftRight)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                if isResizingColumn != column.id {
                                                    isResizingColumn = column.id
                                                    resizeStartWidth = column.width
                                                }
                                                let newWidth = max(80, resizeStartWidth + value.translation.width)
                                                if let index = tableData.columns.firstIndex(where: { $0.id == column.id }) {
                                                    tableData.columns[index].width = newWidth
                                                }
                                            }
                                            .onEnded { _ in
                                                isResizingColumn = nil
                                                persistTableData()
                                            }
                                    )
                            }
                            
                            // Add column button
                            Button(action: addColumn) {
                                Image(systemName: "plus")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 40, height: 32)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        }
                        
                        Divider()
                    }
                    
                    // Table rows
                    ForEach(tableData.rows) { row in
                        TableBlockRowView(
                            row: row,
                            columns: tableData.columns,
                            isHovered: hoveredRow == row.id,
                            editingCell: editingCell,
                            onCellChange: { columnId, value in updateCell(row.id, columnId, value) },
                            onCellTap: { columnId in editingCell = (row.id, columnId) },
                            onDeleteRow: { deleteRow(row.id) },
                            onDuplicateRow: { duplicateRow(row.id) }
                        )
                        .background(hoveredRow == row.id ? Color.accentColor.opacity(0.04) : Color.clear)
                        .onHover { isHovered in
                            hoveredRow = isHovered ? row.id : nil
                        }
                        .onDrag {
                            draggedRow = row.id
                            return NSItemProvider(object: row.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TableRowDropDelegate(
                            targetRow: row.id,
                            draggedRow: $draggedRow,
                            tableData: $tableData,
                            onComplete: persistTableData
                        ))
                        
                        Divider()
                    }
                    
                    // Add row button
                    Button(action: addRow) {
                        HStack {
                            Image(systemName: "plus")
                            Text("New")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear { loadTableData() }
        .onTapGesture {
            editingCell = nil
            showColumnMenu = nil
        }
    }
    
    // MARK: - Data Operations
    
    private func addRow() {
        var newCells: [String: String] = [:]
        for column in tableData.columns {
            newCells[column.id.uuidString] = ""
        }
        tableData.rows.append(TableRow(cells: newCells))
        persistTableData()
    }
    
    private func addColumn() {
        let newColumn = TableColumn(name: "Column \(tableData.columns.count + 1)", type: .text)
        tableData.columns.append(newColumn)
        // Add empty cell for new column in all rows
        for i in tableData.rows.indices {
            tableData.rows[i].cells[newColumn.id.uuidString] = ""
        }
        persistTableData()
    }
    
    private func deleteRow(_ id: UUID) {
        tableData.rows.removeAll { $0.id == id }
        persistTableData()
    }
    
    private func duplicateRow(_ id: UUID) {
        guard let row = tableData.rows.first(where: { $0.id == id }) else { return }
        let newRow = TableRow(cells: row.cells)
        if let index = tableData.rows.firstIndex(where: { $0.id == id }) {
            tableData.rows.insert(newRow, at: index + 1)
        }
        persistTableData()
    }
    
    private func deleteColumn(_ id: UUID) {
        guard tableData.columns.count > 1 else { return }
        tableData.columns.removeAll { $0.id == id }
        // Remove cell data for deleted column
        for i in tableData.rows.indices {
            tableData.rows[i].cells.removeValue(forKey: id.uuidString)
        }
        persistTableData()
    }
    
    private func renameColumn(_ id: UUID, _ newName: String) {
        if let index = tableData.columns.firstIndex(where: { $0.id == id }) {
            tableData.columns[index].name = newName
            persistTableData()
        }
    }
    
    private func changeColumnType(_ id: UUID, _ newType: TableColumnType) {
        if let index = tableData.columns.firstIndex(where: { $0.id == id }) {
            tableData.columns[index].type = newType
            persistTableData()
        }
    }
    
    private func sortByColumn(_ id: UUID) {
        if tableData.sortColumnId == id {
            tableData.sortAscending.toggle()
        } else {
            tableData.sortColumnId = id
            tableData.sortAscending = true
        }
        
        tableData.rows.sort { row1, row2 in
            let val1 = row1.cells[id.uuidString] ?? ""
            let val2 = row2.cells[id.uuidString] ?? ""
            return tableData.sortAscending ? val1 < val2 : val1 > val2
        }
        persistTableData()
    }
    
    private func updateCell(_ rowId: UUID, _ columnId: UUID, _ value: String) {
        if let rowIndex = tableData.rows.firstIndex(where: { $0.id == rowId }) {
            tableData.rows[rowIndex].cells[columnId.uuidString] = value
            persistTableData()
        }
    }
    
    private func loadTableData() {
        // Try to load enhanced format first
        if let raw = block.metadata["enhancedTableData"],
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(EnhancedTableData.self, from: data) {
            tableData = decoded
            return
        }
        
        // Try legacy format
        if let raw = block.metadata["tableData"],
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(TableData.self, from: data) {
            tableData = decoded.toEnhanced()
            persistTableData()
            return
        }
        
        tableData = .defaultTable
        persistTableData()
    }
    
    private func persistTableData() {
        if let data = try? JSONEncoder().encode(tableData),
           let raw = String(data: data, encoding: .utf8) {
            block.metadata["enhancedTableData"] = raw
            block.updatedAt = Date()
        }
    }
}

// MARK: - Table Column Header

struct TableColumnHeader: View {
    let column: TableColumn
    let isHovered: Bool
    let showMenu: Bool
    let onSort: () -> Void
    let onRename: (String) -> Void
    let onChangeType: (TableColumnType) -> Void
    let onDelete: () -> Void
    let onMenuToggle: () -> Void
    
    @State private var editingName = false
    @State private var tempName = ""
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: column.type.icon)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if editingName {
                TextField("", text: $tempName, onCommit: {
                    onRename(tempName)
                    editingName = false
                })
                .textFieldStyle(.plain)
                .font(.caption.bold())
            } else {
                Text(column.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        tempName = column.name
                        editingName = true
                    }
            }
            
            Spacer()
            
            if isHovered || showMenu {
                Button(action: onMenuToggle) {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: .constant(showMenu), arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Column type selector
                        ForEach(TableColumnType.allCases, id: \.self) { type in
                            Button(action: { onChangeType(type) }) {
                                HStack {
                                    Image(systemName: type.icon)
                                        .frame(width: 20)
                                    Text(type.displayName)
                                    Spacer()
                                    if column.type == type {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Button(action: onSort) {
                            HStack {
                                Image(systemName: "arrow.up.arrow.down")
                                    .frame(width: 20)
                                Text("Sort")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        
                        Button(role: .destructive, action: onDelete) {
                            HStack {
                                Image(systemName: "trash")
                                    .frame(width: 20)
                                Text("Delete")
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .padding(.vertical, 8)
                    .frame(width: 180)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .contentShape(Rectangle())
    }
}

// MARK: - Table Block Row View

struct TableBlockRowView: View {
    let row: TableRow
    let columns: [TableColumn]
    let isHovered: Bool
    let editingCell: (row: UUID, column: UUID)?
    let onCellChange: (UUID, String) -> Void
    let onCellTap: (UUID) -> Void
    let onDeleteRow: () -> Void
    let onDuplicateRow: () -> Void
    
    @State private var showRowMenu = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Row handle
            Group {
                if isHovered || showRowMenu {
                    Menu {
                        Button("Duplicate") { onDuplicateRow() }
                        Divider()
                        Button("Delete", role: .destructive) { onDeleteRow() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    Color.clear
                }
            }
            .frame(width: 28)
            
            // Cells
            ForEach(columns) { column in
                let isEditing = editingCell?.row == row.id && editingCell?.column == column.id
                let value = row.cells[column.id.uuidString] ?? ""
                
                TableBlockCellView(
                    value: value,
                    column: column,
                    isEditing: isEditing,
                    onChange: { onCellChange(column.id, $0) },
                    onTap: { onCellTap(column.id) }
                )
                .frame(width: column.width)
                
                Divider()
            }
        }
        .frame(height: 36)
    }
}

// MARK: - Table Block Cell View

struct TableBlockCellView: View {
    let value: String
    let column: TableColumn
    let isEditing: Bool
    let onChange: (String) -> Void
    let onTap: () -> Void
    
    @State private var tempValue = ""
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    
    var body: some View {
        Group {
            switch column.type {
            case .text, .number, .url:
                if isEditing {
                    TextField("", text: $tempValue, onCommit: {
                        onChange(tempValue)
                    })
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .onAppear { tempValue = value }
                } else {
                    Text(value.isEmpty ? " " : value)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { onTap() }
                }
                
            case .checkbox:
                Toggle("", isOn: Binding(
                    get: { value == "true" },
                    set: { onChange($0 ? "true" : "false") }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                
            case .date:
                HStack {
                    Text(value.isEmpty ? "No date" : value)
                        .foregroundColor(value.isEmpty ? .secondary : .primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .onTapGesture { showDatePicker = true }
                .popover(isPresented: $showDatePicker) {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .onChange(of: selectedDate) { _, newDate in
                            let formatter = DateFormatter()
                            formatter.dateStyle = .medium
                            onChange(formatter.string(from: newDate))
                            showDatePicker = false
                        }
                }
                
            case .select:
                Menu {
                    ForEach(column.options, id: \.self) { option in
                        Button(option) {
                            onChange(option)
                        }
                    }
                    if !column.options.isEmpty {
                        Divider()
                    }
                    Button("Clear") {
                        onChange("")
                    }
                } label: {
                    HStack {
                        if value.isEmpty {
                            Text("Select...")
                                .foregroundColor(.secondary)
                        } else {
                            Text(value)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(selectColor(for: value))
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private func selectColor(for value: String) -> Color {
        let colors: [Color] = [.blue.opacity(0.2), .green.opacity(0.2), .orange.opacity(0.2), .purple.opacity(0.2), .pink.opacity(0.2)]
        let index = abs(value.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Table Row Drop Delegate

struct TableRowDropDelegate: DropDelegate {
    let targetRow: UUID
    @Binding var draggedRow: UUID?
    @Binding var tableData: EnhancedTableData
    let onComplete: () -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        draggedRow = nil
        onComplete()
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedRow = draggedRow,
              draggedRow != targetRow,
              let fromIndex = tableData.rows.firstIndex(where: { $0.id == draggedRow }),
              let toIndex = tableData.rows.firstIndex(where: { $0.id == targetRow }) else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            tableData.rows.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }
}

// MARK: - Cursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { isHovered in
            if isHovered {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Column List Block

struct ColumnListBlockView: View {
    @Binding var block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(block.children.indices, id: \.self) { index in
                    ColumnBlockView(column: columnBinding(index))
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 12) {
                Button(action: addColumn) {
                    Label("Add column", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.borderless)

                if block.children.count > 1 {
                    Button(role: .destructive, action: removeLastColumn) {
                        Label("Remove column", systemImage: "minus.rectangle")
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear { ensureColumns() }
    }

    private func columnBinding(_ index: Int) -> Binding<Block> {
        Binding(
            get: { block.children[index] },
            set: { newValue in
                guard block.children.indices.contains(index) else { return }
                block.children[index] = newValue
                block.updatedAt = Date()
            }
        )
    }

    private func ensureColumns() {
        if block.children.isEmpty {
            block.children = [Block(type: .column, children: []), Block(type: .column, children: [])]
        }
    }

    private func addColumn() {
        block.children.append(Block(type: .column, children: []))
        block.updatedAt = Date()
    }

    private func removeLastColumn() {
        guard block.children.count > 1 else { return }
        _ = block.children.popLast()
        block.updatedAt = Date()
    }
}

// MARK: - Column Block

struct ColumnBlockView: View {
    @Binding var column: Block
    @State private var draggedChildID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(column.children.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 6) {
                    Button(action: { deleteItem(at: index) }) {
                        Image(systemName: "minus.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(column.children.count > 1 ? 1 : 0)

                    InlineBlockContentView(block: $column.children[index], index: index)

                    Spacer(minLength: 0)

                    Menu {
                        Button("Move Up") { moveItem(from: index, direction: -1) }
                        Button("Move Down") { moveItem(from: index, direction: 1) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.borderlessButton)
                }
                .onDrag {
                    let id = column.children[index].id
                    draggedChildID = id
                    return NSItemProvider(object: id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: BlockReorderDropDelegate(
                    blocks: $column.children,
                    draggedID: $draggedChildID,
                    targetID: column.children[index].id,
                    onReorder: { column.updatedAt = Date() }
                ))
                .padding(.vertical, 2)
            }

            Button(action: addItem) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption2)
                    Text("Add block")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .opacity(0.8)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
        .onAppear { ensureType() }
    }

    private func ensureType() {
        if column.type != .column {
            column.type = .column
        }
    }

    private func addItem() {
        column.children.append(Block(type: .paragraph, content: ""))
        column.updatedAt = Date()
    }

    private func deleteItem(at index: Int) {
        guard column.children.indices.contains(index) else { return }
        column.children.remove(at: index)
        column.updatedAt = Date()
    }

    private func moveItem(from index: Int, direction: Int) {
        let newIndex = index + direction
        guard column.children.indices.contains(index), column.children.indices.contains(newIndex) else { return }
        column.children.swapAt(index, newIndex)
        column.updatedAt = Date()
    }
}

// MARK: - Synced Block

struct SyncedBlockView: View {
    @Binding var block: Block
    @State private var showingGroupId = false

    private var isSource: Bool {
        block.isSyncedSource || !block.isSynced
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.accentColor)
                Text("Synced Block")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()

                if let group = block.syncedGroupID, showingGroupId {
                    Text(group)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Menu {
                    Button("Create group") {
                        block.syncedGroupID = UUID().uuidString
                        block.isSyncedSource = true
                    }
                    Button("Make source") {
                        if block.syncedGroupID == nil {
                            block.syncedGroupID = UUID().uuidString
                        }
                        block.isSyncedSource = true
                    }
                    Button("Make copy") {
                        if block.syncedGroupID == nil {
                            block.syncedGroupID = UUID().uuidString
                        }
                        block.isSyncedSource = false
                    }
                    Divider()
                    Button("Toggle group id") {
                        showingGroupId.toggle()
                    }
                    Button(role: .destructive, action: {
                        block.syncedGroupID = nil
                        block.isSyncedSource = false
                    }) {
                        Text("Unlink")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
            }

            if isSource {
                CommitTextView(
                    text: $block.content,
                    onCommit: { block.updatedAt = Date() },
                    onCancel: { }
                )
                .frame(minHeight: 60)

                ToggleChildrenView(parent: $block)
            } else {
                Text(block.content.isEmpty ? "Synced content" : block.content)
                    .font(.body)
                    .foregroundColor(.primary)
                if !block.children.isEmpty {
                    Text("\(block.children.count) synced blocks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Helpers

struct BlockURLInput: View {
    @Binding var url: String?
    var placeholder: String

    private var binding: Binding<String> {
        Binding(
            get: { url ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                url = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    var body: some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.roundedBorder)
    }
}

@ViewBuilder
func placeholderCard(icon: String, title: String, subtitle: String) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .foregroundColor(.secondary)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(NSColor.textBackgroundColor))
    .cornerRadius(8)
}

struct AudioPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if let asset = nsView.player?.currentItem?.asset as? AVURLAsset, asset.url == url {
            return
        }
        nsView.player = AVPlayer(url: url)
    }
}

// MARK: - Enhanced Table Data Model

enum TableColumnType: String, Codable, CaseIterable {
    case text = "text"
    case number = "number"
    case checkbox = "checkbox"
    case date = "date"
    case select = "select"
    case url = "url"
    
    var icon: String {
        switch self {
        case .text: return "textformat"
        case .number: return "number"
        case .checkbox: return "checkmark.square"
        case .date: return "calendar"
        case .select: return "tag"
        case .url: return "link"
        }
    }
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .number: return "Number"
        case .checkbox: return "Checkbox"
        case .date: return "Date"
        case .select: return "Select"
        case .url: return "URL"
        }
    }
}

struct TableColumn: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var type: TableColumnType
    var width: CGFloat
    var options: [String] // For select type
    
    init(id: UUID = UUID(), name: String, type: TableColumnType = .text, width: CGFloat = 150, options: [String] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.width = width
        self.options = options
    }
}

struct TableRow: Codable, Equatable, Identifiable {
    var id: UUID
    var cells: [String: String] // Column ID -> Value
    
    init(id: UUID = UUID(), cells: [String: String] = [:]) {
        self.id = id
        self.cells = cells
    }
}

struct EnhancedTableData: Codable, Equatable {
    var columns: [TableColumn]
    var rows: [TableRow]
    var showHeader: Bool
    var sortColumnId: UUID?
    var sortAscending: Bool
    
    init(columns: [TableColumn] = [], rows: [TableRow] = [], showHeader: Bool = true, sortColumnId: UUID? = nil, sortAscending: Bool = true) {
        self.columns = columns
        self.rows = rows
        self.showHeader = showHeader
        self.sortColumnId = sortColumnId
        self.sortAscending = sortAscending
    }
    
    static let defaultTable: EnhancedTableData = {
        let col1 = TableColumn(name: "Name", type: .text)
        let col2 = TableColumn(name: "Status", type: .select, options: ["To Do", "In Progress", "Done"])
        let col3 = TableColumn(name: "Date", type: .date)
        return EnhancedTableData(
            columns: [col1, col2, col3],
            rows: [
                TableRow(cells: [col1.id.uuidString: "", col2.id.uuidString: "", col3.id.uuidString: ""]),
                TableRow(cells: [col1.id.uuidString: "", col2.id.uuidString: "", col3.id.uuidString: ""])
            ]
        )
    }()
}

// Legacy support
struct TableData: Codable, Equatable {
    var columns: [String]
    var rows: [[String]]

    static let defaultTable = TableData(
        columns: ["Column 1", "Column 2", "Column 3"],
        rows: [
            ["", "", ""],
            ["", "", ""]
        ]
    )
    
    // Convert to enhanced format
    func toEnhanced() -> EnhancedTableData {
        let newColumns = columns.map { TableColumn(name: $0, type: .text) }
        let newRows = rows.map { row in
            var cells: [String: String] = [:]
            for (index, value) in row.enumerated() {
                if index < newColumns.count {
                    cells[newColumns[index].id.uuidString] = value
                }
            }
            return TableRow(cells: cells)
        }
        return EnhancedTableData(columns: newColumns, rows: newRows)
    }
}

// MARK: - Slash Command Menu

enum SlashCommandActivation {
    case anywhere
    case leadingOnly
}

// MARK: - Recent Commands Storage

class RecentCommandsManager: ObservableObject {
    static let shared = RecentCommandsManager()
    
    @Published var recentCommands: [BlockType] = []
    private let maxRecent = 5
    private let storageKey = "recentBlockCommands"
    
    private init() {
        loadRecents()
    }
    
    func recordUsage(_ type: BlockType) {
        // Remove if already exists
        recentCommands.removeAll { $0 == type }
        // Insert at beginning
        recentCommands.insert(type, at: 0)
        // Trim to max
        if recentCommands.count > maxRecent {
            recentCommands = Array(recentCommands.prefix(maxRecent))
        }
        saveRecents()
    }
    
    private func loadRecents() {
        if let data = UserDefaults.standard.array(forKey: storageKey) as? [String] {
            recentCommands = data.compactMap { BlockType(rawValue: $0) }
        }
    }
    
    private func saveRecents() {
        let data = recentCommands.map { $0.rawValue }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

struct SlashCommandMenuHost<Content: View>: View {
    @Binding var block: Block
    let activation: SlashCommandActivation
    let content: Content
    @State private var isShowing = false
    @State private var query = ""

    init(block: Binding<Block>, activation: SlashCommandActivation = .anywhere, @ViewBuilder content: () -> Content) {
        self._block = block
        self.activation = activation
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .onChange(of: block.content) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    switch activation {
                    case .anywhere:
                        if trimmed.hasPrefix("/") {
                            query = String(trimmed.dropFirst())
                            isShowing = true
                        } else {
                            isShowing = false
                        }
                    case .leadingOnly:
                        if trimmed.hasPrefix("/") && !trimmed.contains("\n") {
                            query = String(trimmed.dropFirst())
                            isShowing = true
                        } else {
                            isShowing = false
                        }
                    }
                }

            if isShowing {
                EnhancedSlashCommandMenu(query: query) { selection in
                    apply(selection)
                }
                .padding(.top, 28)
                .zIndex(2)
            }
        }
    }

    private func apply(_ selection: SlashCommandOption) {
        RecentCommandsManager.shared.recordUsage(selection.type)
        block.type = selection.type
        block.content = ""
        block.updatedAt = Date()
        isShowing = false
    }
}

// MARK: - Enhanced Slash Command Menu

struct EnhancedSlashCommandMenu: View {
    let query: String
    let onSelect: (SlashCommandOption) -> Void
    
    @ObservedObject private var recentsManager = RecentCommandsManager.shared
    @State private var selectedIndex = 0
    @State private var hoveredType: BlockType?
    
    private var filtered: [SlashCommandCategory] {
        let normalized = query.lowercased()
        
        if normalized.isEmpty {
            // Show recents first, then all categories
            var categories: [SlashCommandCategory] = []

            // Quick actions
            categories.append(SlashCommandCategory(
                name: "Quick Actions",
                icon: "sparkles",
                options: SlashCommandOption.quickActions
            ))
            
            // Recent commands
            if !recentsManager.recentCommands.isEmpty {
                let recentOptions = recentsManager.recentCommands.compactMap { type in
                    SlashCommandOption.defaults.first { $0.type == type }
                }
                if !recentOptions.isEmpty {
                    categories.append(SlashCommandCategory(name: "Recent", icon: "clock", options: recentOptions))
                }
            }
            
            // All default categories
            categories.append(contentsOf: SlashCommandCategory.defaults)
            return categories
        }
        
        // Filter by query
        let matchingOptions = SlashCommandOption.defaults.filter { option in
            option.title.lowercased().contains(normalized) || 
            option.keywords.contains(where: { $0.contains(normalized) })
        }
        
        return [SlashCommandCategory(name: "Results", icon: "magnifyingglass", options: matchingOptions)]
    }
    
    private var allOptions: [SlashCommandOption] {
        filtered.flatMap { $0.options }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "command")
                    .foregroundColor(.secondary)
                Text("Type to filter or select")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("↑↓ navigate")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                Text("↵ select")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Categories and options
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered, id: \.name) { category in
                            // Category header
                            HStack(spacing: 6) {
                                Image(systemName: category.icon)
                                    .font(.caption)
                                Text(category.name)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                            
                            // Options
                            ForEach(category.options, id: \.type) { option in
                                let optionIndex = allOptions.firstIndex(where: { $0.type == option.type }) ?? 0
                                let isSelected = optionIndex == selectedIndex
                                let isHovered = hoveredType == option.type
                                
                                SlashCommandRow(
                                    option: option,
                                    isSelected: isSelected || isHovered,
                                    shortcut: shortcut(for: option.type)
                                )
                                .onTapGesture { onSelect(option) }
                                .onHover { hover in
                                    if hover {
                                        hoveredType = option.type
                                        selectedIndex = optionIndex
                                    }
                                }
                                .id(option.type)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
                .onChange(of: selectedIndex) { _, newValue in
                    if let type = allOptions[safe: newValue]?.type {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(type, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 300)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(allOptions.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            if let option = allOptions[safe: selectedIndex] {
                onSelect(option)
            }
            return .handled
        }
    }
    
    private func shortcut(for type: BlockType) -> String? {
        switch type {
        case .heading1: return "⌘⌥1"
        case .heading2: return "⌘⌥2"
        case .heading3: return "⌘⌥3"
        case .bulletList: return "⌘⇧8"
        case .numberedList: return "⌘⇧7"
        case .todo: return "⌘⇧9"
        case .code: return "⌘⌥C"
        case .quote: return "⌘⇧Q"
        case .divider: return "---"
        default: return nil
        }
    }
}

// MARK: - Slash Command Row

struct SlashCommandRow: View {
    let option: SlashCommandOption
    let isSelected: Bool
    let shortcut: String?
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(isSelected ? 0.2 : 0.1))
                    .frame(width: 32, height: 32)
                
                Image(systemName: option.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .medium : .regular)
                Text(option.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Shortcut
            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Slash Command Category

struct SlashCommandCategory {
    let name: String
    let icon: String
    let options: [SlashCommandOption]
    
    static let defaults: [SlashCommandCategory] = [
        SlashCommandCategory(name: "Basic", icon: "textformat", options: [
            SlashCommandOption.defaults.first { $0.type == .paragraph }!,
            SlashCommandOption.defaults.first { $0.type == .heading1 }!,
            SlashCommandOption.defaults.first { $0.type == .heading2 }!,
            SlashCommandOption.defaults.first { $0.type == .heading3 }!,
        ]),
        SlashCommandCategory(name: "Lists", icon: "list.bullet", options: [
            SlashCommandOption.defaults.first { $0.type == .bulletList }!,
            SlashCommandOption.defaults.first { $0.type == .numberedList }!,
            SlashCommandOption.defaults.first { $0.type == .todo }!,
            SlashCommandOption.defaults.first { $0.type == .toggle }!,
        ]),
        SlashCommandCategory(name: "Media", icon: "photo.on.rectangle", options: [
            SlashCommandOption.defaults.first { $0.type == .image }!,
            SlashCommandOption.defaults.first { $0.type == .video }!,
            SlashCommandOption.defaults.first { $0.type == .audio }!,
            SlashCommandOption.defaults.first { $0.type == .file }!,
        ]),
        SlashCommandCategory(name: "Advanced", icon: "square.stack.3d.up", options: [
            SlashCommandOption.defaults.first { $0.type == .code }!,
            SlashCommandOption.defaults.first { $0.type == .quote }!,
            SlashCommandOption.defaults.first { $0.type == .callout }!,
            SlashCommandOption.defaults.first { $0.type == .divider }!,
            SlashCommandOption.defaults.first { $0.type == .table }!,
            SlashCommandOption.defaults.first { $0.type == .syncedBlock }!,
        ]),
        SlashCommandCategory(name: "Layout", icon: "rectangle.split.2x1", options: [
            SlashCommandOption.defaults.first { $0.type == .columnList }!,
        ]),
        SlashCommandCategory(name: "Embeds", icon: "link.badge.plus", options: [
            SlashCommandOption.defaults.first { $0.type == .sessionEmbed }!,
            SlashCommandOption.defaults.first { $0.type == .databaseEmbed }!,
            SlashCommandOption.defaults.first { $0.type == .bookmark }!,
            SlashCommandOption.defaults.first { $0.type == .embed }!,
            SlashCommandOption.defaults.first { $0.type == .pageLink }!,
        ]),
        SlashCommandCategory(name: "Meeting", icon: "person.2", options: [
            SlashCommandOption.defaults.first { $0.type == .meetingAttendees }!,
            SlashCommandOption.defaults.first { $0.type == .meetingAgenda }!,
            SlashCommandOption.defaults.first { $0.type == .meetingNotes }!,
            SlashCommandOption.defaults.first { $0.type == .meetingDecisions }!,
            SlashCommandOption.defaults.first { $0.type == .meetingActionItems }!,
            SlashCommandOption.defaults.first { $0.type == .meetingNextSteps }!
        ])
    ]
}

// MARK: - Safe Array Access Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Legacy Slash Command Menu (for compatibility)

struct SlashCommandMenu: View {
    let query: String
    let onSelect: (SlashCommandOption) -> Void

    private var filtered: [SlashCommandOption] {
        let normalized = query.lowercased()
        if normalized.isEmpty { return SlashCommandOption.defaults }
        return SlashCommandOption.defaults.filter { option in
            option.title.lowercased().contains(normalized) || option.keywords.contains(where: { $0.contains(normalized) })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(filtered, id: \.type) { option in
                Button(action: { onSelect(option) }) {
                    HStack(spacing: 8) {
                        Image(systemName: option.icon)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.subheadline)
                            Text(option.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(maxWidth: 260)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
    }
}

struct SlashCommandOption: Hashable {
    let type: BlockType
    let title: String
    let subtitle: String
    let icon: String
    let keywords: [String]

    static let quickActions: [SlashCommandOption] = [
        SlashCommandOption(type: .paragraph, title: "Text", subtitle: "Plain text", icon: "text.alignleft", keywords: ["text", "paragraph"]),
        SlashCommandOption(type: .todo, title: "To‑do", subtitle: "Checkbox item", icon: "checkmark.square", keywords: ["todo", "task"]),
        SlashCommandOption(type: .heading2, title: "Heading", subtitle: "Section heading", icon: "textformat.size", keywords: ["heading"]),
        SlashCommandOption(type: .meetingAgenda, title: "Agenda", subtitle: "Meeting agenda", icon: "list.bullet.rectangle", keywords: ["agenda", "meeting"]),
        SlashCommandOption(type: .meetingActionItems, title: "Action Items", subtitle: "Meeting tasks", icon: "checkmark.circle", keywords: ["action", "tasks", "meeting"]),
        SlashCommandOption(type: .toggle, title: "Toggle", subtitle: "Collapsible content", icon: "chevron.right", keywords: ["toggle"])
    ]

    static let defaults: [SlashCommandOption] = [
        SlashCommandOption(type: .paragraph, title: "Text", subtitle: "Plain text", icon: "text.alignleft", keywords: ["text", "paragraph"]),
        SlashCommandOption(type: .heading1, title: "Heading 1", subtitle: "Large heading", icon: "textformat.size.larger", keywords: ["h1", "heading"]),
        SlashCommandOption(type: .heading2, title: "Heading 2", subtitle: "Medium heading", icon: "textformat.size", keywords: ["h2", "heading"]),
        SlashCommandOption(type: .heading3, title: "Heading 3", subtitle: "Small heading", icon: "textformat.size.smaller", keywords: ["h3", "heading"]),
        SlashCommandOption(type: .bulletList, title: "Bulleted List", subtitle: "Unordered list", icon: "list.bullet", keywords: ["bullet", "list"]),
        SlashCommandOption(type: .numberedList, title: "Numbered List", subtitle: "Ordered list", icon: "list.number", keywords: ["number", "list"]),
        SlashCommandOption(type: .todo, title: "To‑do", subtitle: "Checkbox item", icon: "checkmark.square", keywords: ["todo", "task"]),
        SlashCommandOption(type: .toggle, title: "Toggle", subtitle: "Collapsible content", icon: "chevron.right", keywords: ["toggle"]),
        SlashCommandOption(type: .meetingAgenda, title: "Agenda", subtitle: "Meeting agenda", icon: "list.bullet.rectangle", keywords: ["agenda", "meeting"]),
        SlashCommandOption(type: .meetingNotes, title: "Meeting Notes", subtitle: "Discussion notes", icon: "note.text", keywords: ["notes", "meeting"]),
        SlashCommandOption(type: .meetingDecisions, title: "Decisions", subtitle: "Key decisions", icon: "checkmark.seal", keywords: ["decisions", "meeting"]),
        SlashCommandOption(type: .meetingActionItems, title: "Action Items", subtitle: "Follow-up tasks", icon: "checkmark.circle", keywords: ["action", "tasks", "meeting"]),
        SlashCommandOption(type: .meetingNextSteps, title: "Next Steps", subtitle: "Follow-up steps", icon: "arrow.forward.circle", keywords: ["next", "steps", "meeting"]),
        SlashCommandOption(type: .meetingAttendees, title: "Attendees", subtitle: "Who attended", icon: "person.2", keywords: ["attendees", "participants", "meeting"]),
        SlashCommandOption(type: .quote, title: "Quote", subtitle: "Quoted text", icon: "text.quote", keywords: ["quote"]),
        SlashCommandOption(type: .callout, title: "Callout", subtitle: "Highlighted block", icon: "exclamationmark.bubble", keywords: ["callout", "info"]),
        SlashCommandOption(type: .code, title: "Code", subtitle: "Code snippet", icon: "chevron.left.forwardslash.chevron.right", keywords: ["code", "snippet"]),
        SlashCommandOption(type: .divider, title: "Divider", subtitle: "Section separator", icon: "minus", keywords: ["divider", "hr"]),
        SlashCommandOption(type: .image, title: "Image", subtitle: "Embed image", icon: "photo", keywords: ["image", "img", "photo"]),
        SlashCommandOption(type: .audio, title: "Audio", subtitle: "Embed audio", icon: "waveform", keywords: ["audio", "sound"]),
        SlashCommandOption(type: .video, title: "Video", subtitle: "Embed video", icon: "play.rectangle", keywords: ["video"]),
        SlashCommandOption(type: .file, title: "File", subtitle: "Attach file", icon: "doc", keywords: ["file", "attachment"]),
        SlashCommandOption(type: .bookmark, title: "Bookmark", subtitle: "Web preview", icon: "bookmark", keywords: ["bookmark", "link"]),
        SlashCommandOption(type: .embed, title: "Embed", subtitle: "Embed URL", icon: "link", keywords: ["embed", "url"]),
        SlashCommandOption(type: .sessionEmbed, title: "Session", subtitle: "Embed recording", icon: "waveform.circle", keywords: ["session", "recording"]),
        SlashCommandOption(type: .databaseEmbed, title: "Database", subtitle: "Embed database", icon: "rectangle.split.3x1", keywords: ["database", "db"]),
        SlashCommandOption(type: .pageLink, title: "Page Link", subtitle: "Link page", icon: "link", keywords: ["page", "link"]),
        SlashCommandOption(type: .table, title: "Table", subtitle: "Simple table", icon: "tablecells", keywords: ["table"]),
        SlashCommandOption(type: .columnList, title: "Columns", subtitle: "Multi‑column layout", icon: "rectangle.split.2x1", keywords: ["column", "columns"]),
        SlashCommandOption(type: .syncedBlock, title: "Synced Block", subtitle: "Mirror content", icon: "arrow.triangle.2.circlepath", keywords: ["synced", "sync", "mirror"])
    ]
}

// MARK: - Reorder Drop Delegate

struct BlockReorderDropDelegate: DropDelegate {
    @Binding var blocks: [Block]
    @Binding var draggedID: UUID?
    let targetID: UUID
    let onReorder: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedID,
              draggedID != targetID,
              let fromIndex = blocks.firstIndex(where: { $0.id == draggedID }),
              let toIndex = blocks.firstIndex(where: { $0.id == targetID }) else { return }

        if blocks[toIndex].id != draggedID {
            withAnimation(.easeInOut(duration: 0.15)) {
                blocks.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
            onReorder()
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Enhanced Drop Indicator View

/// Visual indicator showing where a block will be dropped
struct DropIndicatorView: View {
    let isActive: Bool
    let position: DropPosition
    
    enum DropPosition {
        case above
        case below
        case inside
    }
    
    var body: some View {
        Group {
            switch position {
            case .above, .below:
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(height: isActive ? 3 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isActive)
            case .inside:
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: isActive ? 2 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isActive)
            }
        }
    }
}

// MARK: - Draggable Block Wrapper

/// Wraps a block view with drag & drop capabilities and visual feedback
struct DraggableBlockWrapper<Content: View>: View {
    let blockID: UUID
    @Binding var draggedID: UUID?
    @Binding var dropTargetID: UUID?
    @Binding var dropPosition: DropIndicatorView.DropPosition
    let canAcceptChildren: Bool
    let content: () -> Content
    
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top drop indicator
            DropIndicatorView(
                isActive: dropTargetID == blockID && dropPosition == .above,
                position: .above
            )
            .padding(.horizontal, 4)
            
            // Block content
            content()
                .opacity(draggedID == blockID ? 0.4 : 1.0)
                .background(
                    Group {
                        if canAcceptChildren {
                            DropIndicatorView(
                                isActive: dropTargetID == blockID && dropPosition == .inside,
                                position: .inside
                            )
                        }
                    }
                )
                .scaleEffect(isDragging ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isDragging)
            
            // Bottom drop indicator  
            DropIndicatorView(
                isActive: dropTargetID == blockID && dropPosition == .below,
                position: .below
            )
            .padding(.horizontal, 4)
        }
        .onDrag {
            isDragging = true
            draggedID = blockID
            return NSItemProvider(object: blockID.uuidString as NSString)
        }
    }
}

// MARK: - Advanced Drop Delegate with Position Detection

struct AdvancedBlockDropDelegate: DropDelegate {
    @Binding var blocks: [Block]
    @Binding var draggedID: UUID?
    @Binding var dropTargetID: UUID?
    @Binding var dropPosition: DropIndicatorView.DropPosition
    let targetID: UUID
    let targetIndex: Int
    let canAcceptChildren: Bool
    let onReorder: () -> Void
    let onDropInside: ((UUID, UUID) -> Void)?
    
    func dropEntered(info: DropInfo) {
        dropTargetID = targetID
        updateDropPosition(info: info)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropPosition(info: info)
        return DropProposal(operation: .move)
    }
    
    func dropExited(info: DropInfo) {
        if dropTargetID == targetID {
            dropTargetID = nil
        }
    }
    
    private func updateDropPosition(info: DropInfo) {
        // Determine if dropping above, below, or inside based on cursor position
        let locationY = info.location.y
        
        if canAcceptChildren && locationY > 10 && locationY < 40 {
            // Middle area - drop inside
            dropPosition = .inside
        } else if locationY < 20 {
            dropPosition = .above
        } else {
            dropPosition = .below
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggedID,
              draggedID != targetID else {
            cleanUp()
            return false
        }
        
        // Handle drop inside (for toggles/columns)
        if dropPosition == .inside && canAcceptChildren {
            onDropInside?(draggedID, targetID)
            cleanUp()
            return true
        }
        
        // Handle reorder
        guard let fromIndex = blocks.firstIndex(where: { $0.id == draggedID }) else {
            cleanUp()
            return false
        }
        
        let toIndex: Int
        if dropPosition == .above {
            toIndex = targetIndex
        } else {
            toIndex = targetIndex + 1
        }
        
        if fromIndex != toIndex && fromIndex != toIndex - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                let adjustedTo = toIndex > fromIndex ? toIndex : toIndex
                blocks.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: adjustedTo)
            }
            onReorder()
        }
        
        cleanUp()
        return true
    }
    
    private func cleanUp() {
        withAnimation(.easeInOut(duration: 0.1)) {
            draggedID = nil
            dropTargetID = nil
        }
    }
}

// MARK: - Cross-Container Drop Support

/// Manages drag & drop state across multiple block containers
class BlockDragManager: ObservableObject {
    static let shared = BlockDragManager()
    
    @Published var draggedBlockID: UUID?
    @Published var draggedBlock: Block?
    @Published var sourceContainerID: UUID?
    @Published var dropTargetContainerID: UUID?
    @Published var dropTargetBlockID: UUID?
    @Published var dropPosition: DropIndicatorView.DropPosition = .below
    
    func startDrag(block: Block, containerID: UUID) {
        draggedBlockID = block.id
        draggedBlock = block
        sourceContainerID = containerID
    }
    
    func endDrag() {
        draggedBlockID = nil
        draggedBlock = nil
        sourceContainerID = nil
        dropTargetContainerID = nil
        dropTargetBlockID = nil
        dropPosition = .below
    }
    
    func updateDropTarget(containerID: UUID, blockID: UUID?, position: DropIndicatorView.DropPosition) {
        dropTargetContainerID = containerID
        dropTargetBlockID = blockID
        dropPosition = position
    }
}

// MARK: - Session Embed Block

struct SessionEmbedBlockView: View {
    @Binding var block: Block
    @State private var session: RecordingSession?
    @State private var showingPicker = false
    @State private var searchText = ""
    @State private var availableSessions: [RecordingSession] = []
    
    var body: some View {
        Group {
            if let sessionId = block.sessionID {
                if let session = session {
                    sessionPreview(session)
                } else {
                    loadingView
                        .onAppear { loadSession(id: sessionId) }
                }
            } else {
                selectSessionButton
            }
        }
        .sheet(isPresented: $showingPicker) {
            SessionPickerView(
                sessions: availableSessions,
                onSelect: { selected in
                    block.sessionID = selected.id
                    block.content = selected.title ?? "Untitled"
                    session = selected
                    showingPicker = false
                }
            )
        }
        .onAppear { refreshSessions() }
    }
    
    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading session...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
    
    private var selectSessionButton: some View {
        Button(action: { showingPicker = true }) {
            HStack {
                Image(systemName: "waveform.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text("Embed Session")
                        .fontWeight(.medium)
                    Text("Click to select a recording session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func sessionPreview(_ session: RecordingSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundColor(.accentColor)
                
                Text(session.title ?? "Untitled Session")
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !session.fullTranscript.isEmpty {
                Text(session.fullTranscript)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            // Duration
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                Text(formatDuration(session.duration))
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func loadSession(id: UUID) {
        Task {
            session = StorageService.shared.loadSessions().first { $0.id == id }
        }
    }

    private func refreshSessions() {
        availableSessions = StorageService.shared.loadSessions().sorted { $0.startDate > $1.startDate }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Picker Views

struct DatabasePickerView: View {
    let databases: [Database]
    let onSelect: (Database) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [Database] {
        if searchText.isEmpty { return databases }
        let query = searchText.lowercased()
        return databases.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Select Database")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search databases...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

            List(filtered) { database in
                Button(action: { onSelect(database) }) {
                    HStack {
                        Image(systemName: database.icon)
                        Text(database.name)
                        Spacer()
                        Text(database.defaultView.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 420, height: 420)
    }
}

struct PagePickerView: View {
    let pages: [WorkspaceItem]
    let onSelect: (WorkspaceItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [WorkspaceItem] {
        if searchText.isEmpty { return pages }
        let query = searchText.lowercased()
        return pages.filter { $0.displayTitle.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Select Page")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search pages...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

            List(filtered) { page in
                Button(action: { onSelect(page) }) {
                    HStack {
                        Text(page.icon)
                        Text(page.displayTitle)
                        Spacer()
                        Text(page.updatedAt.relativeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 420, height: 420)
    }
}

struct SessionPickerView: View {
    let sessions: [RecordingSession]
    let onSelect: (RecordingSession) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [RecordingSession] {
        if searchText.isEmpty { return sessions }
        let query = searchText.lowercased()
        return sessions.filter {
            ($0.title ?? "").lowercased().contains(query) || $0.fullTranscript.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Select Session")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sessions...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

            List(filtered, id: \.id) { session in
                Button(action: { onSelect(session) }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((session.title ?? "").isEmpty ? "Untitled session" : session.title ?? "")
                            .fontWeight(.medium)
                        Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 480, height: 460)
    }
}
