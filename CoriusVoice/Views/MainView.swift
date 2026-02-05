import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case workspace = "Workspace"
    case notes = "Notes"
    case sessions = "Sessions"
    case speakers = "Speakers"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .workspace: return "rectangle.split.3x1.fill"
        case .notes: return "note.text"
        case .sessions: return "waveform.circle"
        case .speakers: return "person.2.fill"
        case .dictionary: return "text.book.closed.fill"
        case .snippets: return "text.insert"
        case .settings: return "gearshape.fill"
        }
    }

    var description: String {
        switch self {
        case .home: return "Transcription history"
        case .workspace: return "Kanban & docs"
        case .notes: return "Voice notes"
        case .sessions: return "Recording sessions"
        case .speakers: return "Speaker library"
        case .dictionary: return "Word replacements"
        case .snippets: return "Text shortcuts"
        case .settings: return "App settings"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedItem: NavigationItem = .home

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(selectedItem: $selectedItem)
            } detail: {
                Group {
                    switch selectedItem {
                    case .home:
                        HomeView()
                    case .workspace:
                        WorkspaceView()
                    case .notes:
                        NotesView()
                    case .sessions:
                        SessionsView()
                    case .speakers:
                        SpeakerLibraryView()
                    case .dictionary:
                        DictionaryView()
                    case .snippets:
                        SnippetsView()
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .navigationSplitViewStyle(.balanced)

            if appState.isWhisperPreloading {
                WhisperLoadingOverlay(
                    title: appState.whisperLoadingTitle,
                    detail: appState.whisperLoadingDetail,
                    progress: appState.whisperLoadingProgress
                )
            }
        }
    }
}

struct WhisperLoadingOverlay: View {
    let title: String
    let detail: String
    let progress: Double?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("Loading Whisper")
                    .font(.headline)

                if !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }

                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 220)
                } else {
                    ProgressView()
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .shadow(radius: 12)
        }
    }
}

struct SidebarView: View {
    @Binding var selectedItem: NavigationItem
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // App header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "waveform.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Corius Voice")
                        .font(.headline)
                    Text("Fn-ready")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            // Navigation items
            List(selection: $selectedItem) {
                Section("Main") {
                    ForEach([NavigationItem.home, .workspace, .notes]) { item in
                        NavigationLink(value: item) {
                            SidebarItemView(item: item)
                        }
                    }
                }

                Section("Sessions") {
                    ForEach([NavigationItem.sessions, .speakers]) { item in
                        NavigationLink(value: item) {
                            SidebarItemView(item: item)
                        }
                    }
                }

                Section("Text") {
                    ForEach([NavigationItem.dictionary, .snippets]) { item in
                        NavigationLink(value: item) {
                            SidebarItemView(item: item)
                        }
                    }
                }

                Section("App") {
                    NavigationLink(value: NavigationItem.settings) {
                        SidebarItemView(item: .settings)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.controlBackgroundColor))

            Spacer()

            Divider()

            // Recording status
            RecordingStatusView()
                .padding()
        }
        .frame(minWidth: 220)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct SidebarItemView: View {
    let item: NavigationItem

    var body: some View {
        HStack(spacing: 10) {
            WorkspaceIconView(name: item.icon)
                .frame(width: 20)
            Text(item.rawValue)
                .fontWeight(.medium)
            Spacer()
            Text(item.description)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct RecordingStatusView: View {
    @EnvironmentObject var appState: AppState
    
    private var statusText: String {
        if appState.isProcessing { return "Processing..." }
        if appState.isRecording { return "Recording" }
        if appState.fnKeyPressed { return "Fn detected" }
        return "Ready"
    }
    
    private var statusColor: Color {
        if appState.isProcessing { return .orange }
        if appState.isRecording { return .red }
        if appState.fnKeyPressed { return .green }
        return .secondary
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.14))
                        .frame(width: 32, height: 32)

                    if appState.isRecording {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                    } else if appState.fnKeyPressed {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundColor(statusColor)
                    } else {
                        Image(systemName: "keyboard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)

                    Text(appState.isRecording ? "Release Fn to stop" : "Hold Fn/Globe to record")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if appState.isRecording {
                    MiniWaveform()
                        .frame(width: 30, height: 16)
                }
            }

            // Current transcription preview
            if appState.isRecording && !appState.currentTranscription.isEmpty {
                Text(appState.currentTranscription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(statusColor.opacity(0.08))
        )
    }
}

struct MiniWaveform: View {
    @State private var levels: [CGFloat] = [0.3, 0.5, 0.4, 0.6, 0.3]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red)
                    .frame(width: 2, height: levels[index] * 14)
            }
        }
        .onAppear {
            animateLevels()
        }
    }

    private func animateLevels() {
        withAnimation(.easeInOut(duration: 0.12)) {
            levels = (0..<5).map { _ in CGFloat.random(in: 0.2...1.0) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            animateLevels()
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AppState.shared)
}
