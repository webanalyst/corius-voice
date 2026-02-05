import Foundation

// MARK: - Session Type (defined here for Settings dependency)

enum SessionType: String, Codable, CaseIterable {
    case meeting = "meeting"
    case interview = "interview"
    case brainstorm = "brainstorm"
    case lecture = "lecture"
    case other = "other"

    var displayName: String {
        switch self {
        case .meeting: return "Meeting"
        case .interview: return "Interview"
        case .brainstorm: return "Brainstorm"
        case .lecture: return "Lecture"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .meeting: return "person.3.fill"
        case .interview: return "person.2.wave.2.fill"
        case .brainstorm: return "lightbulb.fill"
        case .lecture: return "book.fill"
        case .other: return "doc.text.fill"
        }
    }

    /// Prompt template instructions for the AI summarizer
    var promptInstructions: String {
        switch self {
        case .meeting:
            return """
            Focus on:
            - Decisions made during the meeting
            - Action items with assignees and deadlines if mentioned
            - Key discussion points and outcomes
            - Open questions or parking lot items
            - Next steps agreed upon
            """

        case .interview:
            return """
            Focus on:
            - Candidate qualifications and experience discussed
            - Key strengths demonstrated
            - Areas of concern or gaps identified
            - Notable responses to questions
            - Overall fit assessment based on the conversation
            """

        case .brainstorm:
            return """
            Focus on:
            - Main topic or problem being addressed
            - All ideas generated (even wild ones)
            - Most promising concepts identified
            - Challenges and constraints discussed
            - Next steps for developing ideas
            """

        case .lecture:
            return """
            Focus on:
            - Main topic and subtopics covered
            - Key concepts and their explanations
            - Important details and facts
            - Examples and illustrations given
            - Questions raised during the lecture
            - Study points for review
            """

        case .other:
            return """
            Focus on:
            - Main topics discussed
            - Key points and takeaways
            - Any decisions or conclusions reached
            - Notable quotes or insights
            - Follow-up items if applicable
            """
        }
    }

    /// Template structure for the summary output
    var templateStructure: String {
        switch self {
        case .meeting:
            return """
            ## General Summary
            - **Topic 1:** Brief description of what was discussed and outcome (MM:SS)
            - **Topic 2:** Brief description of what was discussed and outcome (MM:SS)
            - **Topic 3:** Brief description of what was discussed and outcome (MM:SS)
            [Continue for all major topics discussed]

            ## Notes

            ### [Topic 1 Title]
            [Detailed explanation of what was discussed about this topic]

            - Key point with specific detail from the conversation (MM:SS)
            - Another important point that was mentioned (MM:SS)
            - Decision or conclusion reached on this topic
            - Impact or implications discussed

            ### [Topic 2 Title]
            [Detailed explanation of what was discussed about this topic]

            - Key point with timestamp reference (MM:SS)
            - Supporting details and context
            - Relevant quotes or specific mentions

            [Continue for each major topic]

            ## Action Items

            ### [Person Name]
            - Task description with context (MM:SS)
            - Another task for this person (MM:SS)

            ### [Another Person]
            - Their assigned task with context (MM:SS)

            ### Unassigned
            - Task that needs an owner assigned (MM:SS)
            - Follow-up item without clear assignee (MM:SS)
            """

        case .interview:
            return """
            ## General Summary
            - **Candidate Profile:** Brief summary of the candidate and position discussed (MM:SS)
            - **Key Strengths:** Main strengths demonstrated during the interview (MM:SS)
            - **Areas of Concern:** Any concerns or gaps identified (MM:SS)
            - **Overall Assessment:** General impression and fit evaluation (MM:SS)

            ## Notes

            ### Candidate Background
            Detailed notes about the candidate's background and experience discussed.

            - Specific experience or qualification mentioned (MM:SS)
            - Relevant skills demonstrated (MM:SS)
            - Career trajectory and motivations

            ### Technical/Role Assessment
            Assessment of candidate's capabilities for the role.

            - Response to specific question or scenario (MM:SS)
            - Technical knowledge demonstrated (MM:SS)
            - Problem-solving approach observed

            ### Cultural Fit
            Notes on alignment with company values and team dynamics.

            - Relevant observation about communication style (MM:SS)
            - Team collaboration indicators (MM:SS)

            ### Notable Responses
            - Q: [Question asked] → A: [Key response] (MM:SS)
            - Q: [Another question] → A: [Response] (MM:SS)

            ## Action Items

            ### Hiring Manager
            - Decision or follow-up action (MM:SS)

            ### Recruiter
            - Next steps in the process (MM:SS)

            ### Unassigned
            - Additional follow-up items (MM:SS)

            ## Recommendation
            [Summary of fit and hiring recommendation with supporting evidence]
            """

        case .brainstorm:
            return """
            ## General Summary
            - **Main Problem:** The challenge or opportunity being addressed (MM:SS)
            - **Key Ideas:** Most significant ideas generated (MM:SS)
            - **Consensus:** Areas where participants agreed (MM:SS)
            - **Next Steps:** Decided direction forward (MM:SS)

            ## Notes

            ### Problem Definition
            Detailed description of the problem or opportunity being addressed.

            - How the problem was framed (MM:SS)
            - Context and constraints discussed (MM:SS)
            - Goals and success criteria defined

            ### Ideas Generated
            All ideas proposed during the session.

            - **Idea 1:** Description and who proposed it (MM:SS)
            - **Idea 2:** Description and discussion around it (MM:SS)
            - **Idea 3:** Description and potential (MM:SS)
            [Continue for all ideas]

            ### Most Promising Concepts
            Ideas that received the most support or interest.

            - **Concept:** Why it's promising and next steps to explore (MM:SS)
            - Supporting arguments and potential challenges

            ### Challenges & Constraints
            Obstacles and limitations identified.

            - Challenge and its impact on solutions (MM:SS)
            - Resource or technical constraints mentioned

            ## Action Items

            ### [Person Name]
            - Idea or concept they will explore further (MM:SS)

            ### Unassigned
            - Ideas needing an owner (MM:SS)
            - Research or validation needed (MM:SS)
            """

        case .lecture:
            return """
            ## General Summary
            - **Main Topic:** The subject covered in this lecture (MM:SS)
            - **Key Concepts:** Most important concepts introduced (MM:SS)
            - **Applications:** How concepts apply in practice (MM:SS)
            - **Study Focus:** Areas to review for retention (MM:SS)

            ## Notes

            ### [Main Topic/Concept 1]
            Detailed explanation of this concept.

            - Key definition or principle explained (MM:SS)
            - Supporting details and nuances (MM:SS)
            - How it connects to other concepts

            ### [Subtopic/Concept 2]
            Detailed explanation of this subtopic.

            - Important points covered (MM:SS)
            - Examples or illustrations given (MM:SS)

            ### Examples & Applications
            Concrete examples provided during the lecture.

            - **Example 1:** Description and what it illustrates (MM:SS)
            - **Example 2:** Description and key takeaway (MM:SS)

            ### Questions & Clarifications
            Questions raised during the lecture and their answers.

            - Q: [Question asked] → A: [Answer provided] (MM:SS)
            - Clarification or additional context given (MM:SS)

            ## Action Items

            ### Student/Self
            - Topic to study further (MM:SS)
            - Exercise or practice recommended (MM:SS)

            ### Unassigned
            - Questions to research (MM:SS)
            - Materials to review (MM:SS)

            ## Study Points
            Key areas to focus on for review and retention.

            - Concept that needs more study (MM:SS)
            - Important formula/process to memorize (MM:SS)
            """

        case .other:
            return """
            ## General Summary
            - **Topic 1:** Brief description of what was discussed (MM:SS)
            - **Topic 2:** Brief description of what was discussed (MM:SS)
            - **Outcome:** Key conclusions or decisions reached (MM:SS)

            ## Notes

            ### [Topic 1]
            Detailed notes about this topic.

            - Key point discussed with context (MM:SS)
            - Additional details or clarifications (MM:SS)
            - Conclusions or outcomes

            ### [Topic 2]
            Detailed notes about this topic.

            - Key point discussed (MM:SS)
            - Supporting information (MM:SS)

            ### Notable Insights
            Important observations or insights from the session.

            - Insight or observation with context (MM:SS)
            - Implications or significance

            ## Action Items

            ### [Person Name]
            - Task or follow-up for this person (MM:SS)

            ### Unassigned
            - Item needing follow-up (MM:SS)
            - Open question to resolve (MM:SS)
            """
        }
    }
}

// MARK: - Audio Source (defined here for Settings dependency)

enum AudioSource: String, Codable, CaseIterable {
    case microphone = "microphone"
    case systemAudio = "system_audio"
    case both = "both"

    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        case .both: return "Microphone + System Audio"
        }
    }

    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .systemAudio: return "speaker.wave.2.fill"
        case .both: return "speaker.wave.2.bubble.left.fill"
        }
    }
}

// MARK: - App Settings

struct AppSettings: Codable {
    // MARK: - Nested Types (must be defined before use)

    enum TranscriptionProvider: String, Codable, CaseIterable {
        case deepgram = "deepgram"    // Cloud API (paid, streaming)
        case whisper = "whisper"      // Local (free, batch)

        var displayName: String {
            switch self {
            case .deepgram: return "Deepgram (Cloud)"
            case .whisper: return "Whisper (Local)"
            }
        }

        var description: String {
            switch self {
            case .deepgram: return "Fast streaming, requires API key"
            case .whisper: return "Free, runs on-device with Apple Silicon"
            }
        }

        var icon: String {
            switch self {
            case .deepgram: return "cloud.fill"
            case .whisper: return "desktopcomputer"
            }
        }
    }

    enum DiarizationMethod: String, Codable, CaseIterable {
        case local = "local"      // FluidAudio (on-device, free)
        case cloud = "cloud"      // Deepgram (API, paid)

        var displayName: String {
            switch self {
            case .local: return "Local (FluidAudio)"
            case .cloud: return "Cloud (Deepgram)"
            }
        }

        var description: String {
            switch self {
            case .local: return "Free, runs on-device using Apple Neural Engine"
            case .cloud: return "Uses Deepgram API (requires API key)"
            }
        }
    }

    enum FloatingBarPosition: String, Codable, CaseIterable {
        case topLeft = "top-left"
        case topCenter = "top-center"
        case topRight = "top-right"
        case bottomLeft = "bottom-left"
        case bottomCenter = "bottom-center"
        case bottomRight = "bottom-right"

        var displayName: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topCenter: return "Top Center"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomCenter: return "Bottom Center"
            case .bottomRight: return "Bottom Right"
            }
        }
    }

    // MARK: - General Settings

    var apiKey: String = ""
    var language: String? = nil
    var autoPaste: Bool = true
    var copyToClipboard: Bool = true
    var removeFillerWords: Bool = true
    var launchAtStartup: Bool = false
    var showFloatingBar: Bool = true
    var showInDock: Bool = true
    var playSoundEffects: Bool = true
    var floatingBarPosition: FloatingBarPosition = .topCenter
    var selectedMicrophone: String? = nil
    var microphoneSensitivity: Float = 1.5  // 1.0 = normal, 2.0 = high sensitivity

    // MARK: - OpenRouter Settings (AI Summarization)

    /// OpenRouter API key
    var openRouterApiKey: String = ""

    /// Selected OpenRouter model ID (e.g., "anthropic/claude-3.5-sonnet")
    var openRouterModelId: String = ""

    /// Display name of the selected model
    var openRouterModelName: String = ""

    /// Default session type for new recordings
    var defaultSessionType: SessionType = .meeting

    // MARK: - Transcription Provider Settings

    /// Transcription provider (Deepgram cloud or Whisper local)
    var transcriptionProvider: TranscriptionProvider = .deepgram

    /// Whisper model size for final transcription (only used when transcriptionProvider == .whisper)
    var whisperModelSize: String = "openai_whisper-large-v3_turbo"

    /// Whisper model size for real-time streaming (smaller = faster, larger = better quality)
    var whisperStreamingModelSize: String = "openai_whisper-base"

    // MARK: - Session Recording Settings

    /// Audio source for session recording
    var sessionAudioSource: AudioSource = .microphone

    /// Selected app bundle ID for system audio capture (nil = all system audio)
    var selectedSystemAudioApp: String? = nil

    /// Enable speaker diarization (identify who is speaking)
    var enableDiarization: Bool = true

    /// Diarization method: local (FluidAudio) or cloud (Deepgram)
    var diarizationMethod: DiarizationMethod = .local

    /// Enable client-side VAD to save API tokens (disabled by default - can affect transcription quality)
    var useClientSideVAD: Bool = false

    /// VAD energy threshold (0.01 - 0.05 typical)
    var vadThreshold: Float = 0.015

    /// Auto-save session transcripts periodically
    var autoSaveInterval: TimeInterval = 30  // seconds

    /// Minimum session duration to auto-train voice profiles (0 = disabled)
    var autoTrainMinSessionDuration: TimeInterval = 60  // seconds

    /// Show live waveform during session recording
    var showLiveWaveform: Bool = true

    // MARK: - Supported Languages

    // Nova-3 supported languages (31 total + regional variants)
    static let supportedLanguages: [(code: String?, name: String, flag: String)] = [
        (nil, "Auto-detect (Multilingual)", "🌍"),
        ("en", "English", "🇺🇸"),
        ("en-US", "English (US)", "🇺🇸"),
        ("en-GB", "English (UK)", "🇬🇧"),
        ("en-AU", "English (Australia)", "🇦🇺"),
        ("es", "Spanish", "🇪🇸"),
        ("es-419", "Spanish (Latin America)", "🇲🇽"),
        ("fr", "French", "🇫🇷"),
        ("fr-CA", "French (Canada)", "🇨🇦"),
        ("de", "German", "🇩🇪"),
        ("de-CH", "German (Swiss)", "🇨🇭"),
        ("it", "Italian", "🇮🇹"),
        ("pt", "Portuguese", "🇵🇹"),
        ("pt-BR", "Portuguese (Brazil)", "🇧🇷"),
        ("nl", "Dutch", "🇳🇱"),
        ("nl-BE", "Flemish", "🇧🇪"),
        ("ja", "Japanese", "🇯🇵"),
        ("zh", "Chinese (Mandarin)", "🇨🇳"),
        ("ko", "Korean", "🇰🇷"),
        ("ru", "Russian", "🇷🇺"),
        ("pl", "Polish", "🇵🇱"),
        ("uk", "Ukrainian", "🇺🇦"),
        ("sv", "Swedish", "🇸🇪"),
        ("da", "Danish", "🇩🇰"),
        ("no", "Norwegian", "🇳🇴"),
        ("fi", "Finnish", "🇫🇮"),
        ("el", "Greek", "🇬🇷"),
        ("ro", "Romanian", "🇷🇴"),
        ("cs", "Czech", "🇨🇿"),
        ("sk", "Slovak", "🇸🇰"),
        ("ca", "Catalan", "🏴"),
        ("lt", "Lithuanian", "🇱🇹"),
        ("lv", "Latvian", "🇱🇻"),
        ("et", "Estonian", "🇪🇪"),
        ("hi", "Hindi", "🇮🇳"),
        ("ta", "Tamil", "🇮🇳"),
        ("tr", "Turkish", "🇹🇷"),
        ("id", "Indonesian", "🇮🇩"),
        ("th", "Thai", "🇹🇭"),
        ("vi", "Vietnamese", "🇻🇳")
    ]
}
