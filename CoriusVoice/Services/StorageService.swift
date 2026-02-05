import Foundation
import AVFoundation
import CoreMedia

class StorageService {
    static let shared = StorageService()

    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default

    private let settingsKey = "CoriusVoiceSettings"
    private let dictionaryKey = "CoriusVoiceDictionary"
    private let snippetsKey = "CoriusVoiceSnippets"
    private let migrationKey = "CoriusVoiceSessionsMigrated_v2"
    private let folderMigrationKey = "CoriusVoiceFoldersMigrated_v1"

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

    private var sessionsURL: URL {
        appDirectory.appendingPathComponent("sessions.json")
    }

    private var foldersURL: URL {
        appDirectory.appendingPathComponent("folders.json")
    }

    private var labelsURL: URL {
        appDirectory.appendingPathComponent("labels.json")
    }

    // Reusable encoder/decoder with consistent date strategy
    private lazy var sessionEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private lazy var sessionDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    // Cached settings to avoid reading from UserDefaults on every audio buffer
    private var _cachedSettings: AppSettings?
    
    // Cached sessions to avoid reading from disk repeatedly
    private var _cachedSessions: [RecordingSession]?
    private var _sessionsLastModified: Date?

    private init() {
        // Load settings on init
        _cachedSettings = loadSettingsFromDisk()

        // Run migrations if needed
        migrateSessionsIfNeeded()
        migrateFoldersIfNeeded()
    }
    
    // MARK: - Session Cache Management
    
    /// Invalidate session cache (call after external modifications)
    func invalidateSessionCache() {
        _cachedSessions = nil
        _sessionsLastModified = nil
    }
    
    /// Check if sessions file was modified since last cache
    private func sessionsFileModified() -> Bool {
        guard let lastMod = _sessionsLastModified else { return true }
        guard let attrs = try? fileManager.attributesOfItem(atPath: sessionsURL.path),
              let fileMod = attrs[.modificationDate] as? Date else { return true }
        return fileMod > lastMod
    }

    // MARK: - Settings

    var settings: AppSettings {
        get {
            // Return cached settings if available
            if let cached = _cachedSettings {
                return cached
            }
            // Otherwise load from disk and cache
            let loaded = loadSettingsFromDisk()
            _cachedSettings = loaded
            return loaded
        }
        set {
            print("[StorageService] 💾 Saving settings to UserDefaults")

            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: settingsKey)
                userDefaults.synchronize()
                _cachedSettings = newValue  // Update cache
                print("[StorageService] ✅ Settings saved - API Key length: \(newValue.apiKey.count)")
            } else {
                print("[StorageService] ❌ Failed to encode settings")
            }
        }
    }

    /// Force reload settings from disk (use sparingly)
    func reloadSettings() {
        _cachedSettings = loadSettingsFromDisk()
    }

    private func loadSettingsFromDisk() -> AppSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
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

    // MARK: - Sessions (File-based with Cache)

    func loadSessions() -> [RecordingSession] {
        // Return cached if available and file not modified
        if let cached = _cachedSessions, !sessionsFileModified() {
            return cached
        }
        
        let sessions = loadSessionsFromDisk()
        _cachedSessions = sessions
        _sessionsLastModified = Date()
        return sessions
    }
    
    /// Load sessions directly from disk (bypasses cache, used for migration)
    func loadSessionsFromDisk() -> [RecordingSession] {
        guard fileManager.fileExists(atPath: sessionsURL.path) else {
            print("[StorageService] ⚠️ sessions.json not found at \(sessionsURL.path)")
            return []
        }

        guard let data = try? Data(contentsOf: sessionsURL) else {
            print("[StorageService] ⚠️ Could not read sessions.json")
            return []
        }

        do {
            let sessions = try sessionDecoder.decode([RecordingSession].self, from: data)
            print("[StorageService] ✅ Loaded \(sessions.count) sessions from disk")
            if sessions.isEmpty {
                print("[StorageService] ℹ️ sessions.json path: \(sessionsURL.path)")
            }
            return sessions
        } catch {
            print("[StorageService] ❌ Failed to decode sessions: \(error)")
            return []
        }
    }
    
    /// Load sessions sorted by date, with optional limit for pagination
    func loadRecentSessions(limit: Int? = nil) -> [RecordingSession] {
        let allSessions = loadSessions()
        let sorted = allSessions.sorted { $0.startDate > $1.startDate }
        if let limit = limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    func saveSessions(_ sessions: [RecordingSession]) {
        _cachedSessions = sessions  // Update cache
        _sessionsLastModified = Date()
        if let data = try? sessionEncoder.encode(sessions) {
            try? data.write(to: sessionsURL)
        }
        
        // Sync with SwiftData (update metadata)
        Task { @MainActor in
            for session in sessions {
                SwiftDataService.shared.syncSession(session)
            }
        }
    }
    
    /// Save a single session (more efficient than saving all)
    func saveSession(_ session: RecordingSession) {
        var sessions = loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        _cachedSessions = sessions
        _sessionsLastModified = Date()
        if let data = try? sessionEncoder.encode(sessions) {
            try? data.write(to: sessionsURL)
        }
        
        // Sync with SwiftData
        Task { @MainActor in
            SwiftDataService.shared.syncSession(session)
        }
    }

    func deleteSession(_ sessionID: UUID) {
        var sessions = loadSessions()
        sessions.removeAll { $0.id == sessionID }
        saveSessions(sessions)
        
        // Delete from SwiftData
        Task { @MainActor in
            SwiftDataService.shared.deleteSession(id: sessionID)
        }
    }

    // MARK: - Folders (File-based)

    func loadFolders() -> [Folder] {
        guard fileManager.fileExists(atPath: foldersURL.path),
              let data = try? Data(contentsOf: foldersURL),
              let folders = try? sessionDecoder.decode([Folder].self, from: data) else {
            // Return default folders if none exist
            return [Folder.inbox]
        }

        // Ensure INBOX always exists
        var result = folders
        if !result.contains(where: { $0.id == Folder.inboxID }) {
            result.insert(Folder.inbox, at: 0)
        }

        return result
    }

    func saveFolders(_ folders: [Folder]) {
        // Ensure INBOX is always included
        var foldersToSave = folders
        if !foldersToSave.contains(where: { $0.id == Folder.inboxID }) {
            foldersToSave.insert(Folder.inbox, at: 0)
        }

        if let data = try? sessionEncoder.encode(foldersToSave) {
            try? data.write(to: foldersURL)
        }
        
        // Sync with SwiftData
        Task { @MainActor in
            for folder in foldersToSave {
                SwiftDataService.shared.syncFolder(folder)
            }
        }
    }

    func createFolder(_ folder: Folder) {
        var folders = loadFolders()
        folders.append(folder)
        saveFolders(folders)
    }

    func updateFolder(_ folder: Folder) {
        var folders = loadFolders()
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            // Don't allow modifying system folders' critical properties
            if folders[index].isSystem {
                var updated = folders[index]
                // Only allow changing non-critical properties
                updated.classificationKeywords = folder.classificationKeywords
                updated.classificationDescription = folder.classificationDescription
                folders[index] = updated
            } else {
                folders[index] = folder
            }
        }
        saveFolders(folders)
    }

    func deleteFolder(_ folderID: UUID) {
        var folders = loadFolders()

        // Don't delete system folders
        guard let folder = folders.first(where: { $0.id == folderID }),
              !folder.isSystem else {
            return
        }

        // Get all descendant folders
        let descendantIDs = Set(folders.descendants(of: folderID).map { $0.id } + [folderID])

        // Move sessions from deleted folders to INBOX
        var sessions = loadSessions()
        for i in 0..<sessions.count {
            if let sessionFolderID = sessions[i].folderID,
               descendantIDs.contains(sessionFolderID) {
                sessions[i].folderID = nil  // Move to INBOX
                sessions[i].isClassified = false
            }
        }
        saveSessions(sessions)

        // Remove the folder and its descendants
        folders.removeAll { descendantIDs.contains($0.id) }
        saveFolders(folders)
    }

    /// Get folder path for physical file storage
    func getFolderPath(for folder: Folder) -> URL {
        let folders = loadFolders()
        let path = folders.path(to: folder.id)

        var url = RecordingSession.sessionsFolder
        for pathFolder in path {
            // Sanitize folder name for filesystem
            let safeName = pathFolder.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            url = url.appendingPathComponent(safeName, isDirectory: true)
        }

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        return url
    }

    // MARK: - Labels (File-based)

    func loadLabels() -> [SessionLabel] {
        guard fileManager.fileExists(atPath: labelsURL.path),
              let data = try? Data(contentsOf: labelsURL),
              let labels = try? sessionDecoder.decode([SessionLabel].self, from: data) else {
            // Return default labels if none exist
            return SessionLabel.defaultLabels
        }
        return labels
    }

    func saveLabels(_ labels: [SessionLabel]) {
        if let data = try? sessionEncoder.encode(labels) {
            try? data.write(to: labelsURL)
        }
        
        // Sync with SwiftData
        Task { @MainActor in
            for label in labels {
                SwiftDataService.shared.syncLabel(label)
            }
        }
    }

    func createLabel(_ label: SessionLabel) {
        var labels = loadLabels()
        labels.append(label)
        saveLabels(labels)
    }

    func updateLabel(_ label: SessionLabel) {
        var labels = loadLabels()
        if let index = labels.firstIndex(where: { $0.id == label.id }) {
            labels[index] = label
        }
        saveLabels(labels)
    }

    func deleteLabel(_ labelID: UUID) {
        var labels = loadLabels()
        labels.removeAll { $0.id == labelID }
        saveLabels(labels)

        // Remove label from all sessions
        var sessions = loadSessions()
        for i in 0..<sessions.count {
            sessions[i].labelIDs.removeAll { $0 == labelID }
        }
        saveSessions(sessions)
    }
    
    // MARK: - Speaker Library (for SwiftData migration)
    
    /// Load speaker library from UserDefaults
    func loadSpeakerLibrary() -> SpeakerLibrary {
        return SpeakerLibrary.shared
    }

    // MARK: - Session Movement

    /// Move a session to a folder
    func moveSession(_ sessionID: UUID, to folderID: UUID?) {
        var sessions = loadSessions()

        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        sessions[index].folderID = folderID
        sessions[index].isClassified = true
        sessions[index].aiSuggestedFolderID = nil
        sessions[index].aiClassificationConfidence = nil

        saveSessions(sessions)

        // Note: Physical file movement is handled by the caller if needed
        // This keeps the storage service focused on data persistence
    }

    /// Add a label to a session
    func addLabel(_ labelID: UUID, to sessionID: UUID) {
        var sessions = loadSessions()

        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        if !sessions[index].labelIDs.contains(labelID) {
            sessions[index].labelIDs.append(labelID)
            saveSessions(sessions)
        }
    }

    /// Remove a label from a session
    func removeLabel(_ labelID: UUID, from sessionID: UUID) {
        var sessions = loadSessions()

        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        sessions[index].labelIDs.removeAll { $0 == labelID }
        saveSessions(sessions)
    }

    /// Get sessions in a specific folder
    func sessions(in folderID: UUID?) -> [RecordingSession] {
        loadSessions().filter { $0.folderID == folderID }
    }

    /// Get sessions with a specific label
    func sessions(withLabel labelID: UUID) -> [RecordingSession] {
        loadSessions().filter { $0.labelIDs.contains(labelID) }
    }

    /// Get unclassified sessions (in INBOX, not yet classified)
    func unclassifiedSessions() -> [RecordingSession] {
        loadSessions().filter { $0.folderID == nil && !$0.isClassified }
    }

    /// Force re-run migration (for debugging)
    func forceMigration() {
        userDefaults.removeObject(forKey: migrationKey)
        migrateSessionsIfNeeded()
    }

    /// Force re-run folder migration and import orphaned files
    func forceOrphanedImport() {
        userDefaults.removeObject(forKey: folderMigrationKey)
        migrateFoldersIfNeeded()
    }

    // MARK: - Session Migration

    /// Migrate sessions to fix date/duration issues
    private func migrateSessionsIfNeeded() {
        guard !userDefaults.bool(forKey: migrationKey) else {
            return  // Already migrated
        }

        print("[StorageService] 🔄 Starting session migration...")

        guard fileManager.fileExists(atPath: sessionsURL.path),
              let data = try? Data(contentsOf: sessionsURL) else {
            userDefaults.set(true, forKey: migrationKey)
            return
        }

        // Try to parse as raw JSON to fix dates
        guard var jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("[StorageService] ⚠️ Could not parse sessions as JSON array")
            userDefaults.set(true, forKey: migrationKey)
            return
        }

        var migratedCount = 0
        let appleToUnixOffset: Double = 978307200  // Seconds between 1970-01-01 and 2001-01-01

        // Reasonable date range: 2020-2030 in UNIX timestamps
        let minReasonableDate: Double = 1577836800  // 2020-01-01
        let maxReasonableDate: Double = 1893456000  // 2030-01-01

        for i in 0..<jsonArray.count {
            var session = jsonArray[i]
            var needsMigration = false

            // Fix startDate
            if let startDate = session["startDate"] as? Double {
                let correctedDate = normalizeTimestamp(startDate, appleOffset: appleToUnixOffset, minDate: minReasonableDate, maxDate: maxReasonableDate)
                if correctedDate != startDate {
                    session["startDate"] = correctedDate
                    needsMigration = true
                    print("[StorageService] 📅 Fixed startDate: \(startDate) -> \(correctedDate)")
                }
            }

            // Fix endDate
            if let endDate = session["endDate"] as? Double {
                let correctedDate = normalizeTimestamp(endDate, appleOffset: appleToUnixOffset, minDate: minReasonableDate, maxDate: maxReasonableDate)
                if correctedDate != endDate {
                    session["endDate"] = correctedDate
                    needsMigration = true
                    print("[StorageService] 📅 Fixed endDate: \(endDate) -> \(correctedDate)")
                }
            }

            // Fix sessions with same start/end date or very short duration
            if let startDate = session["startDate"] as? Double,
               let endDate = session["endDate"] as? Double {
                let duration = endDate - startDate

                // If duration is less than 1 second or negative, try to get from audio file
                if duration < 1 || duration < 0 {
                    if let audioDuration = getAudioDuration(for: session), audioDuration > 0 {
                        session["endDate"] = startDate + audioDuration
                        needsMigration = true
                        print("[StorageService] ⏱️ Fixed duration from audio: \(audioDuration)s")
                    }
                }
            }

            if needsMigration {
                jsonArray[i] = session
                migratedCount += 1
            }
        }

        if migratedCount > 0 {
            // Save migrated data
            if let migratedData = try? JSONSerialization.data(withJSONObject: jsonArray) {
                try? migratedData.write(to: sessionsURL)
                print("[StorageService] ✅ Migrated \(migratedCount) sessions")
            }
        } else {
            print("[StorageService] ✅ No migration needed")
        }

        userDefaults.set(true, forKey: migrationKey)
    }

    /// Normalize a timestamp to UNIX format
    /// Handles timestamps that may be in Apple format (seconds since 2001) or UNIX format (seconds since 1970)
    private func normalizeTimestamp(_ timestamp: Double, appleOffset: Double, minDate: Double, maxDate: Double) -> Double {
        // Check if timestamp is already in reasonable UNIX range
        if timestamp >= minDate && timestamp <= maxDate {
            return timestamp  // Already valid UNIX timestamp
        }

        // Check if it's Apple format (needs conversion to UNIX)
        let asUnix = timestamp + appleOffset
        if asUnix >= minDate && asUnix <= maxDate {
            return asUnix  // Was Apple format, converted to UNIX
        }

        // Check if it's a far-future date (UNIX timestamp interpreted as Apple by old decoder)
        // This happens when UNIX timestamp (like 1769469587) is decoded as Apple format
        // and then would show as year 2057
        // We need to detect this case: the stored value is already UNIX but was saved expecting
        // a decoder that uses UNIX format, while the default decoder uses Apple format
        // In this case, the value is correct and we just need to make sure it's reasonable

        // Actually, if the timestamp is > 1893456000 (2030 in UNIX), it might be:
        // 1. A genuine future date (unlikely)
        // 2. A timestamp that's correct but will be misinterpreted

        // For now, just return the original if we can't determine the format
        return timestamp
    }

    // MARK: - Folder Migration

    /// Migrate existing sessions to folder system
    /// - All existing sessions without folderID go to INBOX
    /// - Create default folder structure
    private func migrateFoldersIfNeeded() {
        guard !userDefaults.bool(forKey: folderMigrationKey) else {
            return  // Already migrated
        }

        print("[StorageService] 🔄 Starting folder migration...")

        // Create default folders if they don't exist
        var folders = loadFolders()
        if folders.isEmpty || (folders.count == 1 && folders.first?.isInbox == true) {
            print("[StorageService] 📁 Creating default folder structure")
            folders = [Folder.inbox]
            saveFolders(folders)
        }

        // Create default labels if they don't exist
        if !fileManager.fileExists(atPath: labelsURL.path) {
            print("[StorageService] 🏷️ Creating default labels")
            saveLabels(SessionLabel.defaultLabels)
        }

        // Migrate existing sessions to have folder organization properties
        var sessions = loadSessions()
        var migratedCount = 0

        for i in 0..<sessions.count {
            // Sessions without folderID are considered to be in INBOX
            // We don't set folderID = Folder.inboxID, we keep it nil
            // nil means INBOX (consistent with the model)

            // Initialize labelIDs if needed (should be done by Codable defaults)
            // Just ensure isClassified is set for sessions that have been placed
            if sessions[i].folderID != nil && !sessions[i].isClassified {
                sessions[i].isClassified = true
                migratedCount += 1
            }
        }

        if migratedCount > 0 {
            saveSessions(sessions)
            print("[StorageService] ✅ Migrated \(migratedCount) sessions for folder organization")
        } else {
            print("[StorageService] ✅ No folder migration needed")
        }

        // Import any orphaned audio files
        importOrphanedAudioFiles()

        userDefaults.set(true, forKey: folderMigrationKey)
    }

    /// Get audio duration for a session from its audio files
    private func getAudioDuration(for sessionDict: [String: Any]) -> Double? {
        let sessionsFolder = RecordingSession.sessionsFolder

        // Check systemAudioFileName first
        if let fileName = sessionDict["systemAudioFileName"] as? String {
            let url = sessionsFolder.appendingPathComponent(fileName)
            if let duration = getAudioFileDuration(url: url) {
                return duration
            }
        }

        // Check micAudioFileName
        if let fileName = sessionDict["micAudioFileName"] as? String {
            let url = sessionsFolder.appendingPathComponent(fileName)
            if let duration = getAudioFileDuration(url: url) {
                return duration
            }
        }

        // Check audioFileName
        if let fileName = sessionDict["audioFileName"] as? String {
            let url = sessionsFolder.appendingPathComponent(fileName)
            if let duration = getAudioFileDuration(url: url) {
                return duration
            }
        }

        return nil
    }

    /// Get duration of an audio file in seconds
    private func getAudioFileDuration(url: URL) -> Double? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let ext = url.pathExtension.lowercased()

        // For WebM/OGG files, use ffprobe since AVFoundation doesn't support them
        if ext == "webm" || ext == "ogg" {
            return getFFprobeDuration(url: url)
        }

        // For other formats, try AVFoundation
        let asset = AVURLAsset(url: url)

        // Try synchronous approach for migration (async not suitable here)
        var duration: Double = 0
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let durationValue = try await asset.load(.duration)
                duration = CMTimeGetSeconds(durationValue)
            } catch {
                print("[StorageService] ⚠️ AVFoundation could not load duration: \(error.localizedDescription)")
            }
            semaphore.signal()
        }

        // Wait up to 5 seconds for duration
        _ = semaphore.wait(timeout: .now() + 5)

        if duration.isNaN || duration <= 0 {
            // Fallback to ffprobe for unsupported formats
            return getFFprobeDuration(url: url)
        }

        return duration
    }

    /// Get audio duration using ffprobe (for WebM and other formats)
    private func getFFprobeDuration(url: URL) -> Double? {
        // Find ffprobe (should be next to ffmpeg)
        guard let ffprobePath = findFFprobe() else {
            print("[StorageService] ⚠️ ffprobe not found")
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
                print("[StorageService] ✅ ffprobe duration for \(url.lastPathComponent): \(String(format: "%.1f", duration))s")
                return duration
            }
        } catch {
            print("[StorageService] ⚠️ ffprobe failed: \(error.localizedDescription)")
        }

        return nil
    }

    /// Find ffprobe binary (next to ffmpeg in bundle or system)
    private func findFFprobe() -> String? {
        // 1. Check for bundled ffprobe in app Resources
        if let bundledPath = Bundle.main.path(forResource: "ffprobe", ofType: nil),
           fileManager.fileExists(atPath: bundledPath) {
            return bundledPath
        }

        // 2. Check next to ffmpeg in bundle
        if let ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            let ffprobeDir = URL(fileURLWithPath: ffmpegPath).deletingLastPathComponent()
            let ffprobePath = ffprobeDir.appendingPathComponent("ffprobe").path
            if fileManager.fileExists(atPath: ffprobePath) {
                return ffprobePath
            }
        }

        // 3. Check common system paths
        let systemPaths = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        for path in systemPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // 4. Fallback: use 'which'
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["ffprobe"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty, fileManager.fileExists(atPath: path) {
                return path
            }
        } catch {}

        return nil
    }

    // MARK: - Orphaned Audio Recovery

    /// Represents an orphaned audio file or file pair
    struct OrphanedAudio {
        let sessionID: String  // Base name like "session_2026-01-26_11-44-15"
        var singleFile: String?  // For single-source recordings
        var micFile: String?     // For dual-mode: mic file
        var systemFile: String?  // For dual-mode: system file
        let date: Date
    }

    /// Find audio files that have no corresponding session in JSON
    func findOrphanedAudioFiles() -> [OrphanedAudio] {
        let sessionsFolder = RecordingSession.sessionsFolder
        let existingSessions = loadSessions()

        // Get all referenced audio files
        var referencedFiles = Set<String>()
        for session in existingSessions {
            if let file = session.audioFileName { referencedFiles.insert(file) }
            if let file = session.micAudioFileName { referencedFiles.insert(file) }
            if let file = session.systemAudioFileName { referencedFiles.insert(file) }
        }

        // Get all audio files in Sessions folder
        guard let files = try? fileManager.contentsOfDirectory(atPath: sessionsFolder.path) else {
            return []
        }

        // Filter for audio files
        let audioExtensions = ["m4a", "wav", "webm", "ogg", "mp3", "aac"]
        let audioFiles = files.filter { file in
            let ext = URL(fileURLWithPath: file).pathExtension.lowercased()
            return audioExtensions.contains(ext)
        }

        // Find orphaned files
        let orphanedFiles = audioFiles.filter { !referencedFiles.contains($0) }

        // Group by session ID (base name without _mic/_system suffix)
        var sessionGroups: [String: OrphanedAudio] = [:]

        for file in orphanedFiles {
            guard let (sessionID, type, date) = parseAudioFilename(file) else {
                continue
            }

            if sessionGroups[sessionID] == nil {
                sessionGroups[sessionID] = OrphanedAudio(sessionID: sessionID, date: date)
            }

            switch type {
            case .single:
                sessionGroups[sessionID]?.singleFile = file
            case .mic:
                sessionGroups[sessionID]?.micFile = file
            case .system:
                sessionGroups[sessionID]?.systemFile = file
            }
        }

        return Array(sessionGroups.values).sorted { $0.date < $1.date }
    }

    private enum AudioFileType {
        case single
        case mic
        case system
    }

    /// Parse filename to extract session ID, type, and date
    /// Filename format: session_YYYY-MM-DD_HH-MM-SS[_mic|_system].ext
    private func parseAudioFilename(_ filename: String) -> (sessionID: String, type: AudioFileType, date: Date)? {
        let name = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent

        // Check for _mic or _system suffix
        var type: AudioFileType = .single
        var baseName = name

        if name.hasSuffix("_mic") {
            type = .mic
            baseName = String(name.dropLast(4))
        } else if name.hasSuffix("_system") {
            type = .system
            baseName = String(name.dropLast(7))
        }

        // Parse date from base name: session_YYYY-MM-DD_HH-MM-SS
        let pattern = "session_(\\d{4})-(\\d{2})-(\\d{2})_(\\d{2})-(\\d{2})-(\\d{2})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: baseName, range: NSRange(baseName.startIndex..., in: baseName)) else {
            return nil
        }

        guard match.numberOfRanges == 7,
              let yearRange = Range(match.range(at: 1), in: baseName),
              let monthRange = Range(match.range(at: 2), in: baseName),
              let dayRange = Range(match.range(at: 3), in: baseName),
              let hourRange = Range(match.range(at: 4), in: baseName),
              let minRange = Range(match.range(at: 5), in: baseName),
              let secRange = Range(match.range(at: 6), in: baseName) else {
            return nil
        }

        var components = DateComponents()
        components.year = Int(baseName[yearRange])
        components.month = Int(baseName[monthRange])
        components.day = Int(baseName[dayRange])
        components.hour = Int(baseName[hourRange])
        components.minute = Int(baseName[minRange])
        components.second = Int(baseName[secRange])

        guard let date = Calendar.current.date(from: components) else {
            return nil
        }

        return (baseName, type, date)
    }

    /// Import orphaned audio files as new sessions
    /// Returns the number of sessions created
    @discardableResult
    func importOrphanedAudioFiles(using existingMetadata: [SessionMetadataSnapshot] = []) -> Int {
        let orphaned = findOrphanedAudioFiles()
        guard !orphaned.isEmpty else {
            print("[StorageService] ✅ No orphaned audio files to import")
            return 0
        }

        print("[StorageService] 🔄 Found \(orphaned.count) orphaned audio session(s) to import")

        var sessions = loadSessions()
        var importedCount = 0
        let metadataByFile = buildMetadataLookup(existingMetadata)

        for orphan in orphaned {
            if let matchedMetadata = metadataFor(orphan: orphan, metadataByFile: metadataByFile) {
                if sessions.contains(where: { $0.id == matchedMetadata.id }) {
                    continue
                }

                let audioSource = AudioSource(rawValue: matchedMetadata.audioSource) ?? .microphone
                let sessionType = SessionType(rawValue: matchedMetadata.sessionType) ?? .meeting

                let newSession = RecordingSession(
                    id: matchedMetadata.id,
                    startDate: matchedMetadata.startDate,
                    endDate: matchedMetadata.endDate,
                    transcriptSegments: [],
                    speakers: [],
                    audioSource: audioSource,
                    title: matchedMetadata.title,
                    audioFileName: matchedMetadata.audioFileName ?? orphan.singleFile,
                    micAudioFileName: matchedMetadata.micAudioFileName ?? orphan.micFile,
                    systemAudioFileName: matchedMetadata.systemAudioFileName ?? orphan.systemFile,
                    sessionType: sessionType,
                    summary: nil,
                    folderID: matchedMetadata.folderID,
                    labelIDs: matchedMetadata.labelIDs,
                    aiSuggestedFolderID: matchedMetadata.aiSuggestedFolderID,
                    aiClassificationConfidence: matchedMetadata.aiClassificationConfidence,
                    isClassified: matchedMetadata.isClassified
                )

                sessions.append(newSession)
                importedCount += 1
                print("[StorageService] 📦 Imported from metadata: \(matchedMetadata.id)")
                continue
            }

            // Determine audio source from files
            let isDualMode = orphan.micFile != nil || orphan.systemFile != nil
            let audioSource: AudioSource

            if isDualMode {
                audioSource = .both
            } else if orphan.singleFile?.contains("system") == true {
                audioSource = .systemAudio
            } else {
                audioSource = .microphone
            }

            // Get duration from audio file
            var duration: TimeInterval = 60  // Default 1 minute if can't read
            let sessionsFolder = RecordingSession.sessionsFolder

            if let singleFile = orphan.singleFile {
                let url = sessionsFolder.appendingPathComponent(singleFile)
                if let d = getAudioFileDuration(url: url) {
                    duration = d
                }
            } else if let systemFile = orphan.systemFile {
                let url = sessionsFolder.appendingPathComponent(systemFile)
                if let d = getAudioFileDuration(url: url) {
                    duration = d
                }
            } else if let micFile = orphan.micFile {
                let url = sessionsFolder.appendingPathComponent(micFile)
                if let d = getAudioFileDuration(url: url) {
                    duration = d
                }
            }

            // Create new session
            let newSession = RecordingSession(
                id: UUID(),
                startDate: orphan.date,
                endDate: orphan.date.addingTimeInterval(duration),
                transcriptSegments: [],
                speakers: [],
                audioSource: audioSource,
                title: nil,
                audioFileName: orphan.singleFile,
                micAudioFileName: orphan.micFile,
                systemAudioFileName: orphan.systemFile,
                sessionType: .meeting,
                summary: nil,
                folderID: nil,  // INBOX
                labelIDs: [],
                aiSuggestedFolderID: nil,
                aiClassificationConfidence: nil,
                isClassified: false
            )

            sessions.append(newSession)
            importedCount += 1

            print("[StorageService] 📦 Imported: \(orphan.sessionID) (duration: \(String(format: "%.1f", duration))s)")
        }

        saveSessions(sessions)
        print("[StorageService] ✅ Imported \(importedCount) orphaned session(s)")

        return importedCount
    }

    /// Remove duplicate sessions based on shared audio filenames.
    /// Returns the number of sessions removed from JSON (and SwiftData).
    func removeDuplicateSessionsByAudioFiles() -> Int {
        var sessions = loadSessions()
        guard !sessions.isEmpty else { return 0 }

        var groups: [String: [RecordingSession]] = [:]
        for session in sessions {
            for key in audioFileKeys(for: session) {
                groups[key, default: []].append(session)
            }
        }

        var keepIDs = Set<UUID>()
        var deleteCandidates = Set<UUID>()

        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { isBetterSession($0, $1) }
            if let keep = sorted.first {
                keepIDs.insert(keep.id)
            }
            for session in sorted.dropFirst() {
                deleteCandidates.insert(session.id)
            }
        }

        let deleteIDs = deleteCandidates.subtracting(keepIDs)
        guard !deleteIDs.isEmpty else { return 0 }

        sessions.removeAll { deleteIDs.contains($0.id) }
        saveSessions(sessions)

        Task { @MainActor in
            for id in deleteIDs {
                SwiftDataService.shared.deleteSession(id: id)
            }
        }

        print("[StorageService] 🧹 Removed \(deleteIDs.count) duplicate session(s) from JSON")
        return deleteIDs.count
    }

    private func buildMetadataLookup(_ metadata: [SessionMetadataSnapshot]) -> [String: SessionMetadataSnapshot] {
        var lookup: [String: SessionMetadataSnapshot] = [:]
        for entry in metadata {
            if let file = entry.audioFileName { lookup[file] = entry }
            if let file = entry.micAudioFileName { lookup[file] = entry }
            if let file = entry.systemAudioFileName { lookup[file] = entry }
        }
        return lookup
    }

    private func metadataFor(
        orphan: OrphanedAudio,
        metadataByFile: [String: SessionMetadataSnapshot]
    ) -> SessionMetadataSnapshot? {
        if let file = orphan.singleFile, let match = metadataByFile[file] {
            return match
        }
        if let file = orphan.micFile, let match = metadataByFile[file] {
            return match
        }
        if let file = orphan.systemFile, let match = metadataByFile[file] {
            return match
        }
        return nil
    }

    private func audioFileKeys(for session: RecordingSession) -> Set<String> {
        var keys = Set<String>()
        if let file = session.audioFileName { keys.insert(file) }
        if let file = session.micAudioFileName { keys.insert(file) }
        if let file = session.systemAudioFileName { keys.insert(file) }
        return keys
    }

    private func isBetterSession(_ lhs: RecordingSession, _ rhs: RecordingSession) -> Bool {
        let lhsHasTranscript = !lhs.transcriptSegments.isEmpty
        let rhsHasTranscript = !rhs.transcriptSegments.isEmpty
        if lhsHasTranscript != rhsHasTranscript {
            return lhsHasTranscript && !rhsHasTranscript
        }

        let lhsHasSummary = lhs.summary != nil
        let rhsHasSummary = rhs.summary != nil
        if lhsHasSummary != rhsHasSummary {
            return lhsHasSummary && !rhsHasSummary
        }

        if lhs.transcriptSegments.count != rhs.transcriptSegments.count {
            return lhs.transcriptSegments.count > rhs.transcriptSegments.count
        }

        if lhs.duration != rhs.duration {
            return lhs.duration > rhs.duration
        }

        let lhsDate = lhs.endDate ?? lhs.startDate
        let rhsDate = rhs.endDate ?? rhs.startDate
        return lhsDate > rhsDate
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
            snippets: snippets,
            sessions: loadSessions(),
            folders: loadFolders(),
            labels: loadLabels()
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
        if let sessions = importData.sessions {
            saveSessions(sessions)
        }
        if let folders = importData.folders {
            saveFolders(folders)
        }
        if let labels = importData.labels {
            saveLabels(labels)
        }

        return true
    }
}

struct SessionMetadataSnapshot {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let title: String?
    let sessionType: String
    let audioSource: String
    let audioFileName: String?
    let micAudioFileName: String?
    let systemAudioFileName: String?
    let folderID: UUID?
    let labelIDs: [UUID]
    let isClassified: Bool
    let aiSuggestedFolderID: UUID?
    let aiClassificationConfidence: Double?
}

struct ExportData: Codable {
    let settings: AppSettings
    let transcriptions: [Transcription]
    let notes: [Note]
    let dictionaryEntries: [DictionaryEntry]
    let snippets: [Snippet]
    let sessions: [RecordingSession]?  // Optional for backwards compatibility
    let folders: [Folder]?             // Optional for backwards compatibility
    let labels: [SessionLabel]?        // Optional for backwards compatibility
}
