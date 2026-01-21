import Foundation

protocol DeepgramServiceDelegate: AnyObject {
    func deepgramDidReceiveTranscript(_ transcript: DeepgramTranscript)
    func deepgramDidReceiveUtteranceEnd()
    func deepgramDidConnect()
    func deepgramDidDisconnect(error: Error?)
}

class DeepgramService {
    static let shared = DeepgramService()

    weak var delegate: DeepgramServiceDelegate?

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false

    private init() {}

    func connect(apiKey: String, language: String? = nil) {
        guard !apiKey.isEmpty else {
            print("[Deepgram] API key is empty")
            return
        }

        disconnect()

        var urlComponents = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        urlComponents.queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "utterance_end_ms", value: "5000"),
            URLQueryItem(name: "vad_events", value: "true"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "diarize", value: "false")
        ]

        if let lang = language {
            urlComponents.queryItems?.append(URLQueryItem(name: "language", value: lang))
        }

        guard let url = urlComponents.url else {
            print("[Deepgram] Failed to create URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        urlSession = URLSession(configuration: .default)
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()

        isConnected = true
        delegate?.deepgramDidConnect()

        print("[Deepgram] Connected to WebSocket")

        receiveMessages()
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        if isConnected {
            isConnected = false
            delegate?.deepgramDidDisconnect(error: nil)
            print("[Deepgram] Disconnected")
        }
    }

    func sendAudio(_ data: Data) {
        guard isConnected, let webSocket = webSocket else { return }

        webSocket.send(.data(data)) { error in
            if let error = error {
                print("[Deepgram] Send error: \(error.localizedDescription)")
            }
        }
    }

    func sendKeepAlive() {
        guard isConnected else { return }

        let keepAlive = ["type": "KeepAlive"]
        if let data = try? JSONSerialization.data(withJSONObject: keepAlive) {
            webSocket?.send(.data(data)) { _ in }
        }
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }

                // Continue receiving
                self.receiveMessages()

            case .failure(let error):
                print("[Deepgram] Receive error: \(error.localizedDescription)")
                self.isConnected = false
                self.delegate?.deepgramDidDisconnect(error: error)
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let type = json["type"] as? String {
                    switch type {
                    case "Results":
                        if let transcript = parseTranscript(json) {
                            DispatchQueue.main.async {
                                self.delegate?.deepgramDidReceiveTranscript(transcript)
                            }
                        }

                    case "UtteranceEnd":
                        DispatchQueue.main.async {
                            self.delegate?.deepgramDidReceiveUtteranceEnd()
                        }

                    case "Metadata":
                        print("[Deepgram] Metadata received")

                    default:
                        break
                    }
                }
            }
        } catch {
            print("[Deepgram] Parse error: \(error.localizedDescription)")
        }
    }

    private func parseTranscript(_ json: [String: Any]) -> DeepgramTranscript? {
        guard let channel = (json["channel"] as? [String: Any]),
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlternative = alternatives.first,
              let transcript = firstAlternative["transcript"] as? String else {
            return nil
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let speechFinal = json["speech_final"] as? Bool ?? false
        let confidence = firstAlternative["confidence"] as? Double ?? 0

        // Parse words if available
        var words: [DeepgramWord] = []
        if let wordsArray = firstAlternative["words"] as? [[String: Any]] {
            words = wordsArray.compactMap { wordDict -> DeepgramWord? in
                guard let word = wordDict["word"] as? String,
                      let start = wordDict["start"] as? Double,
                      let end = wordDict["end"] as? Double else {
                    return nil
                }
                let wordConfidence = wordDict["confidence"] as? Double ?? 0
                return DeepgramWord(word: word, start: start, end: end, confidence: wordConfidence)
            }
        }

        return DeepgramTranscript(
            transcript: transcript,
            confidence: confidence,
            isFinal: isFinal,
            speechFinal: speechFinal,
            words: words
        )
    }
}

// MARK: - Models

struct DeepgramTranscript {
    let transcript: String
    let confidence: Double
    let isFinal: Bool
    let speechFinal: Bool
    let words: [DeepgramWord]
}

struct DeepgramWord {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double
}
