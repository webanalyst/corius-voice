import SwiftUI

struct NotesView: View {
    @State private var notes: [Note] = []
    @State private var selectedNote: Note?
    @State private var searchText = ""
    @State private var showingNewNoteSheet = false
    @State private var showingDeleteAlert = false
    @State private var noteToDelete: Note?

    var filteredNotes: [Note] {
        if searchText.isEmpty {
            return notes
        }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            // Notes list
            VStack(spacing: 0) {
                // Search and add bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search notes...", text: $searchText)
                        .textFieldStyle(.plain)

                    Spacer()

                    Button(action: { showingNewNoteSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding()

                Divider()

                if filteredNotes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No notes yet" : "No results found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        if searchText.isEmpty {
                            Button("Create Note") {
                                showingNewNoteSheet = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredNotes, selection: $selectedNote) { note in
                        NoteRowView(note: note)
                            .tag(note)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    noteToDelete = note
                                    showingDeleteAlert = true
                                }
                            }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 250)

            // Note editor
            if let note = selectedNote {
                NoteEditorView(note: note, onSave: { updatedNote in
                    updateNote(updatedNote)
                })
            } else {
                VStack {
                    Image(systemName: "note.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select or create a note")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadNotes()
        }
        .sheet(isPresented: $showingNewNoteSheet) {
            NewNoteSheet(onSave: { newNote in
                notes.insert(newNote, at: 0)
                saveNotes()
                selectedNote = newNote
            })
        }
        .alert("Delete Note?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let note = noteToDelete {
                    deleteNote(note)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func loadNotes() {
        notes = StorageService.shared.loadNotes()
    }

    private func saveNotes() {
        StorageService.shared.saveNotes(notes)
    }

    private func updateNote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            saveNotes()
        }
    }

    private func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        saveNotes()
        if selectedNote?.id == note.id {
            selectedNote = nil
        }
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.headline)
                .lineLimit(1)

            Text(note.preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text(note.formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct NoteEditorView: View {
    @State var note: Note
    let onSave: (Note) -> Void

    @State private var title: String = ""
    @State private var content: String = ""
    @FocusState private var isContentFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title
            TextField("Title", text: $title)
                .font(.title2)
                .textFieldStyle(.plain)
                .padding()
                .onChange(of: title) { newValue in
                    var updated = note
                    updated.update(title: newValue)
                    note = updated
                    onSave(note)
                }

            Divider()

            // Content
            TextEditor(text: $content)
                .font(.body)
                .padding()
                .focused($isContentFocused)
                .onChange(of: content) { newValue in
                    var updated = note
                    updated.update(content: newValue)
                    note = updated
                    onSave(note)
                }

            Divider()

            // Footer
            HStack {
                Text("\(content.wordCount) words")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Last edited: \(note.formattedDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear {
            title = note.title
            content = note.content
        }
    }
}

struct NewNoteSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSave: (Note) -> Void

    @State private var title = ""
    @State private var content = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Note")
                .font(.headline)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $content)
                .frame(minHeight: 200)
                .border(Color.gray.opacity(0.3))

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    let note = Note(title: title, content: content)
                    onSave(note)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty && content.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}

#Preview {
    NotesView()
}
