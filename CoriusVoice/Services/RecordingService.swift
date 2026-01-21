import Foundation
import AVFoundation

protocol RecordingServiceDelegate: AnyObject {
    func recordingServiceDidStartRecording()
    func recordingServiceDidStopRecording()
    func recordingServiceDidReceiveTranscript(_ text: String, isFinal: Bool)
    func recordingServiceDidEncounterError(_ error: Error)
}

class RecordingService: NSObject {
    static let shared = RecordingService()

    weak var delegate: RecordingServiceDelegate?

    private let audioCapture = AudioCaptureService.shared
    private let deepgram = DeepgramService.shared
    private let textCleanup = TextCleanupService.shared
    private let storage = StorageService.shared

    private var isRecording = false
    private var currentTranscript = ""
    private var interimTranscript = ""
    private var recordingStartTime: Date?
    private var keepAliveTimer: Timer?

    private override init() {
        super.init()
        audioCapture.delegate = self
        deepgram.delegate = self
    }

    var isCurrentlyRecording: Bool {
        return isRecording
    }

    func startRecording() {
        guard !isRecording else { return }

        let settings = storage.settings
        guard !settings.apiKey.isEmpty else {
            delegate?.recordingServiceDidEncounterError(RecordingError.noApiKey)
            return
        }

        isRecording = true
        currentTranscript = ""
        interimTranscript = ""
        recordingStartTime = Date()

        // Connect to Deepgram
        deepgram.connect(apiKey: settings.apiKey, language: settings.language)

        // Start audio capture
        do {
            try audioCapture.startCapture()
            delegate?.recordingServiceDidStartRecording()
            print("[RecordingService] Started recording")

            // Start keep-alive timer
            keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                self?.deepgram.sendKeepAlive()
            }
        } catch {
            isRecording = false
            delegate?.recordingServiceDidEncounterError(error)
            print("[RecordingService] Failed to start: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil

        audioCapture.stopCapture()
        deepgram.disconnect()

        delegate?.recordingServiceDidStopRecording()
        print("[RecordingService] Stopped recording")
    }

    func getCurrentTranscript() -> String {
        let settings = storage.settings
        let dictionary = storage.dictionaryEntries
        let snippets = storage.snippets

        let fullTranscript = currentTranscript + (interimTranscript.isEmpty ? "" : " " + interimTranscript)
        return textCleanup.cleanText(fullTranscript, settings: settings, dictionary: dictionary, snippets: snippets)
    }

    func getRecordingDuration() -> TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
}

// MARK: - AudioCaptureDelegate

extension RecordingService: AudioCaptureDelegate {
    func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording, let data = buffer.toData() else { return }
        deepgram.sendAudio(data)
    }

    func audioCaptureDidEncounterError(_ error: Error) {
        delegate?.recordingServiceDidEncounterError(error)
    }
}

// MARK: - DeepgramServiceDelegate

extension RecordingService: DeepgramServiceDelegate {
    func deepgramDidReceiveTranscript(_ transcript: DeepgramTranscript) {
        guard isRecording else { return }

        if transcript.isFinal {
            // Add to final transcript
            if !transcript.transcript.isEmpty {
                if !currentTranscript.isEmpty {
                    currentTranscript += " "
                }
                currentTranscript += transcript.transcript
            }
            interimTranscript = ""
        } else {
            // Update interim transcript
            interimTranscript = transcript.transcript
        }

        let cleanedTranscript = getCurrentTranscript()
        delegate?.recordingServiceDidReceiveTranscript(cleanedTranscript, isFinal: transcript.isFinal)

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .transcriptionReceived,
            object: nil,
            userInfo: ["text": cleanedTranscript, "isFinal": transcript.isFinal]
        )
    }

    func deepgramDidReceiveUtteranceEnd() {
        // Utterance ended - could trigger auto-stop if configured
        print("[RecordingService] Utterance ended")
    }

    func deepgramDidConnect() {
        print("[RecordingService] Deepgram connected")
    }

    func deepgramDidDisconnect(error: Error?) {
        if let error = error {
            print("[RecordingService] Deepgram disconnected with error: \(error.localizedDescription)")
            if isRecording {
                delegate?.recordingServiceDidEncounterError(error)
            }
        } else {
            print("[RecordingService] Deepgram disconnected")
        }
    }
}

// MARK: - Errors

enum RecordingError: Error, LocalizedError {
    case noApiKey
    case audioCaptureFailed
    case deepgramConnectionFailed

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Deepgram API key is not configured"
        case .audioCaptureFailed:
            return "Failed to capture audio from microphone"
        case .deepgramConnectionFailed:
            return "Failed to connect to Deepgram service"
        }
    }
}
