import Foundation

class StorageService {
    static let shared = StorageService()

    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default

    private let settingsKey = "CoriusVoiceSettings"
    private let dictionaryKey = "CoriusVoiceDictionary"
    private let snippetsKey = "CoriusVoiceSnippets"

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var appDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("CoriusVoice")
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private var transcriptionsURL: URL {
        appDirectory.appendingPathComponent("transcriptions.json")
    }

    private var notesURL: URL {
        appDirectory.appendingPathComponent("notes.json")
    }

    private init() {}

    // MARK: - Settings

    var settings: AppSettings {
        get {
            guard let data = userDefaults.data(forKey: settingsKey),
                  let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
                return AppSettings()
            }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: settingsKey)
            }
        }
    }

    // MARK: - Dictionary Entries

    var dictionaryEntries: [DictionaryEntry] {
        get {
            guard let data = userDefaults.data(forKey: dictionaryKey),
                  let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else {
                return []
            }
            return entries
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: dictionaryKey)
            }
        }
    }

    // MARK: - Snippets

    var snippets: [Snippet] {
        get {
            guard let data = userDefaults.data(forKey: snippetsKey),
                  let snippets = try? JSONDecoder().decode([Snippet].self, from: data) else {
                return []
            }
            return snippets
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: snippetsKey)
            }
        }
    }

    // MARK: - Transcriptions (File-based)

    func loadTranscriptions() -> [Transcription] {
        guard fileManager.fileExists(atPath: transcriptionsURL.path),
              let data = try? Data(contentsOf: transcriptionsURL),
              let transcriptions = try? JSONDecoder().decode([Transcription].self, from: data) else {
            return []
        }
        return transcriptions
    }

    func saveTranscriptions(_ transcriptions: [Transcription]) {
        if let data = try? JSONEncoder().encode(transcriptions) {
            try? data.write(to: transcriptionsURL)
        }
    }

    // MARK: - Notes (File-based)

    func loadNotes() -> [Note] {
        guard fileManager.fileExists(atPath: notesURL.path),
              let data = try? Data(contentsOf: notesURL),
              let notes = try? JSONDecoder().decode([Note].self, from: data) else {
            return []
        }
        return notes
    }

    func saveNotes(_ notes: [Note]) {
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: notesURL)
        }
    }

    // MARK: - Data Management

    func clearAllData() {
        userDefaults.removeObject(forKey: settingsKey)
        userDefaults.removeObject(forKey: dictionaryKey)
        userDefaults.removeObject(forKey: snippetsKey)
        try? fileManager.removeItem(at: transcriptionsURL)
        try? fileManager.removeItem(at: notesURL)
    }

    func exportData() -> Data? {
        let exportData = ExportData(
            settings: settings,
            transcriptions: loadTranscriptions(),
            notes: loadNotes(),
            dictionaryEntries: dictionaryEntries,
            snippets: snippets
        )
        return try? JSONEncoder().encode(exportData)
    }

    func importData(_ data: Data) -> Bool {
        guard let importData = try? JSONDecoder().decode(ExportData.self, from: data) else {
            return false
        }

        settings = importData.settings
        saveTranscriptions(importData.transcriptions)
        saveNotes(importData.notes)
        dictionaryEntries = importData.dictionaryEntries
        snippets = importData.snippets

        return true
    }
}

struct ExportData: Codable {
    let settings: AppSettings
    let transcriptions: [Transcription]
    let notes: [Note]
    let dictionaryEntries: [DictionaryEntry]
    let snippets: [Snippet]
}
