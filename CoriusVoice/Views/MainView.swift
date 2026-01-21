import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case notes = "Notes"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .notes: return "note.text"
        case .dictionary: return "text.book.closed"
        case .snippets: return "text.insert"
        case .settings: return "gear"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedItem: NavigationItem = .home

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedItem)
        } detail: {
            Group {
                switch selectedItem {
                case .home:
                    HomeView()
                case .notes:
                    NotesView()
                case .dictionary:
                    DictionaryView()
                case .snippets:
                    SnippetsView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SidebarView: View {
    @Binding var selectedItem: NavigationItem
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $selectedItem) {
            Section("Main") {
                ForEach([NavigationItem.home, .notes]) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            }

            Section("Text") {
                ForEach([NavigationItem.dictionary, .snippets]) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            }

            Section("App") {
                NavigationLink(value: NavigationItem.settings) {
                    Label(NavigationItem.settings.rawValue, systemImage: NavigationItem.settings.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)

        // Recording status at bottom
        VStack {
            Divider()

            RecordingStatusView()
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }
}

struct RecordingStatusView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            Circle()
                .fill(appState.isRecording ? Color.red : Color.gray.opacity(0.3))
                .frame(width: 10, height: 10)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: appState.isRecording)

            Text(appState.isRecording ? "Recording..." : "Press Fn to record")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if appState.isRecording {
                Image(systemName: "waveform")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    MainView()
        .environmentObject(AppState.shared)
}
