import SwiftUI

// MARK: - Speaker Chat View

struct SpeakerChatView: View {
    let speaker: KnownSpeaker
    @StateObject private var chatService = SpeakerChatService()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Chat messages
            messagesScrollView

            Divider()

            // Input area
            chatInputArea
        }
        .onAppear {
            chatService.startConversation(for: speaker)
        }
    }

    // MARK: - Messages Scroll View

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(visibleMessages) { message in
                        ChatMessageView(message: message, speaker: speaker)
                            .id(message.id)
                    }

                    // Streaming content
                    if chatService.isProcessing && !chatService.streamingContent.isEmpty {
                        StreamingMessageView(
                            content: chatService.streamingContent,
                            speaker: speaker
                        )
                        .id("streaming")
                    }

                    // Tool call indicator
                    if let toolName = chatService.currentToolCall {
                        ToolCallIndicator(toolName: toolName)
                            .id("tool-call")
                    }

                    // Thinking indicator
                    if chatService.isProcessing && chatService.streamingContent.isEmpty && chatService.currentToolCall == nil {
                        ThinkingIndicator()
                            .id("thinking")
                    }
                }
                .padding()
            }
            .onChange(of: chatService.conversation?.messages.count) { _ in
                withAnimation {
                    proxy.scrollTo(chatService.conversation?.messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: chatService.streamingContent) { _ in
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Chat Input Area

    private var chatInputArea: some View {
        VStack(spacing: 8) {
            // Error message
            if let error = chatService.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Dismiss") {
                        chatService.error = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            HStack(spacing: 12) {
                // Clear button
                Button(action: { chatService.clearConversation() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
                .disabled(chatService.isProcessing)

                // Text input
                CommitTextView(
                    text: $inputText,
                    onCommit: { sendMessage() },
                    onCancel: { inputText = "" }
                )
                .frame(minHeight: 24, maxHeight: 120)
                .focused($isInputFocused)
                .disabled(chatService.isProcessing)

                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(canSend ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    // MARK: - Computed Properties

    private var visibleMessages: [ChatMessage] {
        chatService.conversation?.messages.filter { message in
            // Hide system messages and tool messages from the UI
            message.role != .system && message.role != .tool
        } ?? []
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatService.isProcessing
    }

    // MARK: - Methods

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        Task {
            await chatService.sendMessage(text)
        }
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage
    let speaker: KnownSpeaker

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 60)
                userBubble
            } else {
                assistantBubble
                Spacer(minLength: 60)
            }
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(message.content ?? "")
                .padding(12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(16)
                .cornerRadius(4, corners: [.topRight])

            Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                // AI avatar
                Circle()
                    .fill(Color(hex: speaker.color) ?? .blue)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    if let content = message.content, !content.isEmpty {
                        MarkdownText(content)
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(16)
                            .cornerRadius(4, corners: [.topLeft])
                    }

                    // Show tool calls if any
                    if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                        ForEach(toolCalls) { call in
                            HStack(spacing: 4) {
                                Image(systemName: "wrench.fill")
                                    .font(.caption2)
                                Text("Used: \(call.function.name)")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 36)
        }
    }
}

// MARK: - Streaming Message View

struct StreamingMessageView: View {
    let content: String
    let speaker: KnownSpeaker

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color(hex: speaker.color) ?? .blue)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.white)
                    )

                MarkdownText(content)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(16)
                    .cornerRadius(4, corners: [.topLeft])
            }

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Tool Call Indicator

struct ToolCallIndicator: View {
    let toolName: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)

            Text(toolDisplayName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    private var toolDisplayName: String {
        switch toolName {
        case "search_sessions":
            return "Searching sessions..."
        case "get_transcript":
            return "Fetching transcript..."
        case "get_summary":
            return "Getting summary..."
        case "get_speaker_info":
            return "Loading speaker info..."
        case "list_workspace_actions":
            return "Loading action catalog..."
        case "execute_workspace_action":
            return "Executing workspace action..."
        case "confirm_workspace_action":
            return "Confirming action..."
        case "rollback_workspace_action":
            return "Rolling back action..."
        case "get_workspace_action_audit":
            return "Loading action audit..."
        default:
            return "Processing..."
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    @State private var animationOffset = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(animationOffset == index ? 1 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                animationOffset = (animationOffset + 1) % 3
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
    }
}

// MARK: - Markdown Text View

struct MarkdownText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        // Simple markdown rendering - for a full implementation, use a library
        Text(attributedString)
            .textSelection(.enabled)
    }

    private var attributedString: AttributedString {
        do {
            var result = try AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return result
        } catch {
            return AttributedString(content)
        }
    }
}

// Note: RoundedCorner, RectCorner, and related extensions are defined in Extensions.swift

#Preview {
    SpeakerChatView(speaker: KnownSpeaker(name: "Test Speaker"))
        .frame(width: 500, height: 600)
}
