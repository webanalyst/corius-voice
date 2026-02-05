import SwiftUI

struct NotesView: View {
    @EnvironmentObject var appState: AppState
    @State private var notes: [Note] = []
    @State private var selectedNote: Note?
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var noteToDelete: Note?
    @State private var isRecordingNote = false
    @State private var recordedText = ""

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
                // Voice input section
                VoiceNoteInputView(
                    isRecording: $isRecordingNote,
                    recordedText: $recordedText,
                    onCreateNote: { text in
                        createNoteFromVoice(text)
                    }
                )
                .padding()

                Divider()

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search notes...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.vertical, 8)

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
                            Text("Use voice input above to create notes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
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
            .frame(minWidth: 280)

            // Note editor
            if let note = selectedNote {
                NoteEditorView(note: note, onSave: { updatedNote in
                    updateNote(updatedNote)
                })
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select or create a note")
                        .foregroundColor(.secondary)

                    Text("Hold Fn to record a voice note")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadNotes()
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

    private func createNoteFromVoice(_ text: String) {
        guard !text.isEmpty else { return }

        // Auto-generate title from first line or first few words
        let title = generateTitle(from: text)
        let newNote = Note(title: title, content: text)
        notes.insert(newNote, at: 0)
        saveNotes()
        selectedNote = newNote
        recordedText = ""
    }

    private func generateTitle(from text: String) -> String {
        let firstLine = text.components(separatedBy: "\n").first ?? text
        if firstLine.count <= 40 {
            return firstLine
        }
        let words = firstLine.components(separatedBy: " ")
        var title = ""
        for word in words {
            if (title + " " + word).count > 40 {
                break
            }
            title = title.isEmpty ? word : title + " " + word
        }
        return title + "..."
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

// MARK: - Voice Note Input View

struct VoiceNoteInputView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isRecording: Bool
    @Binding var recordedText: String
    var onCreateNote: (String) -> Void

    @State private var showingTextField = false

    var body: some View {
        VStack(spacing: 12) {
            // Main input area
            HStack(spacing: 12) {
                // Recording indicator / mic button
                Button(action: {
                    // Toggle between voice and text input
                    showingTextField.toggle()
                }) {
                    ZStack {
                        Circle()
                            .fill(appState.isRecording ? Color.red : Color.accentColor.opacity(0.2))
                            .frame(width: 44, height: 44)

                        Image(systemName: appState.isRecording ? "stop.fill" : "mic.fill")
                            .foregroundColor(appState.isRecording ? .white : .accentColor)
                            .font(.title3)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    if appState.isRecording {
                        HStack(spacing: 8) {
                            PulsingDot()
                            Text("Recording...")
                                .font(.headline)
                                .foregroundColor(.red)
                        }

                        if !appState.currentTranscription.isEmpty {
                            Text(appState.currentTranscription)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }
                    } else if showingTextField {
                        TextField("Type a note...", text: $recordedText)
                            .textFieldStyle(.plain)
                            .font(.body)
                    } else {
                        Text("Hold Fn key to record a voice note")
                            .font(.body)
                            .foregroundColor(.secondary)

                        Text("Or click the mic to type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Create button
                if !recordedText.isEmpty || !appState.currentTranscription.isEmpty {
                    Button("Create Note") {
                        let text = recordedText.isEmpty ? appState.currentTranscription : recordedText
                        onCreateNote(text)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(appState.isRecording ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(appState.isRecording ? Color.red.opacity(0.3) : Color.clear, lineWidth: 2)
                    )
            )
        }
    }
}

// MARK: - Pulsing Dot Animation

struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Note Row View

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

            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(note.formattedDate)
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Note Editor View

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
                .fontWeight(.semibold)
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
            CommitTextView(
                text: $content,
                onCommit: {
                    var updated = note
                    updated.update(content: content)
                    note = updated
                    onSave(note)
                },
                onCancel: { content = note.content }
            )
            .padding()
            .focused($isContentFocused)

            Divider()

            // Footer
            HStack {
                Label("\(content.wordCount) words", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Label(note.formattedDate, systemImage: "clock")
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

#Preview {
    NotesView()
        .environmentObject(AppState.shared)
}
