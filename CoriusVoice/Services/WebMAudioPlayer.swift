import Foundation
import WebKit
import Combine

/// Audio player that uses WKWebView to play WebM files natively
/// WebKit supports WebM/Opus since Safari 14.1 (macOS 11+)
class WebMAudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoaded = false
    @Published var error: String?
    @Published var volume: Float = 1.0 {
        didSet { setVolume(volume) }
    }

    private var webView: WKWebView?
    private var updateTimer: Timer?
    private var currentFileURL: URL?

    override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // Allow media playback without user gesture
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self

        // Add message handler for callbacks from JavaScript
        webView?.configuration.userContentController.add(self, name: "audioCallback")
    }

    /// Load a WebM (or any supported) audio file
    /// Uses base64 data URL to avoid WKWebView sandbox file access issues
    func load(url: URL) {
        currentFileURL = url
        isLoaded = false
        error = nil
        currentTime = 0
        duration = 0

        print("[WebMAudioPlayer] Loading: \(url.lastPathComponent)")
        print("[WebMAudioPlayer] Full path: \(url.path)")
        print("[WebMAudioPlayer] File exists: \(FileManager.default.fileExists(atPath: url.path))")

        // Read file and convert to base64 to avoid sandbox issues
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let data = try Data(contentsOf: url)
                print("[WebMAudioPlayer] File size: \(data.count) bytes (\(data.count / 1024) KB)")

                guard data.count > 0 else {
                    throw NSError(domain: "WebMAudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "File is empty"])
                }

                let base64String = data.base64EncodedString()
                print("[WebMAudioPlayer] Base64 length: \(base64String.count) chars")

                // Determine MIME type based on extension
                let ext = url.pathExtension.lowercased()
                let mimeType: String
                switch ext {
                case "webm": mimeType = "audio/webm"
                case "ogg", "oga": mimeType = "audio/ogg"
                case "mp3": mimeType = "audio/mpeg"
                case "m4a", "mp4", "aac": mimeType = "audio/mp4"
                case "wav": mimeType = "audio/wav"
                default: mimeType = "audio/webm"
                }

                // Use Blob URL approach instead of data URL for better compatibility with large files
                let html = """
                <!DOCTYPE html>
                <html>
                <head>
                    <style>
                        body { margin: 0; padding: 0; }
                        audio { display: none; }
                    </style>
                </head>
                <body>
                    <audio id="player" preload="auto"></audio>
                    <script>
                        const audio = document.getElementById('player');
                        const mimeType = '\(mimeType)';
                        const base64Data = '\(base64String)';

                        // Convert base64 to Blob and create object URL
                        function base64ToBlob(base64, type) {
                            const binaryString = atob(base64);
                            const len = binaryString.length;
                            const bytes = new Uint8Array(len);
                            for (let i = 0; i < len; i++) {
                                bytes[i] = binaryString.charCodeAt(i);
                            }
                            return new Blob([bytes], { type: type });
                        }

                        // SET UP ALL EVENT LISTENERS FIRST before setting src
                        audio.addEventListener('loadedmetadata', () => {
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'loaded',
                                duration: audio.duration
                            });
                        });

                        audio.addEventListener('timeupdate', () => {
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'timeupdate',
                                currentTime: audio.currentTime
                            });
                        });

                        audio.addEventListener('ended', () => {
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'ended'
                            });
                        });

                        audio.addEventListener('error', (e) => {
                            let errorMsg = 'Unknown error';
                            if (audio.error) {
                                const codes = {1: 'MEDIA_ERR_ABORTED', 2: 'MEDIA_ERR_NETWORK', 3: 'MEDIA_ERR_DECODE', 4: 'MEDIA_ERR_SRC_NOT_SUPPORTED'};
                                errorMsg = codes[audio.error.code] || ('Code: ' + audio.error.code);
                                if (audio.error.message) errorMsg += ' - ' + audio.error.message;
                            }
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'error',
                                message: errorMsg
                            });
                        });

                        audio.addEventListener('canplay', () => {
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'canplay',
                                duration: audio.duration
                            });
                        });

                        audio.addEventListener('play', () => {
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'play'
                            });
                        });

                        audio.addEventListener('pause', () => {
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'pause'
                            });
                        });

                        // Check browser codec support
                        const canPlay = audio.canPlayType(mimeType);
                        const canPlayOpus = audio.canPlayType('audio/webm; codecs="opus"');
                        const canPlayVorbis = audio.canPlayType('audio/webm; codecs="vorbis"');
                        window.webkit.messageHandlers.audioCallback.postMessage({
                            event: 'codeccheck',
                            mimeType: mimeType,
                            canPlay: canPlay || 'empty',
                            canPlayOpus: canPlayOpus || 'empty',
                            canPlayVorbis: canPlayVorbis || 'empty'
                        });

                        // NOW create blob and set src
                        try {
                            const blob = base64ToBlob(base64Data, mimeType);
                            const blobUrl = URL.createObjectURL(blob);
                            audio.src = blobUrl;
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'blobcreated',
                                blobSize: blob.size,
                                blobUrl: blobUrl.substring(0, 50)
                            });
                        } catch(e) {
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'error',
                                message: 'Blob creation failed: ' + e.message
                            });
                        }

                        // Immediately notify Swift that JS is running
                        try {
                            window.webkit.messageHandlers.audioCallback.postMessage({
                                event: 'jsready',
                                srcLength: audio.src ? audio.src.length : 0
                            });
                        } catch(e) {
                            console.error('Failed to send jsready:', e);
                        }

                        // Check if audio has error immediately
                        setTimeout(() => {
                            if (audio.error) {
                                window.webkit.messageHandlers.audioCallback.postMessage({
                                    event: 'error',
                                    message: 'Delayed error check: code ' + audio.error.code
                                });
                            } else if (audio.readyState === 0) {
                                window.webkit.messageHandlers.audioCallback.postMessage({
                                    event: 'debug',
                                    message: 'readyState still 0 after 500ms, networkState: ' + audio.networkState
                                });
                            } else {
                                window.webkit.messageHandlers.audioCallback.postMessage({
                                    event: 'debug',
                                    message: 'Audio ready after 500ms, readyState: ' + audio.readyState + ', duration: ' + audio.duration
                                });
                            }
                        }, 500);

                        // Longer check in case loading is slow
                        setTimeout(() => {
                            if (!audio.error && audio.readyState >= 2 && !isNaN(audio.duration) && audio.duration > 0) {
                                // Force emit loaded if we haven't already
                                window.webkit.messageHandlers.audioCallback.postMessage({
                                    event: 'loaded',
                                    duration: audio.duration,
                                    forcedEmit: true
                                });
                            } else if (audio.readyState === 0) {
                                window.webkit.messageHandlers.audioCallback.postMessage({
                                    event: 'error',
                                    message: 'Audio failed to load after 2s. readyState: ' + audio.readyState + ', networkState: ' + audio.networkState
                                });
                            }
                        }, 2000);

                        // Functions callable from Swift
                        function play() { audio.play(); }
                        function pause() { audio.pause(); }
                        function seek(time) { audio.currentTime = time; }
                        function setVolume(vol) { audio.volume = vol; }
                        function setPlaybackRate(rate) { audio.playbackRate = rate; }
                        function getState() {
                            return {
                                currentTime: audio.currentTime,
                                duration: audio.duration,
                                paused: audio.paused,
                                volume: audio.volume
                            };
                        }
                    </script>
                </body>
                </html>
                """

                DispatchQueue.main.async {
                    self.webView?.loadHTMLString(html, baseURL: nil)
                    print("[WebMAudioPlayer] Loaded as base64 data URL (\(data.count / 1024)KB)")
                }

            } catch {
                DispatchQueue.main.async {
                    self.error = "Failed to read file: \(error.localizedDescription)"
                    print("[WebMAudioPlayer] Error reading file: \(error)")
                }
            }
        }
    }

    func play() {
        webView?.evaluateJavaScript("play()") { [weak self] _, error in
            if let error = error {
                print("[WebMAudioPlayer] Play error: \(error)")
                self?.error = error.localizedDescription
            }
        }
    }

    func pause() {
        webView?.evaluateJavaScript("pause()") { [weak self] _, error in
            if let error = error {
                print("[WebMAudioPlayer] Pause error: \(error)")
            }
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
        webView?.evaluateJavaScript("seek(\(clampedTime))") { [weak self] _, error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.currentTime = clampedTime
                }
            }
        }
    }

    func skip(seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    private func setVolume(_ volume: Float) {
        let clampedVolume = max(0, min(1, volume))
        webView?.evaluateJavaScript("setVolume(\(clampedVolume))") { _, _ in }
    }

    func setPlaybackRate(_ rate: Float) {
        webView?.evaluateJavaScript("setPlaybackRate(\(rate))") { _, _ in }
    }

    deinit {
        updateTimer?.invalidate()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "audioCallback")
    }
}

// MARK: - WKNavigationDelegate

extension WebMAudioPlayer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[WebMAudioPlayer] WebView loaded, checking audio state...")

        // Check the audio element state immediately after load
        webView.evaluateJavaScript("""
            (function() {
                const audio = document.getElementById('player');
                if (!audio) return { error: 'No audio element found' };
                return {
                    srcLength: audio.src ? audio.src.length : 0,
                    readyState: audio.readyState,
                    networkState: audio.networkState,
                    paused: audio.paused,
                    duration: audio.duration,
                    error: audio.error ? audio.error.code : null
                };
            })()
        """) { [weak self] result, error in
            if let error = error {
                print("[WebMAudioPlayer] ❌ JS eval error: \(error)")
            } else if let state = result as? [String: Any] {
                print("[WebMAudioPlayer] 🔍 Audio state: \(state)")
                // readyState: 0=HAVE_NOTHING, 1=HAVE_METADATA, 2=HAVE_CURRENT_DATA, 3=HAVE_FUTURE_DATA, 4=HAVE_ENOUGH_DATA
                // networkState: 0=EMPTY, 1=IDLE, 2=LOADING, 3=NO_SOURCE

                if let errorCode = state["error"] as? Int {
                    let errorMsg: String
                    switch errorCode {
                    case 1: errorMsg = "MEDIA_ERR_ABORTED"
                    case 2: errorMsg = "MEDIA_ERR_NETWORK"
                    case 3: errorMsg = "MEDIA_ERR_DECODE"
                    case 4: errorMsg = "MEDIA_ERR_SRC_NOT_SUPPORTED"
                    default: errorMsg = "Unknown error \(errorCode)"
                    }
                    print("[WebMAudioPlayer] ❌ Audio error: \(errorMsg)")
                    DispatchQueue.main.async {
                        self?.error = errorMsg
                    }
                }
            }
        }

        // Schedule another check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, !self.isLoaded else { return }
            print("[WebMAudioPlayer] ⏰ Delayed state check (audio still not loaded)...")

            webView.evaluateJavaScript("""
                (function() {
                    const audio = document.getElementById('player');
                    if (!audio) return { error: 'No audio element found' };
                    return {
                        srcLength: audio.src ? audio.src.length : 0,
                        readyState: audio.readyState,
                        networkState: audio.networkState,
                        duration: audio.duration,
                        error: audio.error ? audio.error.code : null
                    };
                })()
            """) { result, error in
                if let state = result as? [String: Any] {
                    print("[WebMAudioPlayer] 🔍 Delayed audio state: \(state)")
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WebMAudioPlayer] Navigation error: \(error)")
        self.error = error.localizedDescription
    }
}

// MARK: - WKScriptMessageHandler

extension WebMAudioPlayer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch event {
            case "loaded":
                if let dur = body["duration"] as? Double {
                    self.duration = dur
                    self.isLoaded = true
                    print("[WebMAudioPlayer] Loaded, duration: \(dur)s")
                }

            case "timeupdate":
                if let time = body["currentTime"] as? Double {
                    self.currentTime = time
                }

            case "play":
                self.isPlaying = true

            case "pause":
                self.isPlaying = false

            case "ended":
                self.isPlaying = false
                self.currentTime = self.duration

            case "canplay":
                if let dur = body["duration"] as? Double {
                    print("[WebMAudioPlayer] Can play, duration: \(dur)s")
                    if !self.isLoaded {
                        self.duration = dur
                        self.isLoaded = true
                    }
                }

            case "error":
                let msg = body["message"] as? String ?? "Playback error"
                self.error = msg
                print("[WebMAudioPlayer] ❌ Error: \(msg)")

            case "jsready":
                let srcLen = body["srcLength"] as? Int ?? 0
                print("[WebMAudioPlayer] ✅ JavaScript ready, src length: \(srcLen)")

            case "debug":
                let msg = body["message"] as? String ?? "Debug message"
                print("[WebMAudioPlayer] 🔍 Debug: \(msg)")

            case "blobcreated":
                let size = body["blobSize"] as? Int ?? 0
                let url = body["blobUrl"] as? String ?? "unknown"
                print("[WebMAudioPlayer] ✅ Blob created: \(size) bytes, URL: \(url)...")

            case "codeccheck":
                let mime = body["mimeType"] as? String ?? "unknown"
                let canPlay = body["canPlay"] as? String ?? "unknown"
                let canPlayOpus = body["canPlayOpus"] as? String ?? "unknown"
                let canPlayVorbis = body["canPlayVorbis"] as? String ?? "unknown"
                print("[WebMAudioPlayer] 🔍 Codec support for \(mime):")
                print("  - canPlayType('\(mime)'): \(canPlay)")
                print("  - canPlayType('audio/webm; codecs=\"opus\"'): \(canPlayOpus)")
                print("  - canPlayType('audio/webm; codecs=\"vorbis\"'): \(canPlayVorbis)")
                if canPlay == "empty" && canPlayOpus == "empty" {
                    print("[WebMAudioPlayer] ⚠️ WebM/Opus may not be supported!")
                }

            default:
                print("[WebMAudioPlayer] Unknown event: \(event)")
            }
        }
    }
}

// MARK: - Dual Audio Support

/// Manager for playing dual audio streams (mic + system) using WebM
class DualWebMAudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoaded = false
    @Published var error: String?

    @Published var micVolume: Float = 1.0 {
        didSet { micPlayer.volume = micVolume }
    }
    @Published var systemVolume: Float = 1.0 {
        didSet { systemPlayer.volume = systemVolume }
    }

    private let micPlayer = WebMAudioPlayer()
    private let systemPlayer = WebMAudioPlayer()
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
    }

    private func setupBindings() {
        // Use mic player as the time reference
        micPlayer.$currentTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTime)

        micPlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPlaying)

        // Duration is the max of both
        Publishers.CombineLatest(micPlayer.$duration, systemPlayer.$duration)
            .map { max($0, $1) }
            .receive(on: DispatchQueue.main)
            .assign(to: &$duration)

        // Loaded when both are ready (or at least one if only one exists)
        Publishers.CombineLatest(micPlayer.$isLoaded, systemPlayer.$isLoaded)
            .map { $0 || $1 }
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoaded)
    }

    func load(micURL: URL?, systemURL: URL?) {
        if let url = micURL {
            micPlayer.load(url: url)
        }
        if let url = systemURL {
            systemPlayer.load(url: url)
        }
    }

    func play() {
        micPlayer.play()
        systemPlayer.play()
    }

    func pause() {
        micPlayer.pause()
        systemPlayer.pause()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        micPlayer.seek(to: time)
        systemPlayer.seek(to: time)
    }

    func skip(seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func setPlaybackRate(_ rate: Float) {
        micPlayer.setPlaybackRate(rate)
        systemPlayer.setPlaybackRate(rate)
    }
}
