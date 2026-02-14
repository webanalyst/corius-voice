import Foundation
import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Overview Stats
    @Published var totalChats: Int = 0
    @Published var totalWords: Int = 0
    @Published var avgWPM: Double = 0
    @Published var timeSavedMinutes: Double = 0
    
    // Streaks
    @Published var currentStreak: Int = 0
    @Published var longestStreak: Int = 0
    
    // Personal Records
    @Published var bestWPM: Int = 0
    @Published var mostWordsInDay: Int = 0
    @Published var longestSessionDuration: TimeInterval = 0
    
    // Goals (Hardcoded targets for now, could be settings later)
    @Published var dailyWordCount: Int = 0
    @Published var dailyWordGoal: Int = 500
    @Published var weeklyWordCount: Int = 0
    @Published var weeklyWordGoal: Int = 2500
    
    // Charts Data
    @Published var activityHeatmap: [Date: Int] = [:] // Date -> Count (intensity)
    @Published var hourlyActivity: [Int: Int] = [:]   // Hour (0-23) -> Count
    @Published var wordsOverTime: [(date: Date, count: Int)] = []
    
    // MARK: - Dependencies
    private var storageService = StorageService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Listen for changes in sessions (if StorageService/AppState publishes them)
        // For now, we'll manually refresh on appear or when notified
        NotificationCenter.default.publisher(for: .sessionTranscriptionCompleted)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshStats() }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .recordingDidFinish)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshStats() }
            }
            .store(in: &cancellables)
            
        refreshStats()
    }
    
    func refreshStats() {
        let sessions = storageService.loadSessions()
        
        calculateOverview(sessions: sessions)
        calculateStreaks(sessions: sessions)
        calculateRecords(sessions: sessions)
        calculateGoals(sessions: sessions)
        calculateCharts(sessions: sessions)
    }
    
    // MARK: - Calculations
    
    private func calculateOverview(sessions: [RecordingSession]) {
        self.totalChats = sessions.count
        
        let validSessions = sessions.filter { $0.wordCount > 0 && $0.duration > 0 }
        self.totalWords = sessions.reduce(0) { $0 + $1.wordCount }
        
        // Avg WPM: Average of individual session WPMs
        let totalWPM = validSessions.reduce(0.0) { result, session in
            let minutes = session.duration / 60.0
            return result + (Double(session.wordCount) / max(minutes, 0.1))
        }
        self.avgWPM = validSessions.isEmpty ? 0 : totalWPM / Double(validSessions.count)
        
        // Time Saved: (Total Words / 40 WPM typing speed) - Actual speaking time
        // Actually, "Time Saved" usually means "Time I didn't have to type".
        // Let's use: (Words / 40) - (Duration / 60).
        // If speaking took longer, it's 0.
        let typingTimeMinutes = Double(totalWords) / 40.0
        let speakingTimeMinutes = sessions.reduce(0.0) { $0 + $1.duration } / 60.0
        self.timeSavedMinutes = max(0, typingTimeMinutes - speakingTimeMinutes)
    }
    
    private func calculateStreaks(sessions: [RecordingSession]) {
        guard !sessions.isEmpty else {
            currentStreak = 0
            longestStreak = 0
            return
        }
        
        let calendar = Calendar.current
        
        // Get unique dates with sessions
        let dates = Set(sessions.map { calendar.startOfDay(for: $0.startDate) })
        let sortedDates = dates.sorted(by: >)
        
        // Current Streak
        var current = 0
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        // Check if we have a session today or yesterday to start the streak
        if dates.contains(today) {
            current = 1
            var checkDate = yesterday
            while dates.contains(checkDate) {
                current += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            }
        } else if dates.contains(yesterday) {
            current = 1 // Streak is active from yesterday
            var checkDate = calendar.date(byAdding: .day, value: -1, to: yesterday)!
            while dates.contains(checkDate) {
                current += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            }
        } else {
            current = 0
        }
        self.currentStreak = current
        
        // Longest Streak
        var maxStreak = 0
        var tempStreak = 0
        var previousDate: Date?
        
        // Iterate form oldest to newest for longest streak
        let ascendingDates = sortedDates.reversed()
        
        for date in ascendingDates {
            if let prev = previousDate {
                let diff = calendar.dateComponents([.day], from: prev, to: date).day ?? 0
                if diff == 1 {
                    tempStreak += 1
                } else {
                    maxStreak = max(maxStreak, tempStreak)
                    tempStreak = 1
                }
            } else {
                tempStreak = 1
            }
            previousDate = date
        }
        maxStreak = max(maxStreak, tempStreak)
        self.longestStreak = maxStreak
    }
    
    private func calculateRecords(sessions: [RecordingSession]) {
        let validSessions = sessions.filter { $0.wordCount > 10 && $0.duration > 5 } // Filter simple tests
        
        // Best WPM
        let maxWPM = validSessions.map { session -> Double in
            let minutes = session.duration / 60.0
            return Double(session.wordCount) / max(minutes, 0.1)
        }.max() ?? 0
        self.bestWPM = Int(maxWPM)
        
        // Longest Session
        self.longestSessionDuration = sessions.map { $0.duration }.max() ?? 0
        
        // Most Words / Day
        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startDate) }
        let maxDailyWords = groupedByDay.values.map { daysSessions in
            daysSessions.reduce(0) { $0 + $1.wordCount }
        }.max() ?? 0
        self.mostWordsInDay = maxDailyWords
    }
    
    private func calculateGoals(sessions: [RecordingSession]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Daily
        let todaySessions = sessions.filter { calendar.isDateInToday($0.startDate) }
        self.dailyWordCount = todaySessions.reduce(0) { $0 + $1.wordCount }
        
        // Weekly (Start of week is Monday usually, let's assume default locale)
        // Find start of current week
        let weekOfYear = calendar.component(.weekOfYear, from: today)
        let weeklySessions = sessions.filter {
            calendar.component(.weekOfYear, from: $0.startDate) == weekOfYear
        }
        self.weeklyWordCount = weeklySessions.reduce(0) { $0 + $1.wordCount }
    }
    
    private func calculateCharts(sessions: [RecordingSession]) {
        let calendar = Calendar.current
        
        // 1. Hourly Activity (0-23)
        var hourlyCounts = [Int: Int]()
        // Initialize with 0s
        for i in 0...23 { hourlyCounts[i] = 0 }
        
        for session in sessions {
            let hour = calendar.component(.hour, from: session.startDate)
            hourlyCounts[hour, default: 0] += 1
        }
        self.hourlyActivity = hourlyCounts
        
        // 2. Activity Heatmap (Last 365 days?) - Actually just all data but view handles limiting
        var heatmap = [Date: Int]()
        for session in sessions {
            let day = calendar.startOfDay(for: session.startDate)
            heatmap[day, default: 0] += session.wordCount // We map INTENSITY (words), or count? Image looks like count squares. Let's do count.
            // Actually GitHub is commit count. Here maybe "sessions" count.
            // Let's increment by 1 for simplicity first.
             // heatmap[day, default: 0] += 1
        }
        // Actually, let's do simple session count for now.
        // Or maybe word count is more interesting? "Activity" usually implies "doing something".
        // Let's stick to session count.
         sessions.forEach {
            let day = calendar.startOfDay(for: $0.startDate)
            heatmap[day, default: 0] += 1
        }
        self.activityHeatmap = heatmap
        
        // 3. Words Over Time (Trend) - Last 14 days maybe? Or all time buckets?
        // Image shows a line chart. Let's do last 30 days.
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        let recentSessions = sessions.filter { $0.startDate >= thirtyDaysAgo }
        
        let wordsByDay = Dictionary(grouping: recentSessions) { calendar.startOfDay(for: $0.startDate) }
        
        var trendData: [(date: Date, count: Int)] = []
        // Fill in gaps
        for i in 0..<30 {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date())?.startOfDay {
                let count = wordsByDay[date]?.reduce(0) { $0 + $1.wordCount } ?? 0
                trendData.append((date: date, count: count))
            }
        }
        // sort by date ascending
        self.wordsOverTime = trendData.sorted { $0.date < $1.date }
    }
    
    private func formattedDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? ""
    }
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
