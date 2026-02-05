import SwiftUI

// MARK: - Speaker Library View

struct SpeakerLibraryView: View {
    @StateObject private var library = SpeakerLibrary.shared
    @State private var selectedSpeaker: KnownSpeaker?
    @State private var showingAddSpeaker = false
    @State private var searchText = ""

    var body: some View {
        HSplitView {
            // Left: Speakers list
            SpeakerListView(
                speakers: filteredSpeakers,
                selectedSpeaker: $selectedSpeaker,
                onDelete: deleteSpeaker
            )
            .frame(minWidth: 250, maxWidth: 350)

            // Right: Speaker detail or empty state
            if let speaker = selectedSpeaker {
                SpeakerDetailView(
                    speaker: binding(for: speaker),
                    library: library,
                    onDelete: {
                        deleteSpeaker(speaker.id)
                        selectedSpeaker = nil
                    }
                )
            } else {
                EmptySpeakerDetailView(onAddSpeaker: { showingAddSpeaker = true })
            }
        }
        .searchable(text: $searchText, prompt: "Search speakers...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showingAddSpeaker = true }) {
                    Label("Add Speaker", systemImage: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSpeaker) {
            AddSpeakerSheet(library: library) { newSpeaker in
                selectedSpeaker = newSpeaker
            }
        }
    }

    private var filteredSpeakers: [KnownSpeaker] {
        library.searchSpeakers(query: searchText)
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func deleteSpeaker(_ id: UUID) {
        library.deleteSpeaker(id)
    }

    private func binding(for speaker: KnownSpeaker) -> Binding<KnownSpeaker> {
        Binding(
            get: {
                library.speakers.first { $0.id == speaker.id } ?? speaker
            },
            set: { newValue in
                library.updateSpeaker(newValue)
                selectedSpeaker = newValue
            }
        )
    }
}

// MARK: - Speaker List View

struct SpeakerListView: View {
    let speakers: [KnownSpeaker]
    @Binding var selectedSpeaker: KnownSpeaker?
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Speaker Library")
                    .font(.headline)
                Spacer()
                Text("\(speakers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding()

            Divider()

            if speakers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No speakers yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add speakers to quickly identify them in your sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                List(speakers, selection: $selectedSpeaker) { speaker in
                    SpeakerLibraryRowView(speaker: speaker)
                        .tag(speaker)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                onDelete(speaker.id)
                            }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Speaker Library Row View

struct SpeakerLibraryRowView: View {
    let speaker: KnownSpeaker

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(speaker.displayColor)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(speaker.name.prefix(1).uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.name)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if speaker.usageCount > 0 {
                        Text("Used \(speaker.usageCount)x")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let notes = speaker.notes, !notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty Speaker Detail View

struct EmptySpeakerDetailView: View {
    let onAddSpeaker: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Select a speaker")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Choose a speaker from the list to view and edit their details")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button(action: onAddSpeaker) {
                Label("Add New Speaker", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Speaker Detail Tab

enum SpeakerDetailTab: String, CaseIterable {
    case info = "Info"
    case sessions = "Sessions"
    case training = "Training"
    case chat = "Chat"

    var icon: String {
        switch self {
        case .info: return "person.circle"
        case .sessions: return "waveform"
        case .training: return "brain.head.profile"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Speaker Detail View

struct SpeakerDetailView: View {
    @Binding var speaker: KnownSpeaker
    @ObservedObject var library: SpeakerLibrary
    let onDelete: () -> Void
    @State private var selectedTab: SpeakerDetailTab = .info
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with avatar and tabs
            speakerHeader

            Divider()

            // Tab content
            tabContent
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Delete Speaker?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This action cannot be undone.")
        }
        .onChange(of: speaker) { newValue in
            library.updateSpeaker(newValue)
        }
    }

    // MARK: - Speaker Header

    private var speakerHeader: some View {
        VStack(spacing: 16) {
            // Avatar and name
            HStack(spacing: 16) {
                Circle()
                    .fill(speaker.displayColor)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(speaker.name.prefix(1).uppercased())
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(speaker.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        Text("Added \(speaker.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if speaker.usageCount > 0 {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("Used in \(speaker.usageCount) sessions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            // Tab picker
            HStack(spacing: 0) {
                ForEach(SpeakerDetailTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.caption)
                                Text(tab.rawValue)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                            Rectangle()
                                .fill(selectedTab == tab ? Color.blue : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedTab == tab ? .blue : .secondary)
                }

                Spacer()
            }
            .padding(.horizontal)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .info:
            SpeakerInfoTab(speaker: $speaker, library: library, onDelete: { showingDeleteConfirmation = true })
        case .sessions:
            SpeakerSessionsTab(speaker: speaker)
        case .training:
            SpeakerTrainingTab(speaker: speaker)
        case .chat:
            SpeakerChatView(speaker: speaker)
        }
    }
}

// MARK: - Speaker Info Tab

struct SpeakerInfoTab: View {
    @Binding var speaker: KnownSpeaker
    @ObservedObject var library: SpeakerLibrary
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Name field
                VStack(alignment: .leading, spacing: 12) {
                    Text("Name")
                        .font(.headline)

                    TextField("Speaker name", text: $speaker.name)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                // Color picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color")
                        .font(.headline)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(KnownSpeaker.defaultColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color) ?? .gray)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: speaker.color == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    speaker.color = color
                                }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                // Notes
                VStack(alignment: .leading, spacing: 12) {
                    Text("Notes")
                        .font(.headline)

                    CommitTextView(
                        text: Binding(
                            get: { speaker.notes ?? "" },
                            set: { speaker.notes = $0.isEmpty ? nil : $0 }
                        ),
                        onCommit: { },
                        onCancel: { }
                    )
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)

                    Text("Add notes to help identify this speaker (e.g., \"Project manager\", \"Deep voice\")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                // Voice characteristics
                VStack(alignment: .leading, spacing: 12) {
                    Text("Voice Characteristics")
                        .font(.headline)

                    TextField("Describe the voice...", text: Binding(
                        get: { speaker.voiceCharacteristics ?? "" },
                        set: { speaker.voiceCharacteristics = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Text("Describe distinctive voice features to help match this speaker in future sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                // Danger zone
                VStack(alignment: .leading, spacing: 12) {
                    Text("Danger Zone")
                        .font(.headline)
                        .foregroundColor(.red)

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Speaker", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Text("This will remove the speaker from your library. Sessions will keep their speaker data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.red.opacity(0.05))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}

// MARK: - Add Speaker Sheet

struct AddSpeakerSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var library: SpeakerLibrary
    let onAdd: (KnownSpeaker) -> Void

    @State private var name = ""
    @State private var selectedColor = KnownSpeaker.defaultColors[0]
    @State private var notes = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Speaker")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            Form {
                // Name
                TextField("Name", text: $name)

                // Color
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(KnownSpeaker.defaultColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color) ?? .gray)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                }

                // Notes (optional)
                Section("Notes (optional)") {
                    TextField("E.g., Team lead, deep voice", text: $notes)
                }
            }
            .padding()

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Add Speaker") {
                    let speaker = library.addSpeaker(
                        name: name,
                        color: selectedColor,
                        notes: notes.isEmpty ? nil : notes
                    )
                    onAdd(speaker)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
    }
}

#Preview {
    SpeakerLibraryView()
        .frame(width: 800, height: 600)
}
