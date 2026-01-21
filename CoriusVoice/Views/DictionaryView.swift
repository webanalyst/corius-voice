import SwiftUI

struct DictionaryView: View {
    @State private var entries: [DictionaryEntry] = []
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingEntry: DictionaryEntry?
    @State private var showingDeleteAlert = false
    @State private var entryToDelete: DictionaryEntry?

    var filteredEntries: [DictionaryEntry] {
        if searchText.isEmpty {
            return entries
        }
        return entries.filter {
            $0.trigger.localizedCaseInsensitiveContains(searchText) ||
            $0.replacement.localizedCaseInsensitiveContains(searchText)
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
                    Label("Add Entry", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            // Content
            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No dictionary entries" : "No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add words or phrases to automatically replace during transcription")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    if searchText.isEmpty {
                        Button("Add Entry") {
                            showingAddSheet = true
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        DictionaryEntryRow(
                            entry: entry,
                            onToggle: { toggleEntry(entry) },
                            onEdit: { editingEntry = entry },
                            onDelete: {
                                entryToDelete = entry
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            loadEntries()
        }
        .sheet(isPresented: $showingAddSheet) {
            DictionaryEntrySheet(
                entry: nil,
                onSave: { newEntry in
                    entries.append(newEntry)
                    saveEntries()
                }
            )
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEntrySheet(
                entry: entry,
                onSave: { updatedEntry in
                    if let index = entries.firstIndex(where: { $0.id == updatedEntry.id }) {
                        entries[index] = updatedEntry
                        saveEntries()
                    }
                }
            )
        }
        .alert("Delete Entry?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete {
                    deleteEntry(entry)
                }
            }
        }
    }

    private func loadEntries() {
        entries = StorageService.shared.dictionaryEntries
    }

    private func saveEntries() {
        StorageService.shared.dictionaryEntries = entries
    }

    private func toggleEntry(_ entry: DictionaryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].isEnabled.toggle()
            saveEntries()
        }
    }

    private func deleteEntry(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }
}

struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.trigger)
                        .font(.body)
                        .fontWeight(.medium)

                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text(entry.replacement)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                if entry.caseSensitive {
                    Text("Case sensitive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
        .opacity(entry.isEnabled ? 1.0 : 0.5)
    }
}

struct DictionaryEntrySheet: View {
    @Environment(\.dismiss) var dismiss

    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @State private var trigger = ""
    @State private var replacement = ""
    @State private var caseSensitive = false

    var isEditing: Bool { entry != nil }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Entry" : "New Entry")
                .font(.headline)

            Form {
                TextField("Trigger (word to replace)", text: $trigger)
                    .textFieldStyle(.roundedBorder)

                TextField("Replacement", text: $replacement)
                    .textFieldStyle(.roundedBorder)

                Toggle("Case sensitive", isOn: $caseSensitive)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    let newEntry = DictionaryEntry(
                        id: entry?.id ?? UUID(),
                        trigger: trigger,
                        replacement: replacement,
                        isEnabled: entry?.isEnabled ?? true,
                        caseSensitive: caseSensitive
                    )
                    onSave(newEntry)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trigger.isEmpty || replacement.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
        .onAppear {
            if let entry = entry {
                trigger = entry.trigger
                replacement = entry.replacement
                caseSensitive = entry.caseSensitive
            }
        }
    }
}

#Preview {
    DictionaryView()
}
