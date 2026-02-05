import SwiftUI
import AVFoundation
import Combine
import AppKit

// MARK: - Audio Player Manager (supports dual audio playback)
// Uses WebMAudioPlayer for WebM files (native WebKit playback)
// Falls back to AVAudioPlayer for other formats

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoaded = false
    @Published var error: String?

    // Dual audio support
    @Published var isDualMode = false
    @Published var micVolume: Float = 1.0 {
        didSet {
            micPlayer?.volume = micVolume
            webMicPlayer?.volume = micVolume
        }
    }
    @Published var systemVolume: Float = 1.0 {
        didSet {
            systemPlayer?.volume = systemVolume
            webSystemPlayer?.volume = systemVolume
        }
    }

    // AVAudioPlayer for non-WebM formats
    private var audioPlayer: AVAudioPlayer?
    private var micPlayer: AVAudioPlayer?
    private var systemPlayer: AVAudioPlayer?

    // WebMAudioPlayer for WebM files (uses WKWebView)
    private var webPlayer: WebMAudioPlayer?
    private var webMicPlayer: WebMAudioPlayer?
    private var webSystemPlayer: WebMAudioPlayer?

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var useWebPlayer = false

    // Temporary converted file URL (for WebM conversion)
    private var convertedFileURL: URL?

    // Single file mode
    func loadAudio(from url: URL) {
        isDualMode = false
        useWebPlayer = false

        // For WebM/OGG files, convert to WAV using ffmpeg first
        let ext = url.pathExtension.lowercased()
        if ext == "webm" || ext == "ogg" {
            print("[AudioPlayer] Converting \(ext.uppercased()) to WAV for playback: \(url.lastPathComponent)")
            convertAndLoad(url: url)
        } else {
            loadAudioDirect(from: url)
        }
    }

    /// Convert WebM/OGG to WAV and load with AVAudioPlayer
    private func convertAndLoad(url: URL) {
        isLoaded = false
        error = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Find ffmpeg
            guard let ffmpegPath = Self.findFFmpeg() else {
                DispatchQueue.main.async {
                    self.error = "ffmpeg not found - required for WebM playback"
                }
                return
            }

            // Create temp file for converted audio
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("playback_\(UUID().uuidString).wav")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = [
                "-i", url.path,
                "-acodec", "pcm_s16le",  // WAV format
                "-ar", "44100",           // 44.1kHz sample rate
                "-ac", "2",               // Stereo
                "-y",                     // Overwrite
                tempFile.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                print("[AudioPlayer] Converting with ffmpeg...")
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self.convertedFileURL = tempFile
                        self.loadAudioDirect(from: tempFile)
                        print("[AudioPlayer] ✅ Converted and loaded: \(url.lastPathComponent)")
                    }
                } else {
                    DispatchQueue.main.async {
                        self.error = "Failed to convert audio (ffmpeg exit code: \(process.terminationStatus))"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Failed to convert audio: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Find ffmpeg binary
    private static func findFFmpeg() -> String? {
        let fm = FileManager.default

        // Check for bundled ffmpeg in app Resources
        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil),
           fm.fileExists(atPath: bundledPath) {
            return bundledPath
        }

        // Check common system paths
        let systemPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in systemPaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func setupWebPlayerBindings(_ player: WebMAudioPlayer) {
        player.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.isPlaying = value }
            .store(in: &cancellables)

        player.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.currentTime = value }
            .store(in: &cancellables)

        player.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.duration = value }
            .store(in: &cancellables)

        player.$isLoaded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.isLoaded = value }
            .store(in: &cancellables)

        player.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.error = value }
            .store(in: &cancellables)
    }

    private func loadAudioDirect(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            isLoaded = true
            error = nil
            print("[AudioPlayer] Loaded with AVAudioPlayer: \(url.lastPathComponent), duration: \(duration)s")
        } catch {
            self.error = "Failed to load audio: \(error.localizedDescription)"
            print("[AudioPlayer] Error loading audio: \(error)")
        }
    }

    // Temporary converted files for dual mode
    private var convertedMicURL: URL?
    private var convertedSystemURL: URL?

    // Dual file mode (mic + system)
    func loadDualAudio(micURL: URL?, systemURL: URL?) {
        isDualMode = true
        useWebPlayer = false

        // Check if any file needs conversion (WebM/OGG)
        let micNeedsConversion = micURL.map { ["webm", "ogg"].contains($0.pathExtension.lowercased()) } ?? false
        let sysNeedsConversion = systemURL.map { ["webm", "ogg"].contains($0.pathExtension.lowercased()) } ?? false

        if micNeedsConversion || sysNeedsConversion {
            // Convert files in background then load
            print("[AudioPlayer] Converting WebM/OGG files for dual playback...")
            convertAndLoadDual(micURL: micURL, systemURL: systemURL, micNeedsConversion: micNeedsConversion, sysNeedsConversion: sysNeedsConversion)
            return
        }

        // Non-WebM: use AVAudioPlayer directly
        loadDualAudioDirect(micURL: micURL, systemURL: systemURL)
    }

    /// Convert and load dual audio files
    private func convertAndLoadDual(micURL: URL?, systemURL: URL?, micNeedsConversion: Bool, sysNeedsConversion: Bool) {
        isLoaded = false
        error = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let ffmpegPath = Self.findFFmpeg() else {
                DispatchQueue.main.async {
                    self.error = "ffmpeg not found - required for WebM playback"
                }
                return
            }

            var finalMicURL = micURL
            var finalSysURL = systemURL

            // Convert mic if needed
            if micNeedsConversion, let url = micURL {
                if let converted = self.convertToWav(url: url, ffmpegPath: ffmpegPath, label: "mic") {
                    finalMicURL = converted
                    self.convertedMicURL = converted
                }
            }

            // Convert system if needed
            if sysNeedsConversion, let url = systemURL {
                if let converted = self.convertToWav(url: url, ffmpegPath: ffmpegPath, label: "system") {
                    finalSysURL = converted
                    self.convertedSystemURL = converted
                }
            }

            DispatchQueue.main.async {
                self.loadDualAudioDirect(micURL: finalMicURL, systemURL: finalSysURL)
            }
        }
    }

    /// Convert a single file to WAV
    private func convertToWav(url: URL, ffmpegPath: String, label: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("playback_\(label)_\(UUID().uuidString).wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", url.path,
            "-acodec", "pcm_s16le",
            "-ar", "44100",
            "-ac", "2",
            "-y",
            tempFile.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                print("[AudioPlayer] ✅ Converted \(label): \(url.lastPathComponent)")
                return tempFile
            }
        } catch {
            print("[AudioPlayer] ❌ Failed to convert \(label): \(error)")
        }
        return nil
    }

    /// Load dual audio directly (no conversion needed)
    private func loadDualAudioDirect(micURL: URL?, systemURL: URL?) {
        var loadedDuration: TimeInterval = 0

        // Load mic audio
        if let url = micURL {
            do {
                micPlayer = try AVAudioPlayer(contentsOf: url)
                micPlayer?.delegate = self
                micPlayer?.prepareToPlay()
                micPlayer?.volume = micVolume
                micPlayer?.enableRate = true
                loadedDuration = max(loadedDuration, micPlayer?.duration ?? 0)
                print("[AudioPlayer] Loaded mic audio: \(url.lastPathComponent)")
            } catch {
                print("[AudioPlayer] Error loading mic audio: \(error)")
            }
        }

        // Load system audio
        if let url = systemURL {
            do {
                systemPlayer = try AVAudioPlayer(contentsOf: url)
                systemPlayer?.prepareToPlay()
                systemPlayer?.volume = systemVolume
                systemPlayer?.enableRate = true
                loadedDuration = max(loadedDuration, systemPlayer?.duration ?? 0)
                print("[AudioPlayer] Loaded system audio: \(url.lastPathComponent)")
            } catch {
                print("[AudioPlayer] Error loading system audio: \(error)")
            }
        }

        duration = loadedDuration
        isLoaded = micPlayer != nil || systemPlayer != nil

        if !isLoaded {
            error = "No audio files could be loaded"
        }
    }

    func play() {
        if useWebPlayer {
            if isDualMode {
                webMicPlayer?.play()
                webSystemPlayer?.play()
            } else {
                webPlayer?.play()
            }
        } else {
            if isDualMode {
                micPlayer?.play()
                systemPlayer?.play()
            } else {
                audioPlayer?.play()
            }
            isPlaying = true
            startTimer()
        }
    }

    func pause() {
        if useWebPlayer {
            if isDualMode {
                webMicPlayer?.pause()
                webSystemPlayer?.pause()
            } else {
                webPlayer?.pause()
            }
        } else {
            if isDualMode {
                micPlayer?.pause()
                systemPlayer?.pause()
            } else {
                audioPlayer?.pause()
            }
            isPlaying = false
            stopTimer()
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, duration))
        if useWebPlayer {
            if isDualMode {
                webMicPlayer?.seek(to: clampedTime)
                webSystemPlayer?.seek(to: clampedTime)
            } else {
                webPlayer?.seek(to: clampedTime)
            }
        } else {
            if isDualMode {
                micPlayer?.currentTime = clampedTime
                systemPlayer?.currentTime = clampedTime
                currentTime = clampedTime
            } else {
                audioPlayer?.currentTime = clampedTime
                currentTime = audioPlayer?.currentTime ?? 0
            }
        }
    }

    func skip(seconds: TimeInterval) {
        let newTime = currentTime + seconds
        seek(to: newTime)
    }

    func setPlaybackRate(_ rate: Float) {
        if useWebPlayer {
            if isDualMode {
                webMicPlayer?.setPlaybackRate(rate)
                webSystemPlayer?.setPlaybackRate(rate)
            } else {
                webPlayer?.setPlaybackRate(rate)
            }
        } else {
            if isDualMode {
                micPlayer?.enableRate = true
                micPlayer?.rate = rate
                systemPlayer?.enableRate = true
                systemPlayer?.rate = rate
            } else {
                audioPlayer?.enableRate = true
                audioPlayer?.rate = rate
            }
        }
    }

    private func startTimer() {
        // Only needed for AVAudioPlayer (WebMAudioPlayer has its own time updates)
        guard !useWebPlayer else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.isDualMode {
                    self.currentTime = self.micPlayer?.currentTime ?? self.systemPlayer?.currentTime ?? 0
                } else {
                    self.currentTime = self.audioPlayer?.currentTime ?? 0
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.stopTimer()
        }
    }

    deinit {
        stopTimer()
        audioPlayer?.stop()
        micPlayer?.stop()
        systemPlayer?.stop()
        cancellables.removeAll()
    }
}

// MARK: - Session Playback View

struct SessionPlaybackView: View {
    @Binding var session: RecordingSession
    @ObservedObject var audioPlayer: AudioPlayerManager
    @Binding var autoScroll: Bool
    let syncOffset: Double

    @StateObject private var speakerLibrary = SpeakerLibrary.shared
    @State private var showingSegmentSpeakerPicker: SegmentSpeakerAssignment? = nil
    @State private var hoveredSegmentID: UUID? = nil

    /// Adjusted time for transcript highlighting (applies sync offset)
    private var adjustedTime: TimeInterval {
        audioPlayer.currentTime - syncOffset
    }

    var body: some View {
        HSplitView {
            // Left: Transcript with playback highlighting
            PlaybackTranscriptView(
                session: $session,
                currentTime: adjustedTime,  // Use adjusted time for highlighting
                autoScroll: autoScroll,
                hoveredSegmentID: $hoveredSegmentID,
                onSegmentTap: { segment in
                    // Seek to actual timestamp (not adjusted)
                    audioPlayer.seek(to: segment.timestamp + syncOffset)
                },
                onSpeakerTap: { segmentID, speakerID in
                    showingSegmentSpeakerPicker = SegmentSpeakerAssignment(id: segmentID, currentSpeakerID: speakerID)
                }
            )

            // Right: Speakers panel
            SpeakersPanelView(
                session: $session,
                speakerLibrary: speakerLibrary
            )
            .frame(minWidth: 200, maxWidth: 280)
        }
        .sheet(item: $showingSegmentSpeakerPicker) { assignment in
            SegmentSpeakerAssignmentSheet(
                session: $session,
                segmentID: assignment.id,
                speakerLibrary: speakerLibrary
            )
        }
    }
}

// MARK: - Playback Transcript View

struct PlaybackTranscriptView: View {
    @Binding var session: RecordingSession
    let currentTime: TimeInterval
    let autoScroll: Bool
    @Binding var hoveredSegmentID: UUID?
    let onSegmentTap: (TranscriptSegment) -> Void
    let onSpeakerTap: (UUID, Int?) -> Void  // (segmentID, currentSpeakerID)

    @State private var scrollProxy: ScrollViewProxy?

    /// Segments sorted by timestamp (combines mic + system in chronological order)
    private var sortedSegments: [TranscriptSegment] {
        session.transcriptSegments.sorted { $0.timestamp < $1.timestamp }
    }

    @State private var showingAddFirstSegment = false
    @State private var newSegmentText = ""
    @State private var newSegmentTimestamp: Double = 0
    @State private var newSegmentSpeakerID: Int?

    @State private var searchQuery: String = ""
    @State private var matches: [SearchMatch] = []
    @State private var currentMatchIndex: Int = 0

    private struct SearchMatch: Identifiable {
        let id = UUID()
        let segmentID: UUID
        let range: Range<String.Index>
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var transcriptSnapshot: String {
        session.transcriptSegments.map { "\($0.id.uuidString)|\($0.text)" }.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Add segment at start button
                        Button(action: {
                            newSegmentTimestamp = 0
                            newSegmentText = ""
                            newSegmentSpeakerID = session.speakers.first?.id
                            showingAddFirstSegment = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                                Text("Add segment at start")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)

                        ForEach(sortedSegments) { segment in
                            let isCurrentMatch = matches.indices.contains(currentMatchIndex)
                                ? matches[currentMatchIndex].segmentID == segment.id
                                : false

                            PlaybackSegmentView(
                                segment: segment,
                                speaker: session.speaker(for: segment.speakerID),
                                isActive: isSegmentActive(segment),
                                isPast: isSegmentPast(segment),
                                isHovered: hoveredSegmentID == segment.id,
                                searchQuery: trimmedQuery,
                                isCurrentMatch: isCurrentMatch,
                                onTap: { onSegmentTap(segment) },
                                onSpeakerTap: {
                                    onSpeakerTap(segment.id, segment.speakerID)
                                },
                                onTextChange: { newText in
                                    session.updateSegmentText(segmentID: segment.id, newText: newText)
                                },
                                onTimestampChange: { newTimestamp in
                                    session.updateSegmentTimestamp(segmentID: segment.id, newTimestamp: newTimestamp)
                                },
                                onAddSegmentAfter: { timestamp in
                                    session.insertSegment(
                                        text: "New segment",
                                        timestamp: timestamp,
                                        speakerID: segment.speakerID,
                                        source: segment.source
                                    )
                                },
                                onDeleteSegment: {
                                    session.deleteSegment(segmentID: segment.id)
                                }
                            )
                            .id(segment.id)
                            .onHover { isHovered in
                                hoveredSegmentID = isHovered ? segment.id : nil
                            }
                        }

                        // Add segment at end button
                        Button(action: {
                            let lastTimestamp = sortedSegments.last?.timestamp ?? 0
                            newSegmentTimestamp = lastTimestamp + 1
                            newSegmentText = ""
                            newSegmentSpeakerID = session.speakers.first?.id
                            showingAddFirstSegment = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                                Text("Add segment at end")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .onAppear {
                    scrollProxy = proxy
                    updateMatches(scrollToFirst: false)
                }
                .onChange(of: currentTime) { _, _ in
                    if autoScroll, let activeSegment = findActiveSegment() {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(activeSegment.id, anchor: .center)
                        }
                    }
                }
            }
        }
        .onChange(of: trimmedQuery) { _, _ in
            updateMatches(scrollToFirst: true)
        }
        .onChange(of: transcriptSnapshot) { _, _ in
            if !trimmedQuery.isEmpty {
                updateMatches(scrollToFirst: false)
            }
        }
        .sheet(isPresented: $showingAddFirstSegment) {
            AddSegmentSheet(
                timestamp: $newSegmentTimestamp,
                text: $newSegmentText,
                selectedSpeakerID: $newSegmentSpeakerID,
                speakers: session.speakers,
                onSave: {
                    session.insertSegment(
                        text: newSegmentText,
                        timestamp: newSegmentTimestamp,
                        speakerID: newSegmentSpeakerID,
                        source: .unknown
                    )
                    showingAddFirstSegment = false
                },
                onCancel: {
                    showingAddFirstSegment = false
                }
            )
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Buscar en la sesión…", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            Text(matches.isEmpty ? "0" : "\(currentMatchIndex + 1)/\(matches.count)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: goToPreviousMatch) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.bordered)
            .disabled(matches.isEmpty)

            Button(action: goToNextMatch) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.bordered)
            .disabled(matches.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
    }

    private func updateMatches(scrollToFirst: Bool) {
        let query = trimmedQuery
        guard !query.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }

        var newMatches: [SearchMatch] = []
        for segment in sortedSegments {
            for range in findRanges(in: segment.text, query: query) {
                newMatches.append(SearchMatch(segmentID: segment.id, range: range))
            }
        }

        matches = newMatches
        if matches.isEmpty {
            currentMatchIndex = 0
            return
        }

        if scrollToFirst || currentMatchIndex >= matches.count {
            currentMatchIndex = 0
        }

        scrollToCurrentMatch()
    }

    private func findRanges(in text: String, query: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange: Range<String.Index>? = text.startIndex..<text.endIndex

        while let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<text.endIndex
        }

        return ranges
    }

    private func goToPreviousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
        scrollToCurrentMatch()
    }

    private func goToNextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
        scrollToCurrentMatch()
    }

    private func scrollToCurrentMatch() {
        guard matches.indices.contains(currentMatchIndex) else { return }
        let segmentID = matches[currentMatchIndex].segmentID
        withAnimation(.easeInOut(duration: 0.25)) {
            scrollProxy?.scrollTo(segmentID, anchor: .center)
        }
    }

    private func isSegmentActive(_ segment: TranscriptSegment) -> Bool {
        let nextSegment = sortedSegments.first { $0.timestamp > segment.timestamp }
        let endTime = nextSegment?.timestamp ?? (segment.timestamp + 10)
        return currentTime >= segment.timestamp && currentTime < endTime
    }

    private func isSegmentPast(_ segment: TranscriptSegment) -> Bool {
        return currentTime >= segment.timestamp && !isSegmentActive(segment)
    }

    private func findActiveSegment() -> TranscriptSegment? {
        // Find the segment that contains current time
        var lastSegment: TranscriptSegment?
        for segment in sortedSegments {
            if segment.timestamp > currentTime {
                return lastSegment
            }
            lastSegment = segment
        }
        return lastSegment
    }
}

// MARK: - Playback Segment View

struct PlaybackSegmentView: View {
    let segment: TranscriptSegment
    let speaker: Speaker?
    let isActive: Bool
    let isPast: Bool
    let isHovered: Bool
    let searchQuery: String
    let isCurrentMatch: Bool
    let onTap: () -> Void
    let onSpeakerTap: () -> Void
    let onTextChange: (String) -> Void
    let onTimestampChange: (TimeInterval) -> Void  // Change timestamp
    let onAddSegmentAfter: (TimeInterval) -> Void  // Add segment after this one
    let onDeleteSegment: () -> Void  // Delete this segment

    @State private var isEditing = false
    @State private var editedText = ""
    @State private var isEditingTimestamp = false
    @State private var editedTimestampString: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp - double-click to edit, single click to seek
            if isEditingTimestamp {
                TextField("0:00.000", text: $editedTimestampString)
                    .textFieldStyle(.plain)
                    .frame(width: 70, alignment: .trailing)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(2)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
                    .onSubmit {
                        DispatchQueue.main.async {
                            if let newTime = parseTimestamp(editedTimestampString) {
                                onTimestampChange(newTime)
                            }
                            isEditingTimestamp = false
                        }
                    }
                    .onExitCommand {
                        DispatchQueue.main.async {
                            isEditingTimestamp = false
                        }
                    }
            } else {
                Text(formatTimestamp(segment.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .frame(width: 70, alignment: .trailing)
                    .onTapGesture(count: 2) {
                        // Double-click to edit
                        editedTimestampString = formatTimestamp(segment.timestamp)
                        isEditingTimestamp = true
                    }
                    .onTapGesture(count: 1) {
                        // Single click to seek
                        onTap()
                    }
                    .help("Double-click to edit, click to seek")
            }

            // Speaker indicator with color
            VStack(spacing: 4) {
                Circle()
                    .fill(speakerColor)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .scaleEffect(isActive ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: isActive)

                if !isActive {
                    Rectangle()
                        .fill(speakerColor.opacity(0.3))
                        .frame(width: 2)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Speaker name - click to open speaker picker modal
                Text(speaker?.displayName ?? "Unknown")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(speakerColor)
                    .onTapGesture {
                        onSpeakerTap()
                    }
                    .help("Click to change speaker")

                // Text content - inline editable with double-click
                if isEditing {
                    CommitTextView(
                        text: $editedText,
                        onCommit: {
                            DispatchQueue.main.async {
                                onTextChange(editedText)
                                isEditing = false
                            }
                        },
                        onCancel: {
                            DispatchQueue.main.async {
                                editedText = segment.text
                                isEditing = false
                            }
                        }
                    )
                    .frame(minHeight: 24)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
                } else {
                    HStack(alignment: .top) {
                        highlightedText(segment.text, query: searchQuery)
                            .font(.body)
                            .foregroundColor(isActive ? .primary : (isPast ? .primary.opacity(0.7) : .primary))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                // Double-click to edit
                                DispatchQueue.main.async {
                                    editedText = segment.text
                                    isEditing = true
                                }
                            }
                            .help("Double-click to edit")

                        Spacer()

                        // Action buttons - only show on hover
                        if isHovered {
                            HStack(spacing: 6) {
                                // Add segment after
                                Button(action: {
                                    onAddSegmentAfter(segment.timestamp + 0.5)
                                }) {
                                    Image(systemName: "plus.circle")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                .buttonStyle(.plain)
                                .help("Add segment after")

                                // Delete segment
                                Button(action: onDeleteSegment) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Delete segment")
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrentMatch ? Color.yellow.opacity(0.2) : backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var speakerColor: Color {
        if let colorHex = speaker?.color {
            return Color(hex: colorHex) ?? .gray
        }
        return .gray
    }

    private func highlightedText(_ text: String, query: String) -> Text {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var attributed = AttributedString(text)

        guard !trimmed.isEmpty else {
            return Text(attributed)
        }

        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            let lowerOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            let upperOffset = text.distance(from: text.startIndex, to: range.upperBound)
            let start = attributed.index(attributed.startIndex, offsetByCharacters: lowerOffset)
            let end = attributed.index(attributed.startIndex, offsetByCharacters: upperOffset)
            attributed[start..<end].backgroundColor = Color.yellow.opacity(0.5)
            searchRange = range.upperBound..<text.endIndex
        }

        return Text(attributed)
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.15)
        } else if isHovered {
            return Color(NSColor.controlBackgroundColor)
        } else {
            return Color.clear
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, secs, millis)
    }

    /// Parse timestamp string (m:ss.mmm) back to TimeInterval
    private func parseTimestamp(_ string: String) -> TimeInterval? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        // Try to parse m:ss.mmm or m:ss format
        let colonParts = trimmed.split(separator: ":")
        guard colonParts.count == 2,
              let minutes = Int(colonParts[0]) else {
            // Fallback: try to parse as plain number
            return Double(trimmed)
        }

        let secondsPart = String(colonParts[1])
        let dotParts = secondsPart.split(separator: ".")

        guard let secs = Int(dotParts[0]) else {
            return nil
        }

        var millis: Double = 0
        if dotParts.count == 2 {
            // Handle variable decimal places (e.g., .1, .12, .123)
            let millisStr = String(dotParts[1])
            if let millisInt = Int(millisStr) {
                // Normalize to milliseconds (e.g., "1" -> 100, "12" -> 120, "123" -> 123)
                let factor = pow(10.0, Double(3 - millisStr.count))
                millis = Double(millisInt) * factor / 1000.0
            }
        }

        return Double(minutes * 60) + Double(secs) + millis
    }
}

// MARK: - Commit Text View

struct CommitTextView: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    let font: NSFont
    let textColor: NSColor
    let isStrikethrough: Bool
    let isFocused: Binding<Bool>?
    let updatesBindingOnChange: Bool

    init(
        text: Binding<String>,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize),
        textColor: NSColor = NSColor.labelColor,
        isStrikethrough: Bool = false,
        isFocused: Binding<Bool>? = nil,
        updatesBindingOnChange: Bool = true
    ) {
        _text = text
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.font = font
        self.textColor = textColor
        self.isStrikethrough = isStrikethrough
        self.isFocused = isFocused
        self.updatesBindingOnChange = updatesBindingOnChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onCommit: onCommit,
            onCancel: onCancel,
            isFocused: isFocused,
            updatesBindingOnChange: updatesBindingOnChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = font
        textView.textColor = textColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("Commit text editor")
        textView.string = text

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = font
        textView.textColor = textColor
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        if isStrikethrough {
            textView.textStorage?.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: textView.string.count))
        } else {
            textView.textStorage?.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: textView.string.count))
        }

        if let isFocused, isFocused.wrappedValue, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let onCommit: () -> Void
        private let onCancel: () -> Void
        private let isFocused: Binding<Bool>?
        private let updatesBindingOnChange: Bool

        init(
            text: Binding<String>,
            onCommit: @escaping () -> Void,
            onCancel: @escaping () -> Void,
            isFocused: Binding<Bool>?,
            updatesBindingOnChange: Bool
        ) {
            self.text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
            self.isFocused = isFocused
            self.updatesBindingOnChange = updatesBindingOnChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if updatesBindingOnChange {
                text.wrappedValue = textView.string
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.typingAttributes[.strikethroughStyle] = 0
            isFocused?.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused?.wrappedValue = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewline(nil)
                    return true
                }
                if !updatesBindingOnChange {
                    text.wrappedValue = textView.string
                }
                onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                textView.insertNewline(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel()
                return true
            }
            return false
        }
    }
}

// MARK: - Playback Controls View

struct PlaybackControlsView: View {
    @ObservedObject var audioPlayer: AudioPlayerManager
    @Binding var autoScroll: Bool
    @Binding var playbackSpeed: Float
    @Binding var syncOffset: Double

    let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 12) {
            // Error message if any
            if let error = audioPlayer.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.horizontal)
            }

            // Loading indicator
            if !audioPlayer.isLoaded && audioPlayer.error == nil {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading audio...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }

            // Timeline scrubber
            TimelineScrubberView(
                currentTime: audioPlayer.currentTime,
                duration: audioPlayer.duration,
                onSeek: { time in
                    audioPlayer.seek(to: time)
                }
            )

            // Control buttons
            HStack(spacing: 24) {
                // Left side controls
                HStack(spacing: 12) {
                    // Auto-scroll toggle
                    Button(action: { autoScroll.toggle() }) {
                        Image(systemName: autoScroll ? "arrow.down.doc.fill" : "arrow.down.doc")
                            .font(.title3)
                            .foregroundColor(autoScroll ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(autoScroll ? "Auto-scroll enabled" : "Auto-scroll disabled")

                    // Speed picker with visible value
                    Menu {
                        ForEach(speedOptions, id: \.self) { speed in
                            Button(action: {
                                playbackSpeed = speed
                                audioPlayer.setPlaybackRate(speed)
                            }) {
                                HStack {
                                    Text("\(speed, specifier: "%.2g")x")
                                    if speed == playbackSpeed {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                                .font(.caption)
                            Text("\(playbackSpeed, specifier: "%.2g")x")
                                .font(.system(.caption, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .help("Playback speed")

                    // Sync offset adjustment
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Slider(value: $syncOffset, in: -2.0...2.0, step: 0.1)
                            .frame(width: 80)
                            .help("Sync offset: adjust if transcript is ahead or behind audio")

                        Text("\(syncOffset >= 0 ? "+" : "")\(syncOffset, specifier: "%.1f")s")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 40)
                    }
                }

                Spacer()

                // Center: Main controls
                HStack(spacing: 20) {
                    // Skip back 10s
                    Button(action: { audioPlayer.skip(seconds: -10) }) {
                        Image(systemName: "gobackward.10")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    // Skip back 5s
                    Button(action: { audioPlayer.skip(seconds: -5) }) {
                        Image(systemName: "gobackward.5")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    // Play/Pause
                    Button(action: { audioPlayer.togglePlayPause() }) {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!audioPlayer.isLoaded)

                    // Skip forward 5s
                    Button(action: { audioPlayer.skip(seconds: 5) }) {
                        Image(systemName: "goforward.5")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    // Skip forward 10s
                    Button(action: { audioPlayer.skip(seconds: 10) }) {
                        Image(systemName: "goforward.10")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }

                Spacer()

                // Dual audio volume controls (when in dual mode)
                if audioPlayer.isDualMode {
                    HStack(spacing: 16) {
                        // Mic volume
                        HStack(spacing: 4) {
                            Image(systemName: "mic.fill")
                                .font(.caption)
                                .foregroundColor(audioPlayer.micVolume > 0 ? .green : .secondary)
                            Slider(value: Binding(
                                get: { audioPlayer.micVolume },
                                set: { audioPlayer.micVolume = $0 }
                            ), in: 0...1)
                                .frame(width: 60)
                        }
                        .help("Microphone volume")

                        // System volume
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundColor(audioPlayer.systemVolume > 0 ? .blue : .secondary)
                            Slider(value: Binding(
                                get: { audioPlayer.systemVolume },
                                set: { audioPlayer.systemVolume = $0 }
                            ), in: 0...1)
                                .frame(width: 60)
                        }
                        .help("System audio volume")
                    }
                }

                // Right side: Time display
                HStack(spacing: 8) {
                    Text(formatTime(audioPlayer.currentTime))
                        .font(.system(.body, design: .monospaced))
                    Text("/")
                        .foregroundColor(.secondary)
                    Text(formatTime(audioPlayer.duration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(width: 120)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Timeline Scrubber View

struct TimelineScrubberView: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return (isDragging ? dragTime : currentTime) / duration
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.separatorColor))
                    .frame(height: 8)

                // Progress track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 8)

                // Scrubber handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(radius: 2)
                    .offset(x: max(0, min(geometry.size.width - 16, geometry.size.width * CGFloat(progress) - 8)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let percent = max(0, min(1, value.location.x / geometry.size.width))
                        dragTime = duration * Double(percent)
                    }
                    .onEnded { value in
                        isDragging = false
                        let percent = max(0, min(1, value.location.x / geometry.size.width))
                        onSeek(duration * Double(percent))
                    }
            )
            .onTapGesture { location in
                let percent = max(0, min(1, location.x / geometry.size.width))
                onSeek(duration * Double(percent))
            }
        }
        .frame(height: 16)
    }
}

// MARK: - Add Segment Sheet

struct AddSegmentSheet: View {
    @Binding var timestamp: Double
    @Binding var text: String
    @Binding var selectedSpeakerID: Int?
    let speakers: [Speaker]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Transcript Segment")
                .font(.headline)

            // Timestamp
            HStack {
                Text("Timestamp:")
                    .frame(width: 80, alignment: .trailing)
                TextField("0.0", value: $timestamp, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text("seconds")
                    .foregroundColor(.secondary)
            }

            // Speaker picker
            HStack {
                Text("Speaker:")
                    .frame(width: 80, alignment: .trailing)
                Picker("Speaker", selection: $selectedSpeakerID) {
                    Text("None").tag(nil as Int?)
                    ForEach(speakers) { speaker in
                        HStack {
                            Circle()
                                .fill(Color(hex: speaker.color) ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(speaker.displayName)
                        }
                        .tag(speaker.id as Int?)
                    }
                }
                .frame(width: 200)
            }

            // Text
            VStack(alignment: .leading) {
                Text("Text:")
                CommitTextView(
                    text: $text,
                    onCommit: onSave,
                    onCancel: onCancel
                )
                .frame(minHeight: 100)
                .border(Color.gray.opacity(0.3))
            }

            // Buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Segment", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var audioPlayer = AudioPlayerManager()
        @State private var autoScroll = true

        var body: some View {
            SessionPlaybackView(
                session: .constant(RecordingSession(
                    transcriptSegments: [
                        TranscriptSegment(timestamp: 0, text: "Hello, welcome to the meeting.", speakerID: 0),
                        TranscriptSegment(timestamp: 5, text: "Thanks for having me here today.", speakerID: 1),
                        TranscriptSegment(timestamp: 10, text: "Let's discuss the project timeline.", speakerID: 0),
                        TranscriptSegment(timestamp: 18, text: "I think we should start with the backend.", speakerID: 2),
                        TranscriptSegment(timestamp: 25, text: "That sounds like a good plan.", speakerID: 1),
                    ],
                    speakers: [
                        Speaker(id: 0, name: "Alice"),
                        Speaker(id: 1, name: "Bob"),
                        Speaker(id: 2, name: nil)
                    ],
                    audioFileName: "test.m4a"
                )),
                audioPlayer: audioPlayer,
                autoScroll: $autoScroll,
                syncOffset: 0.0
            )
            .frame(width: 900, height: 600)
        }
    }

    return PreviewWrapper()
}
