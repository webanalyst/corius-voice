import SwiftUI

struct SnippetsView: View {
    @State private var snippets: [Snippet] = []
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingSnippet: Snippet?
    @State private var showingDeleteAlert = false
    @State private var snippetToDelete: Snippet?

    var filteredSnippets: [Snippet] {
        if searchText.isEmpty {
            return snippets
        }
        return snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)

                Spacer()

                Button(action: { showingAddSheet = true }) {
                    Label("Add Snippet", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            // Content
            if filteredSnippets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.insert")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No snippets" : "No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Create text snippets that expand when you speak the trigger phrase")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    if searchText.isEmpty {
                        Button("Add Snippet") {
                            showingAddSheet = true
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredSnippets) { snippet in
                        SnippetRow(
                            snippet: snippet,
                            onToggle: { toggleSnippet(snippet) },
                            onEdit: { editingSnippet = snippet },
                            onDelete: {
                                snippetToDelete = snippet
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            loadSnippets()
        }
        .sheet(isPresented: $showingAddSheet) {
            SnippetSheet(
                snippet: nil,
                onSave: { newSnippet in
                    snippets.append(newSnippet)
                    saveSnippets()
                }
            )
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetSheet(
                snippet: snippet,
                onSave: { updatedSnippet in
                    if let index = snippets.firstIndex(where: { $0.id == updatedSnippet.id }) {
                        snippets[index] = updatedSnippet
                        saveSnippets()
                    }
                }
            )
        }
        .alert("Delete Snippet?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let snippet = snippetToDelete {
                    deleteSnippet(snippet)
                }
            }
        }
    }

    private func loadSnippets() {
        snippets = StorageService.shared.snippets
    }

    private func saveSnippets() {
        StorageService.shared.snippets = snippets
    }

    private func toggleSnippet(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index].isEnabled.toggle()
            saveSnippets()
        }
    }

    private func deleteSnippet(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        saveSnippets()
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { snippet.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.trigger)
                    .font(.body)
                    .fontWeight(.medium)

                Text(snippet.preview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
        .opacity(snippet.isEnabled ? 1.0 : 0.5)
    }
}

struct SnippetSheet: View {
    @Environment(\.dismiss) var dismiss

    let snippet: Snippet?
    let onSave: (Snippet) -> Void

    @State private var trigger = ""
    @State private var content = ""

    var isEditing: Bool { snippet != nil }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Snippet" : "New Snippet")
                .font(.headline)

            Form {
                TextField("Trigger phrase", text: $trigger)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading) {
                    Text("Content")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                        .border(Color.gray.opacity(0.3))
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    let newSnippet = Snippet(
                        id: snippet?.id ?? UUID(),
                        trigger: trigger,
                        content: content,
                        isEnabled: snippet?.isEnabled ?? true
                    )
                    onSave(newSnippet)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trigger.isEmpty || content.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
        .onAppear {
            if let snippet = snippet {
                trigger = snippet.trigger
                content = snippet.content
            }
        }
    }
}

#Preview {
    SnippetsView()
}
