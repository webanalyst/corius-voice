import SwiftUI
import Combine

// MARK: - Transcript Search View

/// Full-text search UI for transcript content with debounced input, highlighted results, and timestamp navigation
struct TranscriptSearchView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var searchIndex = TranscriptSearchIndex.shared
    @StateObject private var recentSearches = RecentSearches()

    // Search state
    @State private var searchText = ""
    @State private var debouncer = Debouncer(delay: 0.3)
    @State private var currentSearchTask: Task<Void, Never>?
    @State private var allSearchResults: [SessionMatch] = []
    @State private var isSearching = false
    @State private var searchDuration: TimeInterval = 0
    @State private var selectedMatch: SessionMatch?
    @FocusState private var isSearchFocused: Bool

    // UI state
    @State private var showRecentSearches = false
    @State private var sortOption: SortOption = .relevance
    @State private var expandedSessions: Set<UUID> = []
    @State private var visibleResults: Int = 20
    @State private var groupedResults: [UUID: [SessionMatch]] = [:]

    // Navigation
    @State private var selectedSessionID: UUID?
    @State private var showSessionDetail = false
    @State private var navigateToSession: UUID?
    @State private var navigateToTimestamp: TimeInterval?

    enum SortOption: String, CaseIterable {
        case relevance = "Relevance"
        case date = "Date"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search header
            searchHeader

            Divider()

            // Results or empty state
            if searchText.isEmpty {
                emptyStateView
            } else if isSearching {
                searchingView
            } else if searchResults.isEmpty {
                noResultsView
            } else {
                resultsListView
            }
        }
        .frame(minWidth: 400, idealWidth: 500, maxWidth: 600)
        .frame(minHeight: 300, idealHeight: 500)
        .onAppear {
            // Auto-focus search field on appear
            isSearchFocused = true
        }
        .onDisappear {
            // Clear results when dismissing
            searchText = ""
            searchResults = []
        }
        .keyboardShortcut(KeyEquivalent("f"), modifiers: [.command, .shift])
        .background(
            // Navigation link for jumping to sessions
            NavigationLink(
                destination: navigateToSession.map { sessionID in
                    SessionDetailView(sessionID: sessionID, initialTimestamp: navigateToTimestamp)
                        .environmentObject(appState)
                },
                isActive: Binding(
                    get: { navigateToSession != nil },
                    set: { if !$0 { navigateToSession = nil; navigateToTimestamp = nil } }
                ),
                label: { EmptyView() }
            )
        )
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        HStack(spacing: 12) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.body)

            // Text field
            TextField("Search transcripts...", text: $searchText)
                .focused($isSearchFocused)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, newValue in
                    debouncer.debounce {
                        performSearch(query: newValue)
                    }
                }
                .onSubmit {
                    // Jump to first result on Enter
                    if let firstMatch = searchResults.first {
                        jumpToMatch(firstMatch)
                    }
                }

            // Clear button
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchResults = []
                    searchDuration = 0
                    isSearchFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text("Search Transcripts")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Type keywords to search across all session transcripts")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tips:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Use multiple words for better matches")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("• Press ⌘⇧F to focus search")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("• Press Enter to jump to first result")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Searching View

    private var searchingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching...")
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - No Results View

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "questionmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text("No results found")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("No transcripts match \"\(searchText)\"")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Try different keywords or check spelling")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsListView: some View {
        VStack(spacing: 0) {
            // Results header with count and duration
            HStack {
                Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if searchDuration > 0 {
                    Text("\(String(format: "%.0f", searchDuration * 1000))ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.separatorColor).opacity(0.3))

            Divider()

            // Scrollable results
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(searchResults) { match in
                        SearchResultRow(
                            match: match,
                            searchQuery: searchText,
                            onTap: {
                                jumpToMatch(match)
                            }
                        )
                        .id(match.id)

                        if match.id != searchResults.last?.id {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func performSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            searchResults = []
            searchDuration = 0
            return
        }

        isSearching = true

        // Measure search performance
        let startTime = Date()

        // Perform search on background thread
        Task.detached(priority: .userInitiated) {
            let results = await TranscriptSearchIndex.shared.search(query: trimmedQuery)
            let duration = Date().timeIntervalSince(startTime)

            // Update UI on main thread
            await MainActor.run {
                self.searchResults = results
                self.searchDuration = duration
                self.isSearching = false
            }
        }
    }

    private func jumpToMatch(_ match: SessionMatch) {
        navigateToSession = match.id
        navigateToTimestamp = match.timestamp
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let match: SessionMatch
    let searchQuery: String
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Relevance indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(relevanceColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 6) {
                    // Title row
                    HStack {
                        if let title = match.title, !title.isEmpty {
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        } else {
                            Text("Untitled Session")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Timestamp badge
                        Text(match.timestamp.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }

                    // Highlighted snippet
                    highlightedSnippet
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(3)

                    // Relevance score (debug/feedback)
                    if isHovering {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption2)
                            Text("\(Int(match.relevanceScore * 100))% relevance")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)

                Spacer()
            }
            .padding(.horizontal, 12)
            .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help("Click to jump to this position in the session")
    }

    private var highlightedSnippet: some View {
        Text(attributedSnippet)
    }

    private var attributedSnippet: AttributedString {
        var attributed = AttributedString(match.snippet)

        // Highlight query terms in the snippet
        let queryTerms = searchQuery.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        for term in queryTerms {
            let range = attributed.range(of: term, options: .caseInsensitive)
            if let range {
                attributed[range].backgroundColor = .accentColor.opacity(0.3)
                attributed[range].font = .body.bold()
            }
        }

        return attributed
    }

    private var relevanceColor: Color {
        let score = match.relevanceScore
        if score >= 0.8 {
            return .green
        } else if score >= 0.5 {
            return .yellow
        } else {
            return .orange
        }
    }
}

// MARK: - Preview

#Preview {
    TranscriptSearchView()
        .environmentObject(AppState.shared)
        .frame(width: 500, height: 600)
}
