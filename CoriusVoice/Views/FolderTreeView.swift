import SwiftUI

// MARK: - Folder Tree View

struct FolderTreeView: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var showingNewFolderSheet = false
    @State private var showingNewLabelSheet = false
    @State private var newFolderParentID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Folders Section
            foldersSection

            Divider()
                .padding(.vertical, 8)

            // Labels Section
            labelsSection

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingNewFolderSheet) {
            FolderEditSheet(
                viewModel: viewModel,
                parentID: newFolderParentID,
                existingFolder: nil
            )
        }
        .sheet(isPresented: $showingNewLabelSheet) {
            LabelEditSheet(
                viewModel: viewModel,
                existingLabel: nil
            )
        }
    }

    // MARK: - Folders Section

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section Header
            HStack {
                Text("Folders")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    newFolderParentID = nil
                    showingNewFolderSheet = true
                }) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Create new folder")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Folder Tree - already lazy with LazyVStack, folders are typically < 100 items
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.rootFolders) { folder in
                        FolderRowView(
                            folder: folder,
                            viewModel: viewModel,
                            depth: 0,
                            onCreateSubfolder: { parentID in
                                newFolderParentID = parentID
                                showingNewFolderSheet = true
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Labels Section

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section Header
            HStack {
                Text("Labels")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    showingNewLabelSheet = true
                }) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Create new label")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            // Labels List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.labels.sorted) { label in
                        LabelRowView(
                            label: label,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 200)
        }
    }
}

// MARK: - Folder Row View

struct FolderRowView: View {
    let folder: Folder
    @ObservedObject var viewModel: FolderTreeViewModel
    let depth: Int
    let onCreateSubfolder: (UUID) -> Void

    @State private var isHovering = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var isDropTargeted = false

    private var isSelected: Bool {
        viewModel.selectedFolderID == folder.id
    }

    private var isExpanded: Bool {
        viewModel.isExpanded(folder.id)
    }

    private var hasChildren: Bool {
        viewModel.hasChildren(folder.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folder Row
            HStack(spacing: 6) {
                // Expand/Collapse button
                if hasChildren {
                    Button(action: { viewModel.toggleExpanded(folder.id) }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 16)
                }

                // Folder icon (fixed width for alignment)
                Image(systemName: folder.icon)
                    .font(.system(size: 14))
                    .foregroundColor(folder.color.flatMap { Color(hex: $0) } ?? .accentColor)
                    .frame(width: 20, alignment: .center)

                // Folder name
                Text(folder.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()

                // Session count
                Text("\(viewModel.sessionCount(for: folder.id))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding(.leading, CGFloat(depth * 16))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isDropTargeted ? Color.accentColor.opacity(0.3) :
                        (isSelected ? Color.primary.opacity(0.1) :
                        (isHovering ? Color.primary.opacity(0.05) : Color.clear))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectFolder(folder.id)
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .dropDestination(for: SessionDragItem.self) { items, _ in
                guard let item = items.first else { return false }
                // Move session to this folder (nil for Inbox)
                let targetFolderID = folder.isInbox ? nil : folder.id
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.moveSession(item.sessionID, to: targetFolderID)
                }
                return true
            } isTargeted: { isTargeted in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isDropTargeted = isTargeted
                }
            }
            .contextMenu {
                if !folder.isSystem {
                    Button("Rename...") {
                        showingEditSheet = true
                    }

                    Button("New Subfolder...") {
                        onCreateSubfolder(folder.id)
                    }

                    Divider()

                    Button("Delete", role: .destructive) {
                        showingDeleteAlert = true
                    }
                } else {
                    Button("New Subfolder...") {
                        onCreateSubfolder(folder.id)
                    }
                }
            }

            // Children (if expanded)
            if isExpanded {
                ForEach(viewModel.children(of: folder.id)) { child in
                    FolderRowView(
                        folder: child,
                        viewModel: viewModel,
                        depth: depth + 1,
                        onCreateSubfolder: onCreateSubfolder
                    )
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            FolderEditSheet(
                viewModel: viewModel,
                parentID: folder.parentID,
                existingFolder: folder
            )
        }
        .alert("Delete Folder?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.deleteFolder(folder.id)
            }
        } message: {
            Text("This will move all sessions in this folder to the Inbox. This action cannot be undone.")
        }
    }
}

// MARK: - Label Row View

struct LabelRowView: View {
    let label: SessionLabel
    @ObservedObject var viewModel: FolderTreeViewModel

    @State private var isHovering = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false

    private var isSelected: Bool {
        viewModel.selectedLabelID == label.id
    }

    var body: some View {
        HStack(spacing: 8) {
            // Color indicator
            Circle()
                .fill(Color(hex: label.color) ?? .gray)
                .frame(width: 10, height: 10)

            // Icon (if present, with fixed width for alignment)
            if let icon = label.icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: label.color) ?? .gray)
                    .frame(width: 16, alignment: .center)
            } else {
                Spacer()
                    .frame(width: 16)
            }

            // Label name
            Text(label.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            // Session count
            Text("\(viewModel.sessionCountByLabel(label.id))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.1) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectLabel(label.id)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Edit...") {
                showingEditSheet = true
            }

            Divider()

            Button("Delete", role: .destructive) {
                showingDeleteAlert = true
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            LabelEditSheet(
                viewModel: viewModel,
                existingLabel: label
            )
        }
        .alert("Delete Label?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.deleteLabel(label.id)
            }
        } message: {
            Text("This will remove the label from all sessions. This action cannot be undone.")
        }
    }
}

// MARK: - Folder Edit Sheet

struct FolderEditSheet: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    let parentID: UUID?
    let existingFolder: Folder?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedIcon: String = "folder.fill"
    @State private var selectedColor: String? = nil

    private var isEditing: Bool {
        existingFolder != nil
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text(isEditing ? "Edit Folder" : "New Folder")
                .font(.headline)

            // Name field
            TextField("Folder Name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Icon picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 8), spacing: 8) {
                    ForEach(Folder.presetIcons, id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .frame(width: 28, height: 28)
                                .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color (optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    // No color option
                    Button(action: { selectedColor = nil }) {
                        Image(systemName: "circle.slash")
                            .font(.system(size: 16))
                            .frame(width: 24, height: 24)
                            .background(selectedColor == nil ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    ForEach(Folder.presetColors.prefix(9), id: \.self) { color in
                        Button(action: { selectedColor = color }) {
                            Circle()
                                .fill(Color(hex: color) ?? .gray)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(isEditing ? "Save" : "Create") {
                    saveFolder()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
        .onAppear {
            if let folder = existingFolder {
                name = folder.name
                selectedIcon = folder.icon
                selectedColor = folder.color
            }
        }
    }

    private func saveFolder() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if var folder = existingFolder {
            folder.name = trimmedName
            folder.icon = selectedIcon
            folder.color = selectedColor
            viewModel.updateFolder(folder)
        } else {
            viewModel.createFolder(
                name: trimmedName,
                parentID: parentID,
                icon: selectedIcon,
                color: selectedColor
            )
        }
    }
}

// MARK: - Label Edit Sheet

struct LabelEditSheet: View {
    @ObservedObject var viewModel: FolderTreeViewModel
    let existingLabel: SessionLabel?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedColor: String = "#3B82F6"
    @State private var selectedIcon: String? = nil

    private var isEditing: Bool {
        existingLabel != nil
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text(isEditing ? "Edit Label" : "New Label")
                .font(.headline)

            // Name field
            TextField("Label Name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 8), spacing: 8) {
                    ForEach(SessionLabel.presetColors, id: \.self) { color in
                        Button(action: { selectedColor = color }) {
                            Circle()
                                .fill(Color(hex: color) ?? .gray)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Icon picker (optional)
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon (optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    // No icon option
                    Button(action: { selectedIcon = nil }) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: selectedColor) ?? .gray)
                            .frame(width: 28, height: 28)
                            .background(selectedIcon == nil ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    ForEach(SessionLabel.presetIcons.prefix(11), id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: selectedColor) ?? .gray)
                                .frame(width: 28, height: 28)
                                .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(isEditing ? "Save" : "Create") {
                    saveLabel()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 380)
        .onAppear {
            if let label = existingLabel {
                name = label.name
                selectedColor = label.color
                selectedIcon = label.icon
            }
        }
    }

    private func saveLabel() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if var label = existingLabel {
            label.name = trimmedName
            label.color = selectedColor
            label.icon = selectedIcon
            viewModel.updateLabel(label)
        } else {
            viewModel.createLabel(
                name: trimmedName,
                color: selectedColor,
                icon: selectedIcon
            )
        }
    }
}

#Preview {
    FolderTreeView(viewModel: FolderTreeViewModel())
        .frame(height: 500)
}
