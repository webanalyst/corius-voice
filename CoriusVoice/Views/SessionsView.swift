import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import CoreMedia

// MARK: - Session Drag Item

struct SessionDragItem: Codable, Transferable {
    let sessionID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .sessionDragItem)
    }
}

extension UTType {
    static let sessionDragItem = UTType(exportedAs: "com.coriusvoice.session-drag-item")
}

// MARK: - Resizable Column Divider

struct ResizableDivider: View {
    @Binding var columnWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    var showSeparator: Bool = false

    @State private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Fixed width container (invisible)
            Color.clear
                .frame(width: 6)

            // Always-visible subtle separator line
            if showSeparator {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: 1)
            }

            // Hover/drag indicator (overlays the separator)
            if isDragging || isHovering {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 3)
            }
        }
        .frame(width: 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    let newWidth = columnWidth + value.translation.width
                    columnWidth = min(max(newWidth, minWidth), maxWidth)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

// MARK: - Sessions View (3-Column Layout)

struct SessionsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var folderViewModel = FolderTreeViewModel()
    @StateObject private var sessionRepository = SessionRepository.shared
    @State private var selectedSessionID: UUID?
    @State private var selectedSession: RecordingSession?
    @State private var showingNewSession = false
    @State private var showingImporter = false
    @State private var searchText = ""
    @State private var searchDebouncer = Debouncer(delay: 0.3)
    @State private var importError: String?
    @State private var showingImportError = false
    @State private var importOrphansMessage: String?
    @State private var showingImportOrphansResult = false
    @State private var dedupeMessage: String?
    @State private var showingDedupeResult = false

    // Resizable column widths
    @State private var folderColumnWidth: CGFloat = 220
    @State private var sessionsColumnWidth: CGFloat = 320

    /// Supported audio file types for import
    private static var supportedAudioTypes: [UTType] {
        var types: [UTType] = [.audio]
        if let webm = UTType(filenameExtension: "webm") { types.append(webm) }
        if let ogg = UTType(filenameExtension: "ogg") { types.append(ogg) }
        return types
    }

    var body: some View {
        Group {
            if folderViewModel.isLoading && !folderViewModel.hasLoadedOnce {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading sessions...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainContent
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { removeDuplicateSessions() }) {
                    Label("Remove Duplicates", systemImage: "trash.slash")
                }
                if folderViewModel.showDiskWarning {
                    Button(action: { importOrphanedSessions() }) {
                        Label("Reimport Audio Sessions", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Button(action: { showingImporter = true }) {
                    Label("Import Audio", systemImage: "square.and.arrow.down")
                }
                Button(action: { showingNewSession = true }) {
                    Label("New Session", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: Self.supportedAudioTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importAudioFile(from: url) { importedSession, error in
                        if let error = error {
                            importError = error
                            showingImportError = true
                        } else if let session = importedSession {
                            selectedSession = session
                            Task { @MainActor in
                                folderViewModel.reloadSessions()
                            }
                        }
                    }
                }
            case .failure(let error):
                importError = error.localizedDescription
                showingImportError = true
            }
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "Unknown error occurred")
        }
        .alert("Audio Reimport", isPresented: $showingImportOrphansResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importOrphansMessage ?? "Done.")
        }
        .alert("Remove Duplicates", isPresented: $showingDedupeResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(dedupeMessage ?? "Done.")
        }
        .sheet(isPresented: $showingNewSession) {
            SessionRecordingView()
                .environmentObject(appState)
                .frame(
                    minWidth: 800,
                    idealWidth: NSScreen.main.map { $0.frame.width * 0.7 } ?? 1000,
                    maxWidth: .infinity,
                    minHeight: 600,
                    idealHeight: NSScreen.main.map { $0.frame.height * 0.7 } ?? 700,
                    maxHeight: .infinity
                )
        }
        .onAppear {
            // Data loads from cache in ViewModel init, so this is rarely needed
            // Only load if somehow the cache was empty
            if !folderViewModel.hasLoadedOnce {
                folderViewModel.loadData()
            }
        }
        .onChange(of: showingNewSession) { _, isShowing in
            // Reload sessions when the recording sheet is dismissed
            if !isShowing {
                Task { @MainActor in
                    folderViewModel.reloadSessions()
                    // Select the most recent session if available (use metadata for fast lookup)
                    if let mostRecent = folderViewModel.sessionMetadata.sorted(by: { $0.startDate > $1.startDate }).first {
                        selectedSession = folderViewModel.loadFullSession(id: mostRecent.id)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingDidFinish)) { _ in
            Task { @MainActor in
                folderViewModel.reloadSessions()
            }
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            if folderViewModel.showDiskWarning {
                diskWarningBanner
            }

            HStack(spacing: 0) {
                // Column 1: Folder Tree
                FolderTreeView(viewModel: folderViewModel)
                    .frame(width: folderColumnWidth)

                // Resizable divider 1 (with visible separator)
                ResizableDivider(
                    columnWidth: $folderColumnWidth,
                    minWidth: 180,
                    maxWidth: 300,
                    showSeparator: true
                )

                // Column 2: Sessions list
                SessionsListView(
                    repository: sessionRepository,
                    selectedSessionID: Binding(
                        get: { selectedSessionID },
                        set: { newID in
                            selectedSessionID = newID
                            if let id = newID {
                                // Load full session from repository cache when selected
                                if let fullSession = sessionRepository.getFullSession(id: id) {
                                    selectedSession = fullSession
                                } else {
                                    selectedSession = folderViewModel.loadFullSession(id: id)
                                }
                            } else {
                                selectedSession = nil
                            }
                        }
                    ),
                    searchText: $searchText,
                    onDelete: { id in
                        deleteSession(id)
                        Task { @MainActor in
                            folderViewModel.reloadSessions()
                            sessionRepository.reloadTotalCount()
                        }
                    },
                    folderViewModel: folderViewModel
                )
                .frame(width: sessionsColumnWidth)

                // Resizable divider 2
                ResizableDivider(
                    columnWidth: $sessionsColumnWidth,
                    minWidth: 280,
                    maxWidth: 500
                )

                // Column 3: Session detail or empty state
                Group {
                    if let session = selectedSession {
                        SessionDetailView(session: binding(for: session))
                            .id(session.id)
                    } else {
                        EmptySessionDetailView(onNewSession: { showingNewSession = true })
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var diskWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("No local session data found")
                    .font(.headline)
                Text("SwiftData has metadata, but sessions.json is empty. You can reimport sessions from audio files.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { importOrphanedSessions() }) {
                Label("Reimport Audio", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            Button(action: { removeDuplicateSessions() }) {
                Label("Remove Duplicates", systemImage: "trash.slash")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .padding([.horizontal, .top])
    }

    private func importOrphanedSessions() {
        let metadataSnapshots = folderViewModel.sessionMetadata.map { meta in
            SessionMetadataSnapshot(
                id: meta.id,
                startDate: meta.startDate,
                endDate: meta.endDate,
                title: meta.title,
                sessionType: meta.sessionType,
                audioSource: meta.audioSource,
                audioFileName: meta.audioFileName,
                micAudioFileName: meta.micAudioFileName,
                systemAudioFileName: meta.systemAudioFileName,
                folderID: meta.folderID,
                labelIDs: meta.labelIDs,
                isClassified: meta.isClassified,
                aiSuggestedFolderID: meta.aiSuggestedFolderID,
                aiClassificationConfidence: meta.aiClassificationConfidence
            )
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let count = StorageService.shared.importOrphanedAudioFiles(using: metadataSnapshots)
            let message: String
            if count > 0 {
                message = "Imported \(count) session(s) from orphaned audio files."
            } else {
                message = "No orphaned audio files found to import."
            }
            DispatchQueue.main.async {
                importOrphansMessage = message
                showingImportOrphansResult = true
                folderViewModel.reloadSessions()
            }
        }
    }

    private func removeDuplicateSessions() {
        DispatchQueue.global(qos: .userInitiated).async {
            let jsonRemoved = StorageService.shared.removeDuplicateSessionsByAudioFiles()
            DispatchQueue.main.async {
                let swiftRemoved = SwiftDataService.shared.removeDuplicateSessionsByAudioFiles()
                let totalRemoved = jsonRemoved + swiftRemoved
                if totalRemoved > 0 {
                    dedupeMessage = "Removed \(totalRemoved) duplicate session(s)."
                } else {
                    dedupeMessage = "No duplicates found."
                }
                showingDedupeResult = true
                folderViewModel.reloadSessions()
            }
        }
    }

    /// Sessions filtered by folder/label selection and search (uses SDSession metadata)
    private var filteredSessionMetadata: [SDSession] {
        var sessions = folderViewModel.filteredSessionMetadata

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            sessions = sessions.filter { session in
                session.displayTitle.lowercased().contains(query) ||
                session.searchableText.lowercased().contains(query) ||
                session.speakerNames.lowercased().contains(query)
            }
        }

        return sessions
    }

    private func binding(for session: RecordingSession) -> Binding<RecordingSession> {
        Binding(
            get: {
                // Return the selectedSession if it matches (most up-to-date)
                if let selected = selectedSession, selected.id == session.id {
                    return selected
                }
                // Otherwise try to read from cache (no side effects)
                return folderViewModel.cachedSession(id: session.id) ?? session
            },
            set: { newValue in
                DispatchQueue.main.async {
                    // Save to SwiftData via repository
                    SwiftDataService.shared.updateSession(newValue)
                    // Update our local selection
                    selectedSession = newValue
                    // Update the cache in folderViewModel
                    folderViewModel.updateSessionInCache(newValue)
                }
            }
        )
    }

    /// Delete a session from both JSON storage and SwiftData
    private func deleteSession(_ id: UUID) {
        // Delete from JSON storage
        StorageService.shared.deleteSession(id)
        // Delete from SwiftData
        SwiftDataService.shared.deleteSession(id: id)
        // Clear from repository cache
        sessionRepository.clearSession(id: id)
        // Deselect if this was the selected session
        if selectedSessionID == id {
            selectedSessionID = nil
            selectedSession = nil
        }
    }
}

// MARK: - Sessions List View (Lazy Loading)

struct SessionsListView: View {
    @ObservedObject var repository: SessionRepository
    @Binding var selectedSessionID: UUID?
    @Binding var searchText: String
    let onDelete: (UUID) -> Void
    @ObservedObject var folderViewModel: FolderTreeViewModel

    @State private var searchDebouncer = Debouncer(delay: 0.3)
    @State private var visibleSessions: Set<UUID> = []
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and count
            HStack {
                Text(headerTitle)
                    .font(.headline)
                Spacer()
                if repository.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }
                Text("\(repository.totalCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sessions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in
                        searchDebouncer.debounce {
                            Task {
                                await updateSearch(query: newValue)
                            }
                        }
                    }
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        Task {
                            await updateSearch(query: "")
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if repository.sessions.isEmpty && !repository.isLoading {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(repository.sessions.enumerated()), id: \.element.id) { index, session in
                            SessionRowFromMetadata(
                                session: session,
                                folderViewModel: folderViewModel
                            )
                            .tag(session.id)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geo.frame(in: .named("scroll")).minY
                                    )
                                }
                            )
                            .onAppear {
                                visibleSessions.insert(session.id)
                                
                                // Load next page if approaching end (last 10 items)
                                if index >= repository.sessions.count - 10 {
                                    Task {
                                        await repository.loadNextPage()
                                    }
                                }
                                
                                // Prefetch transcripts for upcoming items (10-item preload threshold)
                                if index >= 10 {
                                    let prefetchStart = max(0, index - 10)
                                    let prefetchEnd = min(index + 10, repository.sessions.count)
                                    let upcomingSessions = Array(repository.sessions[prefetchStart..<prefetchEnd]).map { $0.id }
                                    Task {
                                        await repository.prefetchTranscripts(for: upcomingSessions)
                                    }
                                }
                            }
                            .onDisappear {
                                visibleSessions.remove(session.id)
                            }
                            .contextMenu {
                                sessionContextMenu(for: session)
                            }
                        }

                        // Loading indicator at bottom
                        if repository.isLoading && repository.hasMorePages {
                            ProgressView()
                                .padding()
                        }
                        
                        // End of list indicator
                        if !repository.hasMorePages && !repository.sessions.isEmpty {
                            Text("All sessions loaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
        }
        .onAppear {
            Task {
                let startTime = CFAbsoluteTimeGetCurrent()
                await repository.loadFirstPage()
                let loadTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                os_log("📊 SessionsView initial load: %.1fms", type: .info, loadTime)
            }
        }
        .onChange(of: folderViewModel.selectedFolderID) { _, newID in
            Task {
                await repository.setFilter(
                    folderID: newID,
                    labelID: folderViewModel.selectedLabelID,
                    searchQuery: searchText
                )
            }
        }
        .onChange(of: folderViewModel.selectedLabelID) { _, newID in
            Task {
                await repository.setFilter(
                    folderID: folderViewModel.selectedFolderID,
                    labelID: newID,
                    searchQuery: searchText
                )
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No sessions")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(emptyStateMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func sessionContextMenu(for session: SDSession) -> some View {
        Menu("Move to...") {
            ForEach(folderViewModel.rootFolders) { folder in
                FolderMenuItemForMetadata(
                    folder: folder,
                    folderViewModel: folderViewModel,
                    sessionID: session.id
                )
            }
        }

        Menu("Labels") {
            ForEach(folderViewModel.labels.sorted) { label in
                Button(action: {
                    folderViewModel.toggleLabel(label.id, for: session.id)
                }) {
                    HStack {
                        Circle()
                            .fill(Color(hex: label.color) ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(label.name)
                        if session.labelIDs.contains(label.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            onDelete(session.id)
            if selectedSessionID == session.id {
                selectedSessionID = nil
            }
        }
    }

    private var headerTitle: String {
        if let labelID = folderViewModel.selectedLabelID,
           let label = folderViewModel.label(withID: labelID) {
            return label.name
        }
        if let folderID = folderViewModel.selectedFolderID,
           let folder = folderViewModel.folder(withID: folderID) {
            return folder.name
        }
        return "All Sessions"
    }

    private var emptyStateMessage: String {
        if folderViewModel.selectedLabelID != nil {
            return "No sessions have this label"
        }
        if folderViewModel.selectedFolderID == Folder.inboxID {
            return "Start a new session to record meetings or calls"
        }
        return "Move sessions here from the Inbox"
    }

    private func updateSearch(query: String) async {
        await repository.setFilter(
            folderID: folderViewModel.selectedFolderID,
            labelID: folderViewModel.selectedLabelID,
            searchQuery: query
        )
    }
}

// MARK: - Visibility Preference Key

struct VisibleItemPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID?] = []
    static func reduce(value: inout [UUID?], nextValue: () -> [UUID?]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Folder Menu Item (Recursive)

struct FolderMenuItem: View {
    let folder: Folder
    @ObservedObject var folderViewModel: FolderTreeViewModel
    let sessionID: UUID

    var body: some View {
        let children = folderViewModel.children(of: folder.id)

        if children.isEmpty {
            Button(action: {
                folderViewModel.moveSession(sessionID, to: folder.isInbox ? nil : folder.id)
            }) {
                Label(folder.name, systemImage: folder.icon)
            }
        } else {
            Menu {
                Button("Move here") {
                    folderViewModel.moveSession(sessionID, to: folder.isInbox ? nil : folder.id)
                }
                Divider()
                ForEach(children) { child in
                    FolderMenuItem(
                        folder: child,
                        folderViewModel: folderViewModel,
                        sessionID: sessionID
                    )
                }
            } label: {
                Label(folder.name, systemImage: folder.icon)
            }
        }
    }
}

// MARK: - Folder Menu Item for Metadata (Recursive)

struct FolderMenuItemForMetadata: View {
    let folder: Folder
    @ObservedObject var folderViewModel: FolderTreeViewModel
    let sessionID: UUID

    var body: some View {
        let children = folderViewModel.children(of: folder.id)

        if children.isEmpty {
            Button(action: {
                folderViewModel.moveSession(sessionID, to: folder.isInbox ? nil : folder.id)
            }) {
                Label(folder.name, systemImage: folder.icon)
            }
        } else {
            Menu {
                Button("Move here") {
                    folderViewModel.moveSession(sessionID, to: folder.isInbox ? nil : folder.id)
                }
                Divider()
                ForEach(children) { child in
                    FolderMenuItemForMetadata(
                        folder: child,
                        folderViewModel: folderViewModel,
                        sessionID: sessionID
                    )
                }
            } label: {
                Label(folder.name, systemImage: folder.icon)
            }
        }
    }
}

// MARK: - Session Row From Metadata (Lightweight)

struct SessionRowFromMetadata: View {
    let session: SDSession
    @ObservedObject var folderViewModel: FolderTreeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Date inline with title area
                    Text(session.formattedStartDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 4)

                // AI suggestion indicator
                VStack(spacing: 4) {
                    if session.aiSuggestedFolderID != nil && !session.isClassified {
                        Image(systemName: "sparkles")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .help("AI has suggested a folder for this session")
                    }
                }
            }

            // Metadata - compact row
            HStack(spacing: 8) {
                // Duration
                Label(session.formattedDuration, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .labelStyle(.titleAndIcon)

                // Speakers count
                if session.speakerCount > 0 {
                    Label("\(session.speakerCount)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                Spacer()
            }

            // Labels badges
            if !session.labelIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(session.labelIDs, id: \.self) { labelID in
                            if let label = folderViewModel.label(withID: labelID) {
                                LabelBadge(label: label)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .draggable(SessionDragItem(sessionID: session.id)) {
            // Drag preview
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                Text(session.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .shadow(radius: 4)
        }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: RecordingSession
    @ObservedObject var folderViewModel: FolderTreeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row - indicators on a separate line if needed
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Date inline with title area
                    Text(session.formattedStartDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 4)

                // Status indicators in a compact column
                VStack(spacing: 4) {
                    if session.isRecording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }

                    // AI suggestion indicator
                    if session.aiSuggestedFolderID != nil && !session.isClassified {
                        Image(systemName: "sparkles")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .help("AI has suggested a folder for this session")
                    }
                }
            }

            // Metadata - compact row
            HStack(spacing: 8) {
                // Duration
                Label(session.formattedDuration, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .labelStyle(.titleAndIcon)

                // Speakers count (unique by name)
                if !session.speakers.isEmpty {
                    Label("\(session.uniqueSpeakerCount)", systemImage: "person.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                // Word count (only if significant)
                if session.wordCount > 0 {
                    Text("\(session.wordCount)w")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Labels badges OR Speaker colors (not both, to save space)
            if !session.labelIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(session.labelIDs, id: \.self) { labelID in
                            if let label = folderViewModel.label(withID: labelID) {
                                LabelBadge(label: label)
                            }
                        }
                    }
                }
            } else if !session.speakers.isEmpty {
                // Show unique speaker colors (group by name)
                let uniqueSpeakers = Dictionary(grouping: session.speakers, by: { $0.name ?? $0.displayName })
                    .compactMap { $0.value.first }
                    .sorted { $0.id < $1.id }
                HStack(spacing: 4) {
                    ForEach(uniqueSpeakers.prefix(5)) { speaker in
                        Circle()
                            .fill(Color(hex: speaker.color) ?? .gray)
                            .frame(width: 10, height: 10)
                    }
                    if uniqueSpeakers.count > 5 {
                        Text("+\(uniqueSpeakers.count - 5)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .draggable(SessionDragItem(sessionID: session.id)) {
            // Drag preview
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                Text(session.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .shadow(radius: 4)
        }
    }
}

// MARK: - Label Badge

struct LabelBadge: View {
    let label: SessionLabel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: label.color) ?? .gray)
                .frame(width: 6, height: 6)

            Text(label.name)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(hex: label.color)?.opacity(0.15) ?? Color.gray.opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Empty Session Detail View

struct EmptySessionDetailView: View {
    let onNewSession: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Select a session")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Choose a session from the list to view its transcript and speakers")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button(action: onNewSession) {
                Label("Start New Session", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Sessions View Model

class SessionsViewModel: ObservableObject {
    @Published var sessions: [RecordingSession] = []
    
    private let storage = StorageService.shared
    private var saveTask: Task<Void, Never>?
    private var pendingSessions: [RecordingSession]?
    
    func loadSessions() {
        sessions = storage.loadSessions()
        pendingSessions = nil
    }


    func filteredSessions(searchText: String) -> [RecordingSession] {
        guard !searchText.isEmpty else {
            return sessions.sorted { $0.startDate > $1.startDate }
        }

        let query = searchText.lowercased()
        return sessions.filter { session in
            session.displayTitle.lowercased().contains(query) ||
            session.fullTranscript.lowercased().contains(query) ||
            session.speakers.contains { $0.displayName.lowercased().contains(query) }
        }.sorted { $0.startDate > $1.startDate }
    }

    func deleteSession(_ id: UUID) {
        storage.deleteSession(id)
        sessions.removeAll { $0.id == id }
    }

    func updateSession(_ session: RecordingSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
        pendingSessions = sessions
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [storage] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let snapshot = pendingSessions {
                    storage.saveSessions(snapshot)
                    pendingSessions = nil
                }
            }
        }
    }

    /// Import an audio file and create a new session from it
    func importAudioFile(from sourceURL: URL, completion: @escaping (RecordingSession?, String?) -> Void) {
        // Request access to the file (security scoped)
        guard sourceURL.startAccessingSecurityScopedResource() else {
            completion(nil, "Cannot access the selected file. Please try again.")
            return
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let fileManager = FileManager.default

        // Ensure sessions folder exists
        let sessionsFolder = RecordingSession.sessionsFolder
        if !fileManager.fileExists(atPath: sessionsFolder.path) {
            do {
                try fileManager.createDirectory(at: sessionsFolder, withIntermediateDirectories: true)
            } catch {
                completion(nil, "Could not create sessions folder: \(error.localizedDescription)")
                return
            }
        }

        // Generate unique filename with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
        let originalExtension = sourceURL.pathExtension.lowercased()
        let newFileName = "imported_\(timestamp).\(originalExtension)"
        let destinationURL = sessionsFolder.appendingPathComponent(newFileName)

        // Copy the file
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            print("[SessionsViewModel] Imported audio file: \(newFileName)")
        } catch {
            completion(nil, "Could not copy file: \(error.localizedDescription)")
            return
        }

        // Verify the copied file exists and has content
        guard fileManager.fileExists(atPath: destinationURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
              let fileSize = attributes[.size] as? Int64,
              fileSize > 1000 else {
            try? fileManager.removeItem(at: destinationURL)
            completion(nil, "Imported file appears to be empty or corrupted")
            return
        }

        // Get audio duration
        var audioDuration: TimeInterval = 0
        let ext = destinationURL.pathExtension.lowercased()

        // For WebM/OGG, use ffprobe since AVFoundation doesn't support them
        if ext == "webm" || ext == "ogg" {
            audioDuration = Self.getFFprobeDuration(url: destinationURL) ?? 0
        } else {
            // Try AVURLAsset for other formats
            let asset = AVURLAsset(url: destinationURL)
            let duration = CMTimeGetSeconds(asset.duration)
            if !duration.isNaN && duration > 0 {
                audioDuration = duration
            } else {
                // Fallback: try AVAudioFile
                if let audioSource = try? AVAudioFile(forReading: destinationURL) {
                    audioDuration = Double(audioSource.length) / audioSource.fileFormat.sampleRate
                }
            }
        }

        if audioDuration > 0 {
            print("[SessionsViewModel] Audio duration: \(String(format: "%.1f", audioDuration))s")
        } else {
            print("[SessionsViewModel] Could not determine audio duration")
        }

        // Create a new session with the imported audio
        // New sessions go to INBOX (folderID = nil)
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(audioDuration)

        let session = RecordingSession(
            id: UUID(),
            startDate: startDate,
            endDate: endDate,
            transcriptSegments: [],
            speakers: [],
            audioSource: .systemAudio,  // Single file treated as system audio
            title: "Imported: \(sourceURL.deletingPathExtension().lastPathComponent)",
            audioFileName: nil,
            micAudioFileName: nil,
            systemAudioFileName: newFileName,  // Store as system audio
            sessionType: .meeting,
            summary: nil,
            folderID: nil,  // INBOX
            labelIDs: [],
            isClassified: false
        )

        // Save the session
        var allSessions = storage.loadSessions()
        allSessions.append(session)
        storage.saveSessions(allSessions)

        // Reload and return
        loadSessions()
        print("[SessionsViewModel] Created session from imported audio: \(session.displayTitle)")
        completion(session, nil)
    }

    /// Get audio duration using ffprobe (for WebM and other formats AVFoundation doesn't support)
    private static func getFFprobeDuration(url: URL) -> Double? {
        // Find ffprobe
        guard let ffprobePath = findFFprobe() else {
            print("[SessionsViewModel] ffprobe not found")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let duration = Double(output), duration > 0 {
                return duration
            }
        } catch {
            print("[SessionsViewModel] ffprobe failed: \(error.localizedDescription)")
        }

        return nil
    }

    /// Find ffprobe binary
    private static func findFFprobe() -> String? {
        let fm = FileManager.default

        // 1. Check for bundled ffprobe in app Resources
        if let bundledPath = Bundle.main.path(forResource: "ffprobe", ofType: nil),
           fm.fileExists(atPath: bundledPath) {
            return bundledPath
        }

        // 2. Check common system paths
        let systemPaths = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        for path in systemPaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }
}

#Preview {
    SessionsView()
        .environmentObject(AppState.shared)
        .frame(width: 1100, height: 700)
}
