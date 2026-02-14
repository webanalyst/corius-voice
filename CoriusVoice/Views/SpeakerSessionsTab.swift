import SwiftUI

// MARK: - Speaker Sessions Tab

struct SpeakerSessionsTab: View {
    let speaker: KnownSpeaker
    @StateObject private var lazyLoader = SpeakerLazyLoadingService(
        pageSize: 20,
        preloadThreshold: 5,
        cacheCapacity: 50
    )
    @State private var allSessions: [RecordingSession] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedSession: RecordingSession?

    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            sessionStatsHeader
            Divider()

            if isLoading {
                ProgressView("Loading sessions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lazyLoader.items.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
        .onAppear {
            loadSessions()
        }
        .onChange(of: searchText) { _, _ in
            updateLazyLoader()
        }
    }

    // MARK: - Stats Header

    private var sessionStatsHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                SpeakerStatBox(
                    title: "Sessions",
                    value: "\(allSessions.count)",
                    icon: "waveform"
                )

                SpeakerStatBox(
                    title: "Total Duration",
                    value: formattedTotalDuration,
                    icon: "clock"
                )

                SpeakerStatBox(
                    title: "Words Spoken",
                    value: "\(totalWordsSpoken)",
                    icon: "text.word.spacing"
                )

                Spacer()
            }

            // Inline search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sessions...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Sessions List
    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(lazyLoader.items.enumerated()), id: \.element.id) { index, session in
                    SpeakerSessionRowView(session: session, speaker: speaker)
                        .tag(session)
                        .onAppear {
                            // Prefetch next page when approaching end
                            if lazyLoader.shouldLoadMore(currentIndex: index) {
                                let _ = lazyLoader.loadNextPage(from: filteredSessions)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSession = session
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    
                    if index < lazyLoader.items.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
                
                // Loading indicator at bottom
                if lazyLoader.isLoading && lazyLoader.hasMorePages {
                    ProgressView()
                        .padding()
                }
                
                // End of list indicator
                if !lazyLoader.hasMorePages && !lazyLoader.items.isEmpty {
                    Text("All sessions loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No sessions found")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("\(speaker.name) hasn't participated in any recorded sessions yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    // MARK: - Computed Properties
    private var filteredSessions: [RecordingSession] {
        guard !searchText.isEmpty else {
            return allSessions.sorted { $0.startDate > $1.startDate }
        }

        let query = searchText.lowercased()
        return allSessions.filter { session in
            (session.title?.lowercased().contains(query) ?? false) ||
            session.fullTranscript.lowercased().contains(query)
        }.sorted { $0.startDate > $1.startDate }
    }

    private var formattedTotalDuration: String {
        let total = allSessions.reduce(0.0) { $0 + $1.duration }
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var totalWordsSpoken: Int {
        allSessions.reduce(0) { total, session in
            total + countWordsForSpeaker(in: session)
        }
    }

    // MARK: - Methods
    private func loadSessions() {
        isLoading = true
        let loadedSessions = StorageService.shared.loadSessions()
        let speakerName = speaker.name.lowercased()

        allSessions = loadedSessions.filter { session in
            session.speakers.contains { $0.name?.lowercased() == speakerName }
        }
        
        // Initialize lazy loader with filtered sessions
        lazyLoader.initialize(with: filteredSessions)
        
        isLoading = false
    }
    
    // Update loader when search changes
    private func updateLazyLoader() {
        lazyLoader.refresh(with: filteredSessions)
    }

    private func countWordsForSpeaker(in session: RecordingSession) -> Int {
        let speakerName = speaker.name.lowercased()
        guard let speakerIndex = session.speakers.first(where: { $0.name?.lowercased() == speakerName })?.id else {
            return 0
        }

        return session.transcriptSegments
            .filter { $0.speakerID == speakerIndex }
            .reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
}

// MARK: - Speaker Session Row View

struct SpeakerSessionRowView: View {
    let session: RecordingSession
    let speaker: KnownSpeaker
    var body: some View {
        HStack(spacing: 12) {
            // Session type icon
            Image(systemName: session.sessionType.icon)
                .font(.title2)
                .foregroundColor(Color(hex: speaker.color) ?? .blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label(session.startDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(session.formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("\(session.wordCount) words", systemImage: "text.word.spacing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Summary indicator
            if session.summary != nil {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.green)
                    .help("Has summary")
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Speaker Stat Box

struct SpeakerStatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    SpeakerSessionsTab(speaker: KnownSpeaker(name: "Test Speaker"))
        .frame(width: 600, height: 400)
}
