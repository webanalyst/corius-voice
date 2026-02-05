import SwiftUI
import AppKit
import Combine

// MARK: - Floating Bar Controller

class FloatingBarController: NSObject {
    private var panel: FloatingBarPanel?
    private var hostingView: NSHostingView<FloatingBarContent>?
    private var viewModel = FloatingBarViewModel()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        print("[FloatingBar] Initializing FloatingBarController")
        setupPanel()
        setupObservers()
        setupViewModelObservers()
        // Show the permanent indicator on launch
        print("[FloatingBar] Calling showPermanentIndicator")
        showPermanentIndicator()
    }

    private func setupPanel() {
        panel = FloatingBarPanel()
        let contentView = FloatingBarContent(viewModel: viewModel)
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.frame = panel?.contentView?.bounds ?? .zero
        hostingView?.autoresizingMask = [.width, .height]
        panel?.contentView = hostingView
    }

    private func setupViewModelObservers() {
        // Observe viewModel state changes to update panel size
        viewModel.$isRecording
            .combineLatest(viewModel.$isProcessing)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updatePanelSize()
            }
            .store(in: &cancellables)
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .settingsChanged,
            object: nil
        )
    }

    @objc private func handleSettingsChanged(_ notification: Notification) {
        let settings = StorageService.shared.settings
        if settings.showFloatingBar {
            showPermanentIndicator()
        } else {
            hide()
        }
    }

    func showPermanentIndicator() {
        let settings = StorageService.shared.settings
        guard settings.showFloatingBar else {
            print("[FloatingBar] showFloatingBar is disabled")
            return
        }

        print("[FloatingBar] Showing permanent indicator")
        updatePanelSize()
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func updatePanelSize() {
        guard let panel = panel, let hostingView = hostingView else { return }

        let newSize: NSSize
        if viewModel.isRecording {
            // Expanded size for recording
            newSize = NSSize(width: 140, height: 36)
        } else if viewModel.isProcessing {
            // Size for processing indicator
            newSize = NSSize(width: 80, height: 32)
        } else {
            // Compact idle indicator with green dot
            newSize = NSSize(width: 30, height: 18)
        }

        print("[FloatingBar] Updating size to: \(newSize) (recording: \(viewModel.isRecording), processing: \(viewModel.isProcessing))")

        // Update panel size
        var frame = panel.frame
        frame.size = newSize
        panel.setFrame(frame, display: true, animate: false)

        // Update hosting view frame
        hostingView.frame = NSRect(origin: .zero, size: newSize)

        // Reposition to correct location based on settings
        positionPanel()
    }

    func show() {
        positionPanel()
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func close() {
        hide()
        panel = nil
    }

    private func positionPanel() {
        guard let panel = panel, let screen = NSScreen.main else { return }

        let settings = StorageService.shared.settings
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size

        var origin: CGPoint

        switch settings.floatingBarPosition {
        case .topLeft:
            origin = CGPoint(
                x: screenFrame.minX + 20,
                y: screenFrame.maxY - panelSize.height - 20
            )
        case .topCenter:
            origin = CGPoint(
                x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.maxY - panelSize.height - 20
            )
        case .topRight:
            origin = CGPoint(
                x: screenFrame.maxX - panelSize.width - 20,
                y: screenFrame.maxY - panelSize.height - 20
            )
        case .bottomLeft:
            origin = CGPoint(
                x: screenFrame.minX + 20,
                y: screenFrame.minY + 20
            )
        case .bottomCenter:
            origin = CGPoint(
                x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.minY + 20
            )
        case .bottomRight:
            origin = CGPoint(
                x: screenFrame.maxX - panelSize.width - 20,
                y: screenFrame.minY + 20
            )
        }

        panel.setFrameOrigin(origin)
    }
}

// MARK: - Floating Bar Panel (NSPanel)

class FloatingBarPanel: NSPanel {
    init() {
        // Start with idle size
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 30, height: 18),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        // Ensure content view is also transparent
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = .clear
    }
}

// MARK: - Floating Bar Content (SwiftUI)

struct FloatingBarContent: View {
    @ObservedObject var viewModel: FloatingBarViewModel

    var body: some View {
        Group {
            if viewModel.isRecording {
                // Recording state: full controls
                recordingView
            } else if viewModel.isProcessing {
                // Processing state: loading indicator
                processingView
            } else {
                // Idle state: small indicator pill
                idleIndicator
            }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Idle Indicator (always visible)
    private var idleIndicator: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.green.opacity(0.8))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
        .help("Mantén pulsado FN para empezar a hablar")
    }

    // MARK: - Recording View
    private var recordingView: some View {
        HStack(spacing: 8) {
            // Cancel button (X)
            Button(action: {
                viewModel.cancelRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 20, height: 20)

                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .buttonStyle(.plain)

            // Waveform in center
            CompactWaveformView(levels: viewModel.audioLevels, isActive: true)
                .frame(width: 50, height: 14)

            // Stop button (red with square)
            Button(action: {
                viewModel.stopRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.85, blue: 0.85))
                        .frame(width: 20, height: 20)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(red: 0.75, green: 0.25, blue: 0.25))
                        .frame(width: 7, height: 7)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Processing View (loading)
    private var processingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)

            Text("...")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Compact Waveform (Wispr Flow style)

struct CompactWaveformView: View {
    let levels: [CGFloat]
    let isActive: Bool

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<min(levels.count, 12), id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: isActive ? max(2, levels[index] * 12) : 2)
                    .animation(.easeOut(duration: 0.06), value: levels[index])
            }
        }
    }
}

// MARK: - Live Waveform View

struct LiveWaveformView: View {
    let levels: [CGFloat]
    let isActive: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<min(levels.count, 15), id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.orange],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3, height: isActive ? levels[index] * 30 : 4)
                    .animation(.easeOut(duration: 0.05), value: levels[index])
            }
        }
    }
}

// MARK: - Floating Bar View Model

class FloatingBarViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false  // True during stop delay
    @Published var transcription = ""
    @Published var duration = "0:00"
    @Published var activeAppName = ""
    @Published var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 12)

    private var timer: Timer?
    private let contextService = ContextService.shared

    init() {
        setupObservers()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingStateChange),
            name: .fnKeyStateChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTranscriptionUpdate),
            name: .transcriptionReceived,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingDidFinish),
            name: .recordingDidFinish,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioLevelsUpdate),
            name: .audioLevelsUpdated,
            object: nil
        )
    }

    @objc private func handleAudioLevelsUpdate(_ notification: Notification) {
        guard let levels = notification.userInfo?["levels"] as? [CGFloat] else { return }
        DispatchQueue.main.async {
            self.audioLevels = levels
        }
    }

    @objc private func handleRecordingStateChange(_ notification: Notification) {
        guard let pressed = notification.userInfo?["pressed"] as? Bool else { return }

        DispatchQueue.main.async {
            if pressed {
                self.isRecording = true
                self.isProcessing = false
                self.transcription = ""
                // Get active app context
                let appContext = self.contextService.getActiveAppInfo()
                self.activeAppName = appContext.name
                self.startTimer()
            } else {
                // Fn released - switch to processing mode
                self.isRecording = false
                self.isProcessing = true
                self.stopTimer()
                self.resetAudioLevels()
            }
        }
    }

    @objc private func handleRecordingDidFinish(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isProcessing = false
        }
    }

    @objc private func handleTranscriptionUpdate(_ notification: Notification) {
        guard let text = notification.userInfo?["text"] as? String else { return }

        DispatchQueue.main.async {
            self.transcription = text
        }
    }

    private func startTimer() {
        var seconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            seconds += 1
            let mins = seconds / 60
            let secs = seconds % 60
            self?.duration = String(format: "%d:%02d", mins, secs)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func resetAudioLevels() {
        audioLevels = Array(repeating: 0.1, count: 12)
    }

    func cancelRecording() {
        // Cancel without transcribing
        isRecording = false
        isProcessing = false
        stopTimer()
        resetAudioLevels()
        // Notify to cancel the recording
        NotificationCenter.default.post(name: .recordingCancelled, object: nil)
    }

    func stopRecording() {
        // Stop and process transcription
        isRecording = false
        isProcessing = true
        stopTimer()
        resetAudioLevels()
        // Simulate Fn key release to trigger transcription
        NotificationCenter.default.post(
            name: .fnKeyStateChanged,
            object: nil,
            userInfo: ["pressed": false]
        )
    }
}

// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Audio Visualizer View

struct AudioVisualizerView: View {
    let isActive: Bool

    @State private var levels: [CGFloat] = [0.3, 0.5, 0.4, 0.6, 0.3]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: 4, height: levels[index] * 30)
            }
        }
        .onAppear {
            if isActive {
                animateLevels()
            }
        }
        .onReceive(Just(isActive)) { active in
            if active {
                animateLevels()
            } else {
                levels = [0.3, 0.5, 0.4, 0.6, 0.3]
            }
        }
    }

    private func animateLevels() {
        guard isActive else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            levels = (0..<5).map { _ in CGFloat.random(in: 0.2...1.0) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            animateLevels()
        }
    }
}

#Preview {
    FloatingBarContent(viewModel: FloatingBarViewModel())
        .frame(width: 140, height: 36)
}
