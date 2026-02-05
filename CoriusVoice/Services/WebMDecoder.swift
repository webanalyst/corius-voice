import Foundation
import WebKit

/// Decodes WebM audio files to PCM Float32 samples using WebKit's AudioContext
/// This allows processing WebM files for diarization and other audio analysis
@MainActor
class WebMDecoder: NSObject {
    static let shared = WebMDecoder()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<(samples: [Float], sampleRate: Double), Error>?
    private var decodedSamples: [Float] = []
    private var decodedSampleRate: Double = 0

    private override init() {
        super.init()
    }

    /// Decode a WebM file to PCM Float32 samples
    /// - Parameter url: URL of the WebM file
    /// - Returns: Tuple of (samples, sampleRate)
    func decode(_ url: URL) async throws -> (samples: [Float], sampleRate: Double) {
        print("[WebMDecoder] 🎵 Decoding: \(url.lastPathComponent)")

        // Read file data
        let data = try Data(contentsOf: url)
        print("[WebMDecoder] 📦 File size: \(data.count) bytes")

        guard data.count > 0 else {
            throw WebMDecoderError.emptyFile
        }

        let base64String = data.base64EncodedString()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.decodedSamples = []
            self.decodedSampleRate = 0
            self.setupWebViewAndDecode(base64Data: base64String)
        }
    }

    private func setupWebViewAndDecode(base64Data: String) {
        // Create WebView configuration
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.configuration.userContentController.add(self, name: "decoderCallback")

        // HTML with JavaScript to decode audio using Web Audio API
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <script>
                async function decodeAudio(base64Data) {
                    try {
                        // Convert base64 to ArrayBuffer
                        const binaryString = atob(base64Data);
                        const len = binaryString.length;
                        const bytes = new Uint8Array(len);
                        for (let i = 0; i < len; i++) {
                            bytes[i] = binaryString.charCodeAt(i);
                        }

                        // Create AudioContext and decode
                        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
                        const audioBuffer = await audioContext.decodeAudioData(bytes.buffer);

                        // Get channel data (mono - use first channel or mix down)
                        let samples;
                        if (audioBuffer.numberOfChannels === 1) {
                            samples = audioBuffer.getChannelData(0);
                        } else {
                            // Mix down to mono
                            const left = audioBuffer.getChannelData(0);
                            const right = audioBuffer.getChannelData(1);
                            samples = new Float32Array(left.length);
                            for (let i = 0; i < left.length; i++) {
                                samples[i] = (left[i] + right[i]) / 2;
                            }
                        }

                        // Resample to 16kHz if needed (FluidAudio expects 16kHz)
                        const targetSampleRate = 16000;
                        let finalSamples = samples;
                        let finalSampleRate = audioBuffer.sampleRate;

                        if (audioBuffer.sampleRate !== targetSampleRate) {
                            // Simple linear resampling
                            const ratio = audioBuffer.sampleRate / targetSampleRate;
                            const newLength = Math.floor(samples.length / ratio);
                            finalSamples = new Float32Array(newLength);
                            for (let i = 0; i < newLength; i++) {
                                const srcIndex = i * ratio;
                                const srcIndexFloor = Math.floor(srcIndex);
                                const srcIndexCeil = Math.min(srcIndexFloor + 1, samples.length - 1);
                                const t = srcIndex - srcIndexFloor;
                                finalSamples[i] = samples[srcIndexFloor] * (1 - t) + samples[srcIndexCeil] * t;
                            }
                            finalSampleRate = targetSampleRate;
                        }

                        // Send samples back in chunks (to avoid message size limits)
                        const chunkSize = 100000;
                        const totalChunks = Math.ceil(finalSamples.length / chunkSize);

                        window.webkit.messageHandlers.decoderCallback.postMessage({
                            event: 'start',
                            sampleRate: finalSampleRate,
                            totalSamples: finalSamples.length,
                            totalChunks: totalChunks,
                            originalSampleRate: audioBuffer.sampleRate,
                            duration: audioBuffer.duration
                        });

                        for (let i = 0; i < totalChunks; i++) {
                            const start = i * chunkSize;
                            const end = Math.min(start + chunkSize, finalSamples.length);
                            const chunk = Array.from(finalSamples.slice(start, end));

                            window.webkit.messageHandlers.decoderCallback.postMessage({
                                event: 'chunk',
                                chunkIndex: i,
                                samples: chunk
                            });
                        }

                        window.webkit.messageHandlers.decoderCallback.postMessage({
                            event: 'complete'
                        });

                        audioContext.close();

                    } catch (error) {
                        window.webkit.messageHandlers.decoderCallback.postMessage({
                            event: 'error',
                            message: error.message || 'Unknown decoding error'
                        });
                    }
                }

                // Start decoding when page loads
                window.onload = function() {
                    decodeAudio('\(base64Data)');
                };
            </script>
        </head>
        <body></body>
        </html>
        """

        webView?.loadHTMLString(html, baseURL: nil)
    }

    private func cleanup() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "decoderCallback")
        webView = nil
    }
}

// MARK: - WKScriptMessageHandler

extension WebMDecoder: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String else {
            return
        }

        switch event {
        case "start":
            if let sampleRate = body["sampleRate"] as? Double,
               let totalSamples = body["totalSamples"] as? Int,
               let duration = body["duration"] as? Double {
                decodedSampleRate = sampleRate
                decodedSamples.reserveCapacity(totalSamples)
                print("[WebMDecoder] 📊 Decoding: \(totalSamples) samples, \(sampleRate)Hz, duration: \(String(format: "%.2f", duration))s")
            }

        case "chunk":
            if let samples = body["samples"] as? [Double] {
                decodedSamples.append(contentsOf: samples.map { Float($0) })
                if let chunkIndex = body["chunkIndex"] as? Int {
                    print("[WebMDecoder] 📦 Received chunk \(chunkIndex + 1), total samples: \(decodedSamples.count)")
                }
            }

        case "complete":
            print("[WebMDecoder] ✅ Decoding complete: \(decodedSamples.count) samples at \(decodedSampleRate)Hz")
            let samples = decodedSamples
            let sampleRate = decodedSampleRate
            cleanup()
            continuation?.resume(returning: (samples: samples, sampleRate: sampleRate))
            continuation = nil

        case "error":
            let message = body["message"] as? String ?? "Unknown error"
            print("[WebMDecoder] ❌ Error: \(message)")
            cleanup()
            continuation?.resume(throwing: WebMDecoderError.decodingFailed(message))
            continuation = nil

        default:
            break
        }
    }
}

// MARK: - Errors

enum WebMDecoderError: Error, LocalizedError {
    case emptyFile
    case decodingFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "WebM file is empty"
        case .decodingFailed(let message):
            return "Failed to decode WebM: \(message)"
        case .timeout:
            return "WebM decoding timed out"
        }
    }
}
