import Foundation
import AVFoundation

/// Voice Activity Detection (VAD) Service
/// Detects speech in audio buffers to avoid sending silent audio to Deepgram (saves tokens)
class VADService {
    static let shared = VADService()

    // MARK: - Configuration

    /// Energy threshold for detecting voice (RMS value)
    /// Typical voice: 0.02 - 0.2
    /// Silence: < 0.01
    var energyThreshold: Float = 0.015

    /// Minimum consecutive speech frames to confirm voice activity
    var minSpeechFrames: Int = 3

    /// Minimum consecutive silence frames before stopping
    var minSilenceFrames: Int = 10

    /// Hangover time: keep sending audio for a bit after speech ends (seconds)
    var hangoverTime: TimeInterval = 0.5

    // MARK: - State

    private var consecutiveSpeechFrames: Int = 0
    private var consecutiveSilenceFrames: Int = 0
    private var isSpeaking: Bool = false
    private var lastSpeechTime: Date?

    private init() {}

    // MARK: - Public Methods

    /// Analyze buffer and return whether it likely contains speech
    /// - Parameters:
    ///   - buffer: Audio buffer to analyze
    ///   - useHangover: If true, continues returning true for hangoverTime after speech ends
    /// - Returns: true if speech is detected, false otherwise
    func containsSpeech(_ buffer: AVAudioPCMBuffer, useHangover: Bool = true) -> Bool {
        let rms = calculateRMS(buffer)
        let hasEnergy = rms > energyThreshold

        if hasEnergy {
            consecutiveSpeechFrames += 1
            consecutiveSilenceFrames = 0
            lastSpeechTime = Date()

            // Start speaking after minimum consecutive speech frames
            if consecutiveSpeechFrames >= minSpeechFrames {
                isSpeaking = true
            }
        } else {
            consecutiveSilenceFrames += 1
            consecutiveSpeechFrames = 0

            // Stop speaking after minimum consecutive silence frames
            if consecutiveSilenceFrames >= minSilenceFrames && isSpeaking {
                isSpeaking = false
            }
        }

        // Use hangover to capture trailing words
        if useHangover, let lastSpeech = lastSpeechTime {
            let timeSinceSpeech = Date().timeIntervalSince(lastSpeech)
            if timeSinceSpeech < hangoverTime {
                return true
            }
        }

        return isSpeaking
    }

    /// Reset VAD state (call when starting a new recording)
    func reset() {
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        isSpeaking = false
        lastSpeechTime = nil
    }

    /// Get the current RMS level (for visualization)
    func getCurrentLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        return calculateRMS(buffer)
    }

    /// Check if currently in speaking state
    var isCurrentlySpeaking: Bool {
        return isSpeaking
    }

    // MARK: - Private Methods

    /// Calculate Root Mean Square (RMS) of the audio buffer
    /// RMS is a good measure of audio energy/loudness
    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        // Try Int16 format first (our converted format)
        if let int16Data = buffer.int16ChannelData {
            return calculateRMSFromInt16(int16Data[0], frameLength: Int(buffer.frameLength))
        }

        // Fall back to Float format
        if let floatData = buffer.floatChannelData {
            return calculateRMSFromFloat(floatData[0], frameLength: Int(buffer.frameLength))
        }

        return 0
    }

    private func calculateRMSFromFloat(_ data: UnsafePointer<Float>, frameLength: Int) -> Float {
        guard frameLength > 0 else { return 0 }

        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let sample = data[i]
            sumSquares += sample * sample
        }

        return sqrt(sumSquares / Float(frameLength))
    }

    private func calculateRMSFromInt16(_ data: UnsafePointer<Int16>, frameLength: Int) -> Float {
        guard frameLength > 0 else { return 0 }

        var sumSquares: Float = 0
        let scale: Float = 1.0 / 32768.0  // Normalize Int16 to -1.0...1.0

        for i in 0..<frameLength {
            let sample = Float(data[i]) * scale
            sumSquares += sample * sample
        }

        return sqrt(sumSquares / Float(frameLength))
    }

    // MARK: - Debug

    /// Get VAD state info for debugging
    var debugInfo: String {
        return "VAD: speaking=\(isSpeaking), speechFrames=\(consecutiveSpeechFrames), silenceFrames=\(consecutiveSilenceFrames)"
    }
}

// MARK: - VAD Statistics

extension VADService {
    struct Statistics {
        var totalFrames: Int = 0
        var speechFrames: Int = 0
        var silenceFrames: Int = 0

        var speechPercentage: Double {
            guard totalFrames > 0 else { return 0 }
            return Double(speechFrames) / Double(totalFrames) * 100
        }

        var tokensSaved: String {
            let saved = 100 - speechPercentage
            return String(format: "%.1f%%", saved)
        }
    }
}
