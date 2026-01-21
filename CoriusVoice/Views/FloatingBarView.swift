import SwiftUI
import AppKit

// MARK: - Floating Bar Controller

class FloatingBarController: NSObject {
    private var panel: FloatingBarPanel?
    private var hostingView: NSHostingView<FloatingBarContent>?

    override init() {
        super.init()
        setupPanel()
        setupObservers()
    }

    private func setupPanel() {
        panel = FloatingBarPanel()
        let contentView = FloatingBarContent()
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.frame = panel?.contentView?.bounds ?? .zero
        hostingView?.autoresizingMask = [.width, .height]
        panel?.contentView = hostingView
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
    }

    @objc private func handleRecordingStateChange(_ notification: Notification) {
        guard let pressed = notification.userInfo?["pressed"] as? Bool else { return }

        let settings = StorageService.shared.settings
        guard settings.showFloatingBar else { return }

        DispatchQueue.main.async {
            if pressed {
                self.show()
            } else {
                // Delay hiding to show final transcription
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !AppState.shared.isRecording {
                        self.hide()
                    }
                }
            }
        }
    }

    @objc private func handleTranscriptionUpdate(_ notification: Notification) {
        // Update is handled by SwiftUI bindings
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
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 72),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
    }
}

// MARK: - Floating Bar Content (SwiftUI)

struct FloatingBarContent: View {
    @StateObject private var viewModel = FloatingBarViewModel()

    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .scaleEffect(viewModel.isRecording ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: viewModel.isRecording)

            // Transcription text
            VStack(alignment: .leading, spacing: 4) {
                if viewModel.transcription.isEmpty {
                    Text("Listening...")
                        .font(.body)
                        .foregroundColor(.secondary)
                } else {
                    Text(viewModel.transcription)
                        .font(.body)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                }

                Text(viewModel.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Audio visualizer placeholder
            AudioVisualizerView(isActive: viewModel.isRecording)
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
}

// MARK: - Floating Bar View Model

class FloatingBarViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var transcription = ""
    @Published var duration = "0:00"

    private var timer: Timer?

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
    }

    @objc private func handleRecordingStateChange(_ notification: Notification) {
        guard let pressed = notification.userInfo?["pressed"] as? Bool else { return }

        DispatchQueue.main.async {
            self.isRecording = pressed

            if pressed {
                self.transcription = ""
                self.startTimer()
            } else {
                self.stopTimer()
            }
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
        .onChange(of: isActive) { active in
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
    FloatingBarContent()
        .frame(width: 380, height: 72)
}
