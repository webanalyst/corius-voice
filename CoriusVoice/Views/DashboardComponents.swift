import SwiftUI
import Charts

struct StatsOverviewCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(1.0)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                Text(unit)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // .background(Color.red.opacity(0.1)) // Debug
    }
}

struct StreakCard: View {
    let currentStreak: Int
    let longestStreak: Int
    
    var body: some View {
        HStack(spacing: 16) {
            streakBox(title: "CURRENT STREAK", value: currentStreak, color: .orange)
            streakBox(title: "LONGEST STREAK", value: longestStreak, color: .secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func streakBox(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(value > 0 ? color : .secondary)
            
            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.2))
        )
    }
}

struct PersonalRecordsCard: View {
    let bestWPM: Int
    let mostWords: Int
    let longestSession: TimeInterval
    
    var body: some View {
        HStack(spacing: 0) {
            recordItem(value: "\(bestWPM)", label: "BEST WPM")
            Divider().padding(.vertical, 12)
            recordItem(value: "\(mostWords)", label: "MOST WORDS/DAY")
            Divider().padding(.vertical, 12)
            recordItem(value: formatTime(longestSession), label: "LONGEST SESSION")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func recordItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        return "\(minutes)m"
    }
}

struct DailyGoalCard: View {
    let current: Int
    let target: Int
    let title: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(current) / \(target)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(color)
                        .frame(width: min(geo.size.width, geo.size.width * CGFloat(current) / CGFloat(max(target, 1))), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Charts

struct ActivityHeatmap: View {
    // Data: Date -> Count
    // To implement a GitHub-style heatmap, we need to grid by Week (horizontal) and WeekDay (vertical)
    let data: [Date: Int]
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.fixed(10), spacing: 2), count: 52) // 52 weeks roughly
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVITY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
            }
            
            // Simplified Heatmap: Just the last 140 days (20 weeks) to fit nicely?
            // Or just a standard horizontal scrollview of blocks
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(0..<20) { weekOffset in
                        VStack(spacing: 2) {
                            ForEach(0..<7) { dayOffset in
                                // Calculate date for this cell
                                // Start from 20 weeks ago
                                if let date = dateFor(week: weekOffset, day: dayOffset) {
                                    let count = data[calendar.startOfDay(for: date)] ?? 0
                                    Rectangle()
                                        .fill(colorForCount(count))
                                        .frame(width: 10, height: 10)
                                        .cornerRadius(2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func dateFor(week: Int, day: Int) -> Date? {
        // Find start of current week
        let today = Date()
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return nil }
        
        // Go back 19 weeks (since we show 20)
        guard let startView = calendar.date(byAdding: .weekOfYear, value: -19, to: startOfWeek) else { return nil }
        
        // Add week offset and day offset
        var components = DateComponents()
        components.weekOfYear = week
        components.weekday = day + 1 // Sunday = 1
        
        // This logic is tricky. Let's simplify:
        // Just map absolute days from (Today - 140 days)
        let totalDays = (20 * 7)
        let daysAgo = totalDays - (week * 7 + day) - 1
        return calendar.date(byAdding: .day, value: -daysAgo, to: today)
    }
    
    private func colorForCount(_ count: Int) -> Color {
        if count == 0 { return Color.secondary.opacity(0.1) }
        if count < 3 { return Color.accentColor.opacity(0.3) }
        if count < 6 { return Color.accentColor.opacity(0.6) }
        return Color.accentColor
    }
}

struct HourlyActivityChart: View {
    let data: [Int: Int] // Hour -> Count
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PEAK HOURS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            Chart {
                ForEach(0..<24, id: \.self) { hour in
                    BarMark(
                        x: .value("Hour", hour),
                        y: .value("Sessions", data[hour] ?? 0)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text("\(hour):00")
                        }
                    }
                }
            }
            .frame(height: 120)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct WordsOverTimeChart: View {
    let data: [(date: Date, count: Int)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WORDS OVER TIME")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            if data.isEmpty {
                Text("No data yet")
                    .foregroundColor(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(data, id: \.date) { item in
                        AreaMark(
                            x: .value("Date", item.date),
                            y: .value("Words", item.count)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        
                        LineMark(
                            x: .value("Date", item.date),
                            y: .value("Words", item.count)
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                    }
                }
                .frame(height: 150)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }
}
