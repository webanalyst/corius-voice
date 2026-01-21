import Foundation

struct Transcription: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var text: String
    let date: Date
    var duration: TimeInterval
    var isFavorite: Bool = false
    var note: String?

    init(id: UUID = UUID(), text: String, date: Date = Date(), duration: TimeInterval = 0, isFavorite: Bool = false, note: String? = nil) {
        self.id = id
        self.text = text
        self.date = date
        self.duration = duration
        self.isFavorite = isFavorite
        self.note = note
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var preview: String {
        let maxLength = 100
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
}
