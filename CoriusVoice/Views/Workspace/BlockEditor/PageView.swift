import SwiftUI

// MARK: - Page View

/// Full page view with editor and navigation
struct PageView: View {
    let itemID: UUID
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var item: WorkspaceItem?
    @State private var isLoading = true
    @State private var selectedBacklinkItem: WorkspaceItem?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let item = Binding($item) {
                VStack(spacing: 0) {
                    BlockEditorView(item: item)
                    CommentsSection(item: item)
                    VersionsSection(pageID: itemID)
                    BacklinksSection(
                        currentItemID: itemID,
                        currentItem: item.wrappedValue,
                        allItems: storage.items,
                        onSelectPage: { selectedBacklinkItem = $0 }
                    )
                }
            } else {
                notFoundView
            }
        }
        .onAppear { loadItem() }
        .sheet(item: $selectedBacklinkItem) { item in
            PageView(itemID: item.id)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarItems
            }
        }
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("Page not found")
                .font(.headline)
            
            Text("This page may have been deleted or moved")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Go Back") {
                dismiss()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var toolbarItems: some View {
        // Favorite
        Button(action: toggleFavorite) {
            Image(systemName: item?.isFavorite == true ? "star.fill" : "star")
        }
        .help("Add to favorites")
        
        // Share
        Menu {
            Button(action: { exportAsMarkdown() }) {
                Label("Export as Markdown", systemImage: "doc.plaintext")
            }
            Button(action: { copyLink() }) {
                Label("Copy Link", systemImage: "link")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .help("Share")

        // Auto-save indicator
        if let lastAutoSave = lastAutoSaveDate {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("Auto‑saved \(lastAutoSave.relativeString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        // More
        Menu {
            Button(action: { duplicatePage(clearProperties: false) }) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button(action: { duplicatePage(clearProperties: true) }) {
                Label("Duplicate (Clear Properties)", systemImage: "sparkles")
            }

            Button(action: { createVersion() }) {
                Label("Save Version", systemImage: "clock.arrow.circlepath")
            }
            
            Divider()
            
            Button(action: { archivePage() }) {
                Label("Move to Trash", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("More options")
    }
    
    // MARK: - Actions
    
    private func loadItem() {
        item = storage.items.first { $0.id == itemID }
        isLoading = false
    }
    
    private func toggleFavorite() {
        item?.isFavorite.toggle()
        if let item = item {
            storage.updateItem(item)
        }
    }
    
    private func exportAsMarkdown() {
        guard let item = item else { return }
        
        var markdown = "# \(item.title)\n\n"
        
        for block in item.blocks {
            markdown += block.toMarkdown() + "\n\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
    
    private func copyLink() {
        // Copy internal link
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("corius://page/\(itemID.uuidString)", forType: .string)
    }
    
    private func duplicatePage(clearProperties: Bool) {
        guard let item = item else { return }
        let newItem = item.duplicated(clearProperties: clearProperties)
        storage.createItem(newItem)
    }

    private func createVersion() {
        guard let item = item else { return }
        storage.createVersion(for: item)
    }
    
    private func archivePage() {
        item?.isArchived = true
        if let item = item {
            storage.updateItem(item)
        }
        dismiss()
    }

    private var lastAutoSaveDate: Date? {
        guard let item = item else { return nil }
        let versions = storage.versions(for: item.id)
        return versions.first(where: { $0.note == "Auto-save" })?.createdAt
    }
}

// MARK: - Versions

struct VersionsSection: View {
    let pageID: UUID
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var showingSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Text("Versions")
                    .font(.headline)
                Spacer()
                Button("View all") { showingSheet = true }
                    .buttonStyle(.borderless)
            }

            let versions = storage.versions(for: pageID)
            if versions.isEmpty {
                Text("No versions yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(versions.prefix(3)) { version in
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                        Spacer()
                        if let note = version.note, !note.isEmpty {
                            Text(note)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .sheet(isPresented: $showingSheet) {
            VersionsListView(pageID: pageID)
        }
    }
}

struct VersionsListView: View {
    let pageID: UUID
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Versions")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
            }

            List(storage.versions(for: pageID)) { version in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let note = version.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("Blocks: \(version.blocks.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Restore") {
                        storage.restoreVersion(version)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .frame(width: 420, height: 420)
    }
}

// MARK: - Comments

struct CommentsSection: View {
    @Binding var item: WorkspaceItem
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @StateObject private var speakerLibrary = SpeakerLibrary.shared
    @State private var newComment = ""

    private var recentSpeakers: [KnownSpeaker] {
        speakerLibrary.suggestedSpeakers(limit: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("Comments")
                .font(.headline)

            if item.comments.isEmpty {
                Text("No comments yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(item.comments.sorted(by: { $0.createdAt > $1.createdAt })) { comment in
                    commentRow(comment)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                CommitTextView(
                    text: $newComment,
                    onCommit: { addComment() },
                    onCancel: { newComment = "" }
                )
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)

                HStack(spacing: 8) {
                    Button("@today") { insertDateMention(.today) }
                        .buttonStyle(.borderless)
                    Button("@tomorrow") { insertDateMention(.tomorrow) }
                        .buttonStyle(.borderless)
                    Button("@date…") { insertDateMention(.custom) }
                        .buttonStyle(.borderless)

                    Spacer()

                    Button("Add Comment") {
                        addComment()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !recentSpeakers.isEmpty {
                    HStack(spacing: 6) {
                        Text("@person:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(recentSpeakers) { speaker in
                            Button("@\(speaker.name)") {
                                insertPersonMention(speaker)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
    }

    private func commentRow(_ comment: PageComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.displayAuthor)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text(comment.content)
                .font(.body)
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func addComment() {
        let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let comment = PageComment(content: trimmed)
        item.comments.append(comment)
        item.updatedAt = Date()
        storage.updateItem(item)
        newComment = ""
    }

    private func insertPersonMention(_ speaker: KnownSpeaker) {
        newComment = appendToken("@\(speaker.name)")
        SpeakerLibrary.shared.markSpeakerUsed(speaker.id)
    }

    private func insertDateMention(_ type: DateMentionType) {
        let token: String
        switch type {
        case .today:
            token = "@today"
        case .tomorrow:
            token = "@tomorrow"
        case .custom:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            token = "@date(\(formatter.string(from: Date())))"
        }
        newComment = appendToken(token)
    }

    private func appendToken(_ token: String) -> String {
        let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return token + " " }
        return newComment + (newComment.hasSuffix(" ") ? "" : " ") + token + " "
    }
}

enum DateMentionType {
    case today
    case tomorrow
    case custom
}

// MARK: - Backlinks & Related Pages

struct BacklinksSection: View {
    let currentItemID: UUID
    let currentItem: WorkspaceItem
    let allItems: [WorkspaceItem]
    var onSelectPage: (WorkspaceItem) -> Void = { _ in }

    @State private var showAllBacklinks = false
    @State private var showAllRelated = false

    private var backlinks: [WorkspaceItem] {
        allItems.filter { item in
            guard item.id != currentItemID, item.itemType == .page else { return false }
            return item.blocks.contains(where: { block in
                if let pageID = block.metadata["pageID"], pageID == currentItemID.uuidString {
                    return true
                }
                if block.content.contains("corius://page/\(currentItemID.uuidString)") {
                    return true
                }
                return false
            })
        }
    }

    private var outgoingLinks: [UUID] {
        currentItem.blocks.compactMap { block in
            if let pageID = block.metadata["pageID"], let id = UUID(uuidString: pageID) {
                return id
            }
            if let range = block.content.range(of: "corius://page/") {
                let suffix = block.content[range.upperBound...]
                let idString = suffix.split { $0 == ")" || $0 == " " || $0 == "\n" }.first
                if let idString, let id = UUID(uuidString: String(idString)) {
                    return id
                }
            }
            return nil
        }
    }

    private var relatedPages: [WorkspaceItem] {
        let outgoing = allItems.filter { outgoingLinks.contains($0.id) }
        let combined = Array(Set(outgoing + backlinks))
        return combined.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        if !backlinks.isEmpty || !relatedPages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                if !backlinks.isEmpty {
                    section(title: "Backlinks", items: backlinks, showAll: $showAllBacklinks)
                }
                if !relatedPages.isEmpty {
                    section(title: "Related Pages", items: relatedPages, showAll: $showAllRelated)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
    }

    private func section(title: String, items: [WorkspaceItem], showAll: Binding<Bool>) -> some View {
        let visibleItems = showAll.wrappedValue ? items : Array(items.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if items.count > 6 {
                    Button(showAll.wrappedValue ? "Show less" : "Show all") {
                        showAll.wrappedValue.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            ForEach(visibleItems) { page in
                Button(action: { onSelectPage(page) }) {
                    HStack(spacing: 8) {
                        WorkspaceIconView(name: page.icon)
                        Text(page.displayTitle)
                            .lineLimit(1)
                        Spacer()
                        Text(page.updatedAt.relativeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Block Markdown Export

extension Block {
    func toMarkdown() -> String {
        switch type {
        case .paragraph:
            return content
            
        case .heading1:
            return "# \(content)"
            
        case .heading2:
            return "## \(content)"
            
        case .heading3:
            return "### \(content)"
            
        case .bulletList:
            return "- \(content)"
            
        case .numberedList:
            return "1. \(content)"
            
        case .todo:
            let checkbox = isChecked ? "[x]" : "[ ]"
            return "- \(checkbox) \(content)"
            
        case .quote:
            return "> \(content)"
            
        case .code:
            return "```\n\(content)\n```"
            
        case .divider:
            return "---"
            
        case .callout:
            return "> \(icon ?? "💡") \(content)"
            
        case .image:
            if let url = url {
                return "![\(content)](\(url))"
            }
            return ""

        case .bookmark:
            if let url = url { return "[\(content.isEmpty ? url : content)](\(url))" }
            return content

        case .file:
            if let url = url { return "[\(content.isEmpty ? "File" : content)](\(url))" }
            return content

        case .audio:
            if let url = url { return "[Audio](\(url))" }
            return content

        case .video:
            if let url = url { return "[Video](\(url))" }
            return content

        case .embed:
            if let url = url { return "[Embed](\(url))" }
            return content

        case .pageLink:
            if let pageID = metadata["pageID"] {
                return "[[\(content.isEmpty ? pageID : content)]]"
            }
            return content

        case .table:
            if let raw = metadata["tableData"],
               let data = raw.data(using: .utf8),
               let table = try? JSONDecoder().decode(MarkdownTableData.self, from: data) {
                return table.toMarkdown()
            }
            return content
            
        default:
            return content
        }
    }
}

private struct MarkdownTableData: Codable {
    let columns: [String]
    let rows: [[String]]

    func toMarkdown() -> String {
        guard !columns.isEmpty else { return "" }
        let header = "| " + columns.joined(separator: " | ") + " |"
        let separator = "| " + Array(repeating: "---", count: columns.count).joined(separator: " | ") + " |"
        let body = rows.map { row in
            let cells = row + Array(repeating: "", count: max(0, columns.count - row.count))
            return "| " + cells.prefix(columns.count).joined(separator: " | ") + " |"
        }
        return ([header, separator] + body).joined(separator: "\n")
    }
}

// MARK: - Quick Page Creator

struct QuickPageCreator: View {
    @Binding var isPresented: Bool
    let parentID: UUID?
    let onCreated: (WorkspaceItem) -> Void
    
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var title = ""
    @State private var icon = "doc.text"
    @State private var selectedTemplate: PageTemplate = .blank
    @FocusState private var isTitleFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("New Page")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
            }
            
            Divider()
            
            // Icon and title
            HStack(spacing: 12) {
                IconPicker(selectedIcon: $icon)
                
                TextField("Untitled", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($isTitleFocused)
            }
            
            // Templates
            VStack(alignment: .leading, spacing: 8) {
                Text("Template")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(PageTemplate.allCases, id: \.self) { template in
                        TemplateButton(
                            template: template,
                            isSelected: selectedTemplate == template,
                            action: { selectedTemplate = template }
                        )
                    }
                }
            }
            
            Spacer()
            
            // Create button
            Button(action: createPage) {
                Text("Create Page")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding()
        .frame(width: 400, height: 300)
        .onAppear { isTitleFocused = true }
    }
    
    private func createPage() {
        let page = WorkspaceItem.page(
            title: title.isEmpty ? "Untitled" : title,
            icon: icon,
            parentID: parentID
        )
        
        // Apply template blocks
        var pageWithBlocks = page
        pageWithBlocks.blocks = selectedTemplate.blocks
        
        storage.createItem(pageWithBlocks)
        onCreated(pageWithBlocks)
        isPresented = false
    }
}

// MARK: - Page Template

enum PageTemplate: String, CaseIterable {
    case blank = "Blank"
    case notes = "Notes"
    case meeting = "Meeting"
    case doc = "Document"
    
    var icon: String {
        switch self {
        case .blank: return "doc"
        case .notes: return "note.text"
        case .meeting: return "person.2"
        case .doc: return "doc.richtext"
        }
    }
    
    var blocks: [Block] {
        switch self {
        case .blank:
            return []
            
        case .notes:
            return [
                Block(type: .heading2, content: "Notes"),
                Block(type: .paragraph, content: ""),
                Block(type: .divider, content: ""),
                Block(type: .heading3, content: "Key Points"),
                Block(type: .bulletList, content: ""),
            ]
            
        case .meeting:
            return [
                Block(type: .heading2, content: "Meeting Notes"),
                Block(type: .meetingAttendees, content: ""),
                Block(type: .meetingAgenda, content: ""),
                Block(type: .meetingNotes, content: ""),
                Block(type: .meetingDecisions, content: ""),
                Block(type: .meetingActionItems, content: ""),
                Block(type: .meetingNextSteps, content: "")
            ]
            
        case .doc:
            return [
                Block(type: .heading1, content: "Document Title"),
                Block(type: .paragraph, content: "Introduction paragraph..."),
                Block(type: .divider, content: ""),
                Block(type: .heading2, content: "Section 1"),
                Block(type: .paragraph, content: ""),
            ]
        }
    }
}

struct TemplateButton: View {
    let template: PageTemplate
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: template.icon)
                    .font(.title2)
                Text(template.rawValue)
                    .font(.caption)
            }
            .frame(width: 70, height: 60)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
