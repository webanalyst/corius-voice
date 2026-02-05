import Foundation
import SwiftUI

// MARK: - Known Speaker (Persistent)

/// A speaker in the user's library that can be reused across sessions
struct KnownSpeaker: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var color: String  // Hex color
    var notes: String?  // Optional notes about this speaker
    var voiceCharacteristics: String?  // User can describe voice for manual matching
    let createdAt: Date
    var lastUsedAt: Date?
    var usageCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        color: String? = nil,
        notes: String? = nil,
        voiceCharacteristics: String? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color ?? KnownSpeaker.randomColor()
        self.notes = notes
        self.voiceCharacteristics = voiceCharacteristics
        self.createdAt = Date()
        self.lastUsedAt = nil
        self.usageCount = 0
    }

    var displayColor: Color {
        Color(hex: color) ?? .blue
    }

    mutating func markUsed() {
        lastUsedAt = Date()
        usageCount += 1
    }

    // MARK: - Default Colors

    static let defaultColors = [
        "#3B82F6",  // Blue
        "#10B981",  // Green
        "#F59E0B",  // Amber
        "#EF4444",  // Red
        "#8B5CF6",  // Purple
        "#EC4899",  // Pink
        "#06B6D4",  // Cyan
        "#F97316",  // Orange
        "#6366F1",  // Indigo
        "#84CC16",  // Lime
    ]

    static func randomColor() -> String {
        defaultColors.randomElement() ?? "#3B82F6"
    }

    static func colorForIndex(_ index: Int) -> String {
        defaultColors[index % defaultColors.count]
    }
}

// MARK: - Speaker Assignment

/// Links a Deepgram speaker ID (0, 1, 2...) to a known speaker in a session
struct SpeakerAssignment: Codable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let deepgramSpeakerID: Int  // The ID from Deepgram (0, 1, 2...)
    var knownSpeakerID: UUID?  // Link to KnownSpeaker, nil if unassigned
    var temporaryName: String?  // Name used if not linked to known speaker
    var temporaryColor: String  // Color used if not linked

    init(
        sessionID: UUID,
        deepgramSpeakerID: Int,
        knownSpeakerID: UUID? = nil,
        temporaryName: String? = nil
    ) {
        self.id = UUID()
        self.sessionID = sessionID
        self.deepgramSpeakerID = deepgramSpeakerID
        self.knownSpeakerID = knownSpeakerID
        self.temporaryName = temporaryName
        self.temporaryColor = KnownSpeaker.colorForIndex(deepgramSpeakerID)
    }

    var displayName: String {
        temporaryName ?? "Speaker \(deepgramSpeakerID + 1)"
    }
}

// MARK: - Speaker Library Manager

class SpeakerLibrary: ObservableObject {
    static let shared = SpeakerLibrary()

    @Published var speakers: [KnownSpeaker] = []

    private let storageKey = "CoriusVoiceSpeakerLibrary"

    private init() {
        loadSpeakers()
    }

    // MARK: - CRUD Operations

    func addSpeaker(name: String, color: String? = nil, notes: String? = nil) -> KnownSpeaker {
        let speaker = KnownSpeaker(name: name, color: color, notes: notes)
        speakers.append(speaker)
        saveSpeakers()
        return speaker
    }

    func updateSpeaker(_ speaker: KnownSpeaker) {
        if let index = speakers.firstIndex(where: { $0.id == speaker.id }) {
            speakers[index] = speaker
            saveSpeakers()
        }
    }

    func deleteSpeaker(_ speakerID: UUID) {
        speakers.removeAll { $0.id == speakerID }
        saveSpeakers()
    }

    func getSpeaker(byID id: UUID) -> KnownSpeaker? {
        speakers.first { $0.id == id }
    }

    func markSpeakerUsed(_ speakerID: UUID) {
        if let index = speakers.firstIndex(where: { $0.id == speakerID }) {
            speakers[index].markUsed()
            saveSpeakers()
        }
    }

    // MARK: - Search & Suggestions

    /// Get speakers sorted by most recently used
    var recentSpeakers: [KnownSpeaker] {
        speakers
            .filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }

    /// Get speakers sorted by most frequently used
    var frequentSpeakers: [KnownSpeaker] {
        speakers.sorted { $0.usageCount > $1.usageCount }
    }

    /// Search speakers by name
    func searchSpeakers(query: String) -> [KnownSpeaker] {
        guard !query.isEmpty else { return speakers }
        let lowercaseQuery = query.lowercased()
        return speakers.filter {
            $0.name.lowercased().contains(lowercaseQuery) ||
            ($0.notes?.lowercased().contains(lowercaseQuery) ?? false)
        }
    }

    /// Get suggested speakers based on context
    func suggestedSpeakers(limit: Int = 5) -> [KnownSpeaker] {
        // Prioritize recent, then frequent
        var suggestions: [KnownSpeaker] = []

        // Add recent speakers first
        for speaker in recentSpeakers {
            if suggestions.count >= limit { break }
            if !suggestions.contains(where: { $0.id == speaker.id }) {
                suggestions.append(speaker)
            }
        }

        // Fill with frequent speakers
        for speaker in frequentSpeakers {
            if suggestions.count >= limit { break }
            if !suggestions.contains(where: { $0.id == speaker.id }) {
                suggestions.append(speaker)
            }
        }

        return suggestions
    }

    // MARK: - Persistence

    private func loadSpeakers() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([KnownSpeaker].self, from: data) else {
            speakers = []
            return
        }
        speakers = decoded
    }

    private func saveSpeakers() {
        if let encoded = try? JSONEncoder().encode(speakers) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    // MARK: - Quick Add from Session

    /// Create a new speaker from a session's temporary speaker
    func createSpeakerFromSession(name: String, color: String) -> KnownSpeaker {
        let speaker = KnownSpeaker(name: name, color: color)
        speakers.append(speaker)
        saveSpeakers()
        return speaker
    }
}
