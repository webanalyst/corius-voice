import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTranscription: Transcription?
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var transcriptionToDelete: Transcription?

    var filteredTranscriptions: [Transcription] {
        if searchText.isEmpty {
            return appState.transcriptions
        }
        return appState.transcriptions.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HSplitView {
            // List
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search transcriptions...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding()

                Divider()

                // Transcription list
                if filteredTranscriptions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "Press and hold Fn to start recording" : "Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredTranscriptions, selection: $selectedTranscription) { transcription in
                        TranscriptionRowView(transcription: transcription)
                            .tag(transcription)
                            .contextMenu {
                                Button("Copy") {
                                    KeyboardService.shared.copyToClipboard(transcription.text)
                                }
                                Button("Paste") {
                                    KeyboardService.shared.pasteText(transcription.text)
                                }
                                Divider()
                                Button(transcription.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                                    toggleFavorite(transcription)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    transcriptionToDelete = transcription
                                    showingDeleteAlert = true
                                }
                            }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 300)

            // Detail view
            if let transcription = selectedTranscription {
                TranscriptionDetailView(transcription: transcription)
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a transcription")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Delete Transcription?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let transcription = transcriptionToDelete {
                    deleteTranscription(transcription)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func toggleFavorite(_ transcription: Transcription) {
        if let index = appState.transcriptions.firstIndex(where: { $0.id == transcription.id }) {
            appState.transcriptions[index].isFavorite.toggle()
            StorageService.shared.saveTranscriptions(appState.transcriptions)
        }
    }

    private func deleteTranscription(_ transcription: Transcription) {
        appState.transcriptions.removeAll { $0.id == transcription.id }
        StorageService.shared.saveTranscriptions(appState.transcriptions)
        if selectedTranscription?.id == transcription.id {
            selectedTranscription = nil
        }
    }
}

struct TranscriptionRowView: View {
    let transcription: Transcription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(transcription.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if transcription.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }

                Text(transcription.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(transcription.preview)
                .font(.body)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct TranscriptionDetailView: View {
    let transcription: Transcription
    @State private var isEditing = false
    @State private var editedText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(transcription.formattedDate)
                        .font(.headline)
                    Text("\(transcription.text.wordCount) words")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        KeyboardService.shared.copyToClipboard(transcription.text)
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")

                    Button(action: {
                        KeyboardService.shared.pasteText(transcription.text)
                    }) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Paste")
                }
            }

            Divider()

            // Content
            ScrollView {
                Text(transcription.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 300)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState.shared)
}
