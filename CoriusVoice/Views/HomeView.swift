import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                
                // Top Stats Row
                StatsGrid(viewModel: viewModel)
                
                // Quick Actions
                quickActions
                
                // Analytics Section
                VStack(spacing: 16) {
                    StreakCard(currentStreak: viewModel.currentStreak, longestStreak: viewModel.longestStreak)
                    
                    PersonalRecordsCard(
                        bestWPM: viewModel.bestWPM,
                        mostWords: viewModel.mostWordsInDay,
                        longestSession: viewModel.longestSessionDuration
                    )
                    
                    DailyGoalCard(
                        current: viewModel.dailyWordCount,
                        target: viewModel.dailyWordGoal,
                        title: "DAILY GOAL PROGRESS",
                        color: .yellow
                    )
                    
                    ActivityHeatmap(data: viewModel.activityHeatmap)
                    
                    HourlyActivityChart(data: viewModel.hourlyActivity)
                    
                    WordsOverTimeChart(data: viewModel.wordsOverTime)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.refreshStats()
        }
    }
}

// MARK: - Sections

private extension HomeView {
    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription History")
                .font(.largeTitle).bold()
            Text("Your voice journey in numbers.")
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
    }
    
    var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK ACTIONS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            HStack(spacing: 16) {
                actionCard(
                    icon: "record.circle.fill",
                    title: "Record",
                    subtitle: "New session",
                    color: .red,
                    action: { NotificationCenter.default.post(name: .uiStartRecording, object: nil) }
                )
                actionCard(
                    icon: "note.text",
                    title: "Voice Note",
                    subtitle: "Quick idea",
                    color: .blue,
                    action: { NotificationCenter.default.post(name: .uiStartVoiceNote, object: nil) }
                )
                actionCard(
                    icon: "text.badge.plus",
                    title: "Snippet",
                    subtitle: "Add shortcut",
                    color: .orange,
                    action: { NotificationCenter.default.post(name: .uiOpenSnippets, object: nil) }
                )
            }
        }
    }

    func actionCard(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

struct StatsGrid: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
            StatsOverviewCard(
                title: "CHATS",
                value: "\(viewModel.totalChats)",
                unit: "",
                color: .primary
            )
            StatsOverviewCard(
                title: "WORDS",
                value: formatNumber(viewModel.totalWords),
                unit: "",
                color: .primary
            )
            StatsOverviewCard(
                title: "AVG WPM",
                value: "\(Int(viewModel.avgWPM))",
                unit: "",
                color: .primary
            )
            StatsOverviewCard(
                title: "MIN SAVED",
                value: String(format: "%.1f", viewModel.timeSavedMinutes),
                unit: "",
                color: .yellow
            )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor)) // Darker background to make text pop
        .cornerRadius(12)
    }
    
    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState.shared)
        .frame(width: 900, height: 800)
}
