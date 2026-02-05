import Foundation

// MARK: - Voice Profile

/// A stored voice profile for a known speaker
struct VoiceProfile: Codable, Identifiable {
    let id: UUID
    let speakerID: UUID  // Link to KnownSpeaker
    var features: VoiceFeatures  // Legacy basic features
    var embedding: [Float]?  // 256-dim speaker embedding from FluidAudio (WeSpeaker)
    var sampleCount: Int  // Number of samples used to build this profile
    var totalDuration: TimeInterval  // Total audio duration used
    let createdAt: Date
    var updatedAt: Date
    var trainingRecords: [VoiceTrainingRecord]  // Track which sessions were used for training

    /// Whether this profile has modern embeddings (more accurate than basic features)
    var hasEmbedding: Bool { embedding != nil && embedding!.count == 256 }

    init(speakerID: UUID, features: VoiceFeatures, duration: TimeInterval, embedding: [Float]? = nil) {
        self.id = UUID()
        self.speakerID = speakerID
        self.features = features
        self.embedding = embedding
        self.sampleCount = 1
        self.totalDuration = duration
        self.createdAt = Date()
        self.updatedAt = Date()
        self.trainingRecords = []
    }

    // Custom Codable for backwards compatibility
    private enum CodingKeys: String, CodingKey {
        case id, speakerID, features, embedding, sampleCount, totalDuration, createdAt, updatedAt, trainingRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        speakerID = try container.decode(UUID.self, forKey: .speakerID)
        features = try container.decode(VoiceFeatures.self, forKey: .features)
        embedding = try container.decodeIfPresent([Float].self, forKey: .embedding)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        totalDuration = try container.decode(TimeInterval.self, forKey: .totalDuration)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Default to empty array for backwards compatibility
        trainingRecords = try container.decodeIfPresent([VoiceTrainingRecord].self, forKey: .trainingRecords) ?? []
    }

    /// Update profile with new features (incremental learning)
    mutating func updateWith(newFeatures: VoiceFeatures, duration: TimeInterval) {
        // Weighted average - give more weight to existing profile
        let existingWeight = Float(sampleCount)
        let newWeight: Float = 1.0
        let totalWeight = existingWeight + newWeight

        // Merge MFCCs
        var mergedMFCCs = [Float](repeating: 0, count: features.mfccs.count)
        var mergedMFCCVar = [Float](repeating: 0, count: features.mfccVariance.count)

        for i in 0..<features.mfccs.count {
            mergedMFCCs[i] = (features.mfccs[i] * existingWeight + newFeatures.mfccs[i] * newWeight) / totalWeight
            mergedMFCCVar[i] = (features.mfccVariance[i] * existingWeight + newFeatures.mfccVariance[i] * newWeight) / totalWeight
        }

        // Merge other features
        let mergedPitchMean = (features.pitchMean * existingWeight + newFeatures.pitchMean * newWeight) / totalWeight
        let mergedPitchVar = (features.pitchVariance * existingWeight + newFeatures.pitchVariance * newWeight) / totalWeight
        let mergedEnergyMean = (features.energyMean * existingWeight + newFeatures.energyMean * newWeight) / totalWeight
        let mergedEnergyVar = (features.energyVariance * existingWeight + newFeatures.energyVariance * newWeight) / totalWeight
        let mergedSpectral = (features.spectralCentroid * existingWeight + newFeatures.spectralCentroid * newWeight) / totalWeight
        let mergedZCR = (features.zeroCrossingRate * existingWeight + newFeatures.zeroCrossingRate * newWeight) / totalWeight

        features = VoiceFeatures(
            mfccs: mergedMFCCs,
            mfccVariance: mergedMFCCVar,
            pitchMean: mergedPitchMean,
            pitchVariance: mergedPitchVar,
            energyMean: mergedEnergyMean,
            energyVariance: mergedEnergyVar,
            spectralCentroid: mergedSpectral,
            zeroCrossingRate: mergedZCR
        )

        sampleCount += 1
        totalDuration += duration
        updatedAt = Date()
    }

    /// Update profile with embedding (from FluidAudio diarization)
    mutating func updateWithEmbedding(_ newEmbedding: [Float], duration: TimeInterval) {
        guard newEmbedding.count == 256 else {
            print("[VoiceProfile] ⚠️ Invalid embedding size: \(newEmbedding.count), expected 256")
            return
        }

        if let existingEmbedding = embedding, existingEmbedding.count == 256 {
            // Average with existing embedding (weighted by sample count)
            let existingWeight = Float(sampleCount)
            let newWeight: Float = 1.0
            let totalWeight = existingWeight + newWeight

            var merged = [Float](repeating: 0, count: 256)
            for i in 0..<256 {
                merged[i] = (existingEmbedding[i] * existingWeight + newEmbedding[i] * newWeight) / totalWeight
            }

            // L2 normalize the merged embedding
            embedding = VoiceProfile.l2Normalize(merged)
        } else {
            // First embedding - L2 normalize and store
            embedding = VoiceProfile.l2Normalize(newEmbedding)
        }

        sampleCount += 1
        totalDuration += duration
        updatedAt = Date()
    }

    /// L2 normalize an embedding vector
    static func l2Normalize(_ embedding: [Float]) -> [Float] {
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return embedding }
        return embedding.map { $0 / norm }
    }

    /// Compute cosine distance between two embeddings (0 = identical, 2 = opposite)
    static func cosineDistance(_ emb1: [Float], _ emb2: [Float]) -> Float {
        guard emb1.count == emb2.count, emb1.count == 256 else {
            return Float.infinity
        }

        // Embeddings should already be normalized, but normalize just in case
        let norm1 = sqrt(emb1.reduce(0) { $0 + $1 * $1 })
        let norm2 = sqrt(emb2.reduce(0) { $0 + $1 * $1 })

        guard norm1 > 0, norm2 > 0 else {
            return Float.infinity
        }

        var dotProduct: Float = 0
        for i in 0..<256 {
            dotProduct += (emb1[i] / norm1) * (emb2[i] / norm2)
        }

        return 1.0 - dotProduct
    }
}

// MARK: - Speaker Match Result

/// Result of matching audio against voice profiles
struct SpeakerMatch {
    let speakerID: UUID
    let speakerName: String
    let confidence: Float  // 0-1
    let features: VoiceFeatures
}

// MARK: - Voice Profile Service

/// Manages voice profiles for speaker identification
class VoiceProfileService: ObservableObject {
    static let shared = VoiceProfileService()

    @Published private(set) var profiles: [VoiceProfile] = []

    private let storageKey = "CoriusVoiceProfiles"
    private let featureExtractor = AudioFeatureExtractor.shared
    private let minimumConfidence: Float = 0.40  // Lowered for debugging (was 0.65)

    private init() {
        loadProfiles()
        debugPrintProfiles()

        // Automatically clean up invalid profiles on startup
        let removedCount = removeInvalidProfiles()
        if removedCount > 0 {
            print("[VoiceProfile] 🧹 Auto-cleaned \(removedCount) invalid profile(s) on startup")
        }
    }

    /// Print debug info about loaded profiles
    private func debugPrintProfiles() {
        print("[VoiceProfile] 📦 Loaded \(profiles.count) voice profile(s)")
        for profile in profiles {
            let speakerName = SpeakerLibrary.shared.getSpeaker(byID: profile.speakerID)?.name ?? "Unknown"
            let isValid = profile.features.pitchMean > 0 && profile.features.energyMean > 0
            print("[VoiceProfile]   - \(speakerName): pitch=\(String(format: "%.1f", profile.features.pitchMean))Hz, energy=\(String(format: "%.4f", profile.features.energyMean)), samples=\(profile.sampleCount), valid=\(isValid ? "✅" : "❌")")
        }

        // Check for invalid profiles
        let invalidCount = profiles.filter { $0.features.pitchMean == 0 || $0.features.energyMean == 0 }.count
        if invalidCount > 0 {
            print("[VoiceProfile] ⚠️ WARNING: \(invalidCount) profile(s) have invalid features (pitch=0 or energy=0)")
            print("[VoiceProfile] ⚠️ These profiles should be retrained or deleted")
        }
    }

    /// Remove profiles with invalid features (pitch=0 or energy=0)
    func removeInvalidProfiles() -> Int {
        let beforeCount = profiles.count
        profiles.removeAll { $0.features.pitchMean == 0 || $0.features.energyMean == 0 }
        let removedCount = beforeCount - profiles.count
        if removedCount > 0 {
            saveProfiles()
            print("[VoiceProfile] 🗑️ Removed \(removedCount) invalid profile(s)")
        }
        return removedCount
    }

    // MARK: - Profile Management

    /// Create or update a voice profile for a speaker
    func trainProfile(
        for speakerID: UUID,
        from audioURL: URL,
        startTime: TimeInterval,
        duration: TimeInterval
    ) async throws {
        let features = try await featureExtractor.extractFeatures(
            from: audioURL,
            startTime: startTime,
            duration: duration
        )

        // Validate features before saving
        guard features.pitchMean > 0 && features.energyMean > 0 else {
            print("[VoiceProfile] ⚠️ Rejecting profile training from file - invalid features (pitch=\(features.pitchMean), energy=\(features.energyMean))")
            return
        }

        print("[VoiceProfile] ✅ Training profile from file with valid features: pitch=\(String(format: "%.1f", features.pitchMean))Hz, energy=\(String(format: "%.4f", features.energyMean))")

        await MainActor.run {
            if let index = profiles.firstIndex(where: { $0.speakerID == speakerID }) {
                // Update existing profile
                profiles[index].updateWith(newFeatures: features, duration: duration)
            } else {
                // Create new profile
                let profile = VoiceProfile(speakerID: speakerID, features: features, duration: duration)
                profiles.append(profile)
            }
            saveProfiles()
        }
    }

    /// Create or update profile from raw audio samples
    func trainProfile(for speakerID: UUID, from samples: [Float], duration: TimeInterval) {
        let features = featureExtractor.extractFeatures(from: samples)

        // Validate features before saving
        guard features.pitchMean > 0 && features.energyMean > 0 else {
            print("[VoiceProfile] ⚠️ Rejecting profile training - invalid features (pitch=\(features.pitchMean), energy=\(features.energyMean))")
            return
        }

        print("[VoiceProfile] ✅ Training profile with valid features: pitch=\(String(format: "%.1f", features.pitchMean))Hz, energy=\(String(format: "%.4f", features.energyMean))")

        if let index = profiles.firstIndex(where: { $0.speakerID == speakerID }) {
            profiles[index].updateWith(newFeatures: features, duration: duration)
        } else {
            let profile = VoiceProfile(speakerID: speakerID, features: features, duration: duration)
            profiles.append(profile)
        }
        saveProfiles()
    }

    /// Delete a voice profile
    func deleteProfile(for speakerID: UUID) {
        profiles.removeAll { $0.speakerID == speakerID }
        saveProfiles()
    }

    /// Get profile for a speaker
    func getProfile(for speakerID: UUID) -> VoiceProfile? {
        profiles.first { $0.speakerID == speakerID }
    }

    /// Check if a speaker has a voice profile
    func hasProfile(for speakerID: UUID) -> Bool {
        profiles.contains { $0.speakerID == speakerID }
    }

    // MARK: - Speaker Identification

    /// Match audio against all known profiles
    func identifySpeaker(from audioURL: URL, startTime: TimeInterval, duration: TimeInterval) async throws -> [SpeakerMatch] {
        let features = try await featureExtractor.extractFeatures(
            from: audioURL,
            startTime: startTime,
            duration: duration
        )

        return await identifySpeaker(from: features)
    }

    /// Match features against all known profiles
    func identifySpeaker(from features: VoiceFeatures) async -> [SpeakerMatch] {
        let speakerLibrary = await MainActor.run { SpeakerLibrary.shared }

        print("[VoiceProfile] 🔍 Identifying speaker against \(profiles.count) profiles...")
        print("[VoiceProfile] 📊 Input features - MFCCs[0-2]: \(features.mfccs.prefix(3).map { String(format: "%.2f", $0) })")
        print("[VoiceProfile] 📊 Input features - Pitch: \(String(format: "%.1f", features.pitchMean))Hz, Energy: \(String(format: "%.4f", features.energyMean))")

        var matches: [SpeakerMatch] = []
        var allSimilarities: [(name: String, similarity: Float)] = []

        for profile in profiles {
            let similarity = features.similarity(to: profile.features)

            // Get speaker name from library
            let speakerName = await MainActor.run {
                speakerLibrary.getSpeaker(byID: profile.speakerID)?.name ?? "Unknown"
            }

            allSimilarities.append((speakerName, similarity))

            print("[VoiceProfile] 👤 \(speakerName): similarity = \(String(format: "%.2f", similarity * 100))% (threshold: \(String(format: "%.0f", minimumConfidence * 100))%)")
            print("[VoiceProfile]    Profile MFCCs[0-2]: \(profile.features.mfccs.prefix(3).map { String(format: "%.2f", $0) })")
            print("[VoiceProfile]    Profile Pitch: \(String(format: "%.1f", profile.features.pitchMean))Hz, Energy: \(String(format: "%.4f", profile.features.energyMean))")
            print("[VoiceProfile]    Profile samples: \(profile.sampleCount), duration: \(String(format: "%.1f", profile.totalDuration))s")

            if similarity >= minimumConfidence {
                matches.append(SpeakerMatch(
                    speakerID: profile.speakerID,
                    speakerName: speakerName,
                    confidence: similarity,
                    features: features
                ))
                print("[VoiceProfile] ✅ MATCH!")
            } else {
                print("[VoiceProfile] ❌ Below threshold")
            }
        }

        if matches.isEmpty {
            print("[VoiceProfile] ⚠️ No matches found. Best similarity was: \(allSimilarities.max(by: { $0.similarity < $1.similarity })?.similarity ?? 0)")
        }

        // Sort by confidence (highest first)
        return matches.sorted { $0.confidence > $1.confidence }
    }

    /// Match raw audio samples against profiles
    func identifySpeaker(from samples: [Float]) -> [SpeakerMatch] {
        let features = featureExtractor.extractFeatures(from: samples)
        let speakerLibrary = SpeakerLibrary.shared

        var matches: [SpeakerMatch] = []

        for profile in profiles {
            let similarity = features.similarity(to: profile.features)
            let speakerName = speakerLibrary.getSpeaker(byID: profile.speakerID)?.name ?? "Unknown"

            if similarity >= minimumConfidence {
                matches.append(SpeakerMatch(
                    speakerID: profile.speakerID,
                    speakerName: speakerName,
                    confidence: similarity,
                    features: features
                ))
            }
        }

        return matches.sorted { $0.confidence > $1.confidence }
    }

    /// Get best match for audio (if above threshold)
    func getBestMatch(from samples: [Float]) -> SpeakerMatch? {
        identifySpeaker(from: samples).first
    }

    // MARK: - Batch Operations

    /// Progress callback type for training
    typealias TrainingProgressCallback = (String, Double) -> Void  // (status, progress 0-1)

    /// Train a specific speaker from assigned segments and a specific audio source
    /// Prioritizes embeddings over legacy features when available
    func trainFromAssignedSpeaker(
        audioURL: URL,
        speaker: Speaker,
        segments: [TranscriptSegment],
        knownSpeaker: KnownSpeaker,
        session: RecordingSession? = nil,
        onProgress: TrainingProgressCallback? = nil
    ) async throws -> Bool {
        let speakerSegments = segments.filter { $0.speakerID == speaker.id }
        guard !speakerSegments.isEmpty else {
            print("[VoiceProfile] ⏭️ No segments found for speaker \(speaker.id)")
            return false
        }

        print("[VoiceProfile] 🎯 Training '\(knownSpeaker.name)' from speaker \(speaker.id) (\(speakerSegments.count) segments)")
        onProgress?("Preparing training for \(knownSpeaker.name)...", 0.0)

        // Check if speaker already has embedding from diarization
        let hasExistingEmbedding = speaker.embedding?.count == 256
        
        var totalDuration: TimeInterval = 0
        var finalEmbedding: [Float]?
        var legacyFeatures: VoiceFeatures?
        
        // Calculate total duration from segments
        for segment in speakerSegments {
            let segmentDuration: TimeInterval
            if let lastWord = segment.words.last, let firstWord = segment.words.first {
                segmentDuration = lastWord.end - firstWord.start
            } else if !segment.text.isEmpty {
                let wordCount = segment.text.split(separator: " ").count
                segmentDuration = Double(wordCount) * 0.3
            } else {
                continue
            }
            totalDuration += min(segmentDuration, 10.0)
        }

        // PRIORITY 1: Use existing embedding from speaker (from diarization)
        if hasExistingEmbedding, let embedding = speaker.embedding {
            print("[VoiceProfile] 🧬 Using existing 256-dim embedding from diarization")
            onProgress?("Using embedding from diarization...", 0.5)
            finalEmbedding = embedding
        }
        // PRIORITY 2: Extract embedding using LocalDiarizationService (if macOS 14+)
        else if #available(macOS 14.0, *) {
            print("[VoiceProfile] 🧬 Extracting embedding using FluidAudio...")
            onProgress?("Extracting voice embedding...", 0.2)
            
            do {
                let diarizationResult = try await LocalDiarizationService.shared.processAudioFile(audioURL)
                onProgress?("Processing embeddings...", 0.6)
                
                // Find the speaker with most overlap with our segments
                var bestMatch: (speakerID: String, embedding: [Float], overlap: TimeInterval)?
                
                for (diarizationSpeakerID, profile) in diarizationResult.speakerProfiles {
                    // Calculate time overlap between diarization speaker and our segments
                    var overlap: TimeInterval = 0
                    for segment in speakerSegments {
                        for diarizationSegment in diarizationResult.segments where diarizationSegment.speakerID == diarizationSpeakerID {
                            let overlapStart = max(segment.timestamp, diarizationSegment.startTime)
                            let segmentEnd = segment.words.last?.end ?? (segment.timestamp + 5.0)
                            let overlapEnd = min(segmentEnd, diarizationSegment.endTime)
                            if overlapEnd > overlapStart {
                                overlap += overlapEnd - overlapStart
                            }
                        }
                    }
                    
                    if bestMatch == nil || overlap > bestMatch!.overlap {
                        bestMatch = (diarizationSpeakerID, profile.embedding, overlap)
                    }
                }
                
                if let match = bestMatch, match.overlap > 1.0 {  // At least 1 second overlap
                    finalEmbedding = match.embedding
                    print("[VoiceProfile] 🧬 Extracted embedding from speaker '\(match.speakerID)' (overlap: \(String(format: "%.1f", match.overlap))s)")
                } else {
                    print("[VoiceProfile] ⚠️ Could not find matching speaker in diarization result")
                }
            } catch {
                print("[VoiceProfile] ⚠️ FluidAudio extraction failed: \(error.localizedDescription)")
            }
        }
        
        // FALLBACK: Extract legacy features if no embedding available
        if finalEmbedding == nil {
            print("[VoiceProfile] 📊 Falling back to legacy feature extraction...")
            onProgress?("Extracting voice features (fallback)...", 0.3)
            
            var allFeatures: [VoiceFeatures] = []
            let totalSegments = speakerSegments.count
            
            for (index, segment) in speakerSegments.enumerated() {
                let segmentDuration: TimeInterval
                if let lastWord = segment.words.last, let firstWord = segment.words.first {
                    segmentDuration = lastWord.end - firstWord.start
                } else if !segment.text.isEmpty {
                    let wordCount = segment.text.split(separator: " ").count
                    segmentDuration = Double(wordCount) * 0.3
                } else {
                    continue
                }
                
                let duration = min(segmentDuration, 10.0)
                guard duration > 0.5 else { continue }
                
                let progress = 0.3 + (Double(index) / Double(totalSegments)) * 0.5
                onProgress?("Extracting features (\(index + 1)/\(totalSegments))...", progress)
                
                do {
                    let features = try await featureExtractor.extractFeatures(
                        from: audioURL,
                        startTime: segment.timestamp,
                        duration: duration
                    )
                    
                    if features.mfccs.allSatisfy({ !$0.isNaN }) && !features.energyMean.isNaN {
                        allFeatures.append(features)
                    }
                } catch {
                    // Silently continue - don't spam logs
                }
            }
            
            legacyFeatures = VoiceFeatures.average(allFeatures)
        }
        
        // Must have either embedding or features
        guard finalEmbedding != nil || legacyFeatures != nil else {
            print("[VoiceProfile] ❌ Could not extract embedding or features for '\(knownSpeaker.name)'")
            return false
        }
        
        onProgress?("Saving profile...", 0.9)
        
        // Build training record
        let usedSegments = speakerSegments.compactMap { segment -> SegmentTimeRange? in
            let segmentDuration: TimeInterval
            if let lastWord = segment.words.last, let firstWord = segment.words.first {
                segmentDuration = lastWord.end - firstWord.start
            } else if !segment.text.isEmpty {
                let wordCount = segment.text.split(separator: " ").count
                segmentDuration = Double(wordCount) * 0.3
            } else {
                return nil
            }
            guard segmentDuration > 0.5 else { return nil }
            return SegmentTimeRange(start: segment.timestamp, end: segment.timestamp + min(segmentDuration, 10.0))
        }

        await MainActor.run {
            let trainingRecord = VoiceTrainingRecord(
                speakerID: knownSpeaker.id,
                sessionID: session?.id ?? UUID(),
                segmentTimestamps: usedSegments,
                extractedDuration: totalDuration,
                trainedAt: Date(),
                featuresExtracted: legacyFeatures != nil,
                sessionTitle: session?.displayTitle,
                sessionDate: session?.startDate
            )

            if let index = profiles.firstIndex(where: { $0.speakerID == knownSpeaker.id }) {
                // Update existing profile
                if let embedding = finalEmbedding {
                    profiles[index].updateWithEmbedding(embedding, duration: totalDuration)
                    print("[VoiceProfile] 🧬 Updated embedding for '\(knownSpeaker.name)'")
                }
                if let features = legacyFeatures {
                    profiles[index].updateWith(newFeatures: features, duration: totalDuration)
                }
                profiles[index].trainingRecords.append(trainingRecord)
            } else {
                // Create new profile
                var profile = VoiceProfile(
                    speakerID: knownSpeaker.id,
                    features: legacyFeatures ?? VoiceFeatures.empty,
                    duration: totalDuration,
                    embedding: finalEmbedding != nil ? VoiceProfile.l2Normalize(finalEmbedding!) : nil
                )
                profile.trainingRecords.append(trainingRecord)
                profiles.append(profile)
            }

            saveProfiles()
        }
        
        let methodUsed = finalEmbedding != nil ? "embedding" : "legacy features"
        print("[VoiceProfile] ✅ Training complete for '\(knownSpeaker.name)' using \(methodUsed)")
        onProgress?("Training complete!", 1.0)
        return true
    }

    // MARK: - DEPRECATED: trainFromSession removed - use trainFromAssignedSpeaker instead
    // The legacy method used feature extraction (MFCCs, pitch, energy) for all training.
    // The new trainFromAssignedSpeaker prioritizes 256-dim embeddings from FluidAudio.

    /// Auto-identify speakers in a session based on existing profiles
    /// Uses embeddings (if available) for better accuracy, falls back to voice features
    func autoIdentifySession(
        audioURL: URL,
        segments: [TranscriptSegment],
        speakers: [Speaker]
    ) async throws -> [Int: SpeakerMatch] {  // deepgramSpeakerID -> match
        var results: [Int: SpeakerMatch] = [:]

        // Check if we have profiles with embeddings
        let profilesWithEmbeddings = profiles.filter { $0.hasEmbedding }
        let useEmbeddings = !profilesWithEmbeddings.isEmpty

        print("[VoiceProfile] 🔍 Auto-identify: \(profiles.count) profiles, \(profilesWithEmbeddings.count) with embeddings")

        // STRATEGY 1: Try to use embeddings from session speakers (if they have them)
        var embeddingMatches: [Int: SpeakerMatch] = [:]
        for speaker in speakers {
            if let embedding = speaker.embedding, embedding.count == 256 {
                print("[VoiceProfile] 🧬 Speaker \(speaker.id) has embedding, trying to match...")
                if let match = identifyWithEmbedding(embedding) {
                    let speakerMatch = SpeakerMatch(
                        speakerID: match.speakerID,
                        speakerName: match.speakerName,
                        confidence: match.confidence,
                        features: .empty
                    )
                    embeddingMatches[speaker.id] = speakerMatch
                    print("[VoiceProfile] 🧬 Embedding match: Speaker \(speaker.id) → \(match.speakerName) (\(Int(match.confidence * 100))%)")
                }
            }
        }

        // If we got embedding matches, use them
        if !embeddingMatches.isEmpty {
            print("[VoiceProfile] ✅ Using \(embeddingMatches.count) embedding-based matches")
            return embeddingMatches
        }

        // STRATEGY 2: Try to run FluidAudio diarization to get embeddings
        if useEmbeddings && LocalDiarizationService.shared.isAvailable {
            print("[VoiceProfile] 🧬 Running FluidAudio to extract embeddings...")
            do {
                try await LocalDiarizationService.shared.loadModels()
                let diarizationResult = try await LocalDiarizationService.shared.processAudioFile(audioURL)

                // Match diarization embeddings against our profiles
                for (diarizationSpeakerID, profile) in diarizationResult.speakerProfiles {
                    guard profile.embedding.count == 256 else { continue }

                    if let match = identifyWithEmbedding(profile.embedding) {
                        // Map diarization speaker to session speaker
                        // Try to find corresponding session speaker by matching segment counts
                        let diarizationSegments = diarizationResult.segments.filter { $0.speakerID == diarizationSpeakerID }

                        // Find the session speaker with most overlapping timestamps
                        for speaker in speakers {
                            let sessionSegments = segments.filter { $0.speakerID == speaker.id }
                            let overlap = sessionSegments.filter { seg in
                                diarizationSegments.contains { diaSeg in
                                    abs(seg.timestamp - diaSeg.startTime) < 1.0
                                }
                            }.count

                            if overlap > 0 {
                                let speakerMatch = SpeakerMatch(
                                    speakerID: match.speakerID,
                                    speakerName: match.speakerName,
                                    confidence: match.confidence,
                                    features: .empty
                                )
                                results[speaker.id] = speakerMatch
                                print("[VoiceProfile] 🧬 FluidAudio match: Speaker \(speaker.id) → \(match.speakerName) (\(Int(match.confidence * 100))%)")
                                break
                            }
                        }
                    }
                }

                if !results.isEmpty {
                    print("[VoiceProfile] ✅ Using \(results.count) FluidAudio embedding matches")
                    return results
                }
            } catch {
                print("[VoiceProfile] ⚠️ FluidAudio failed: \(error.localizedDescription), falling back to voice features")
            }
        }

        // STRATEGY 3: Fall back to voice features (less accurate)
        print("[VoiceProfile] 📊 Falling back to voice features matching...")

        // Group segments by speaker
        var speakerSegments: [Int: [TranscriptSegment]] = [:]
        for segment in segments {
            guard let speakerID = segment.speakerID else { continue }
            speakerSegments[speakerID, default: []].append(segment)
        }

        // For each unique speaker in the session
        for speakerID in speakerSegments.keys {
            guard let segments = speakerSegments[speakerID], !segments.isEmpty else { continue }

            var allFeatures: [VoiceFeatures] = []

            print("[VoiceProfile] 🔍 Processing speaker \(speakerID) with \(segments.count) segments")

            for (index, segment) in segments.prefix(5).enumerated() {
                let segmentDuration: TimeInterval
                if let lastWord = segment.words.last, let firstWord = segment.words.first {
                    segmentDuration = lastWord.end - firstWord.start
                } else if !segment.text.isEmpty {
                    let wordCount = segment.text.split(separator: " ").count
                    segmentDuration = Double(wordCount) * 0.3
                } else {
                    segmentDuration = 0
                }

                let duration = min(segmentDuration, 3.0)

                if duration > 0.5 {
                    do {
                        let features = try await featureExtractor.extractFeatures(
                            from: audioURL,
                            startTime: segment.timestamp,
                            duration: duration
                        )
                        if features.mfccs.allSatisfy({ !$0.isNaN }) && !features.energyMean.isNaN {
                            allFeatures.append(features)
                        }
                    } catch {
                        continue
                    }
                }
            }

            if let avgFeatures = VoiceFeatures.average(allFeatures) {
                let matches = await identifySpeaker(from: avgFeatures)
                if let bestMatch = matches.first {
                    results[speakerID] = bestMatch
                }
            }
        }

        return results
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([VoiceProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
    }

    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    // MARK: - Debug/Info

    /// Get profile statistics
    func profileStats(for speakerID: UUID) -> (samples: Int, duration: TimeInterval)? {
        guard let profile = getProfile(for: speakerID) else { return nil }
        return (profile.sampleCount, profile.totalDuration)
    }

    /// Clear all profiles
    func clearAllProfiles() {
        profiles.removeAll()
        saveProfiles()
    }

    // MARK: - Embedding-Based Identification (FluidAudio)

    /// Train profile with embedding from FluidAudio diarization
    func trainWithEmbedding(
        for speakerID: UUID,
        embedding: [Float],
        duration: TimeInterval,
        session: RecordingSession? = nil
    ) {
        guard embedding.count == 256 else {
            print("[VoiceProfile] ⚠️ Invalid embedding size: \(embedding.count), expected 256")
            return
        }

        print("[VoiceProfile] 🧬 Training with 256-dim embedding for speaker \(speakerID)")

        // Create training record
        let trainingRecord = VoiceTrainingRecord(
            speakerID: speakerID,
            sessionID: session?.id ?? UUID(),
            segmentTimestamps: [],
            extractedDuration: duration,
            trainedAt: Date(),
            featuresExtracted: true,
            sessionTitle: session?.displayTitle,
            sessionDate: session?.startDate
        )

        if let index = profiles.firstIndex(where: { $0.speakerID == speakerID }) {
            profiles[index].updateWithEmbedding(embedding, duration: duration)
            profiles[index].trainingRecords.append(trainingRecord)
            print("[VoiceProfile] 🔄 Updated embedding for existing profile")
        } else {
            // Create new profile with embedding but empty features
            var profile = VoiceProfile(
                speakerID: speakerID,
                features: VoiceFeatures.empty,
                duration: duration,
                embedding: VoiceProfile.l2Normalize(embedding)
            )
            profile.trainingRecords.append(trainingRecord)
            profiles.append(profile)
            print("[VoiceProfile] ✨ Created new profile with embedding")
        }
        saveProfiles()
    }

    /// Identify speaker using embedding (more accurate than feature-based)
    func identifyWithEmbedding(
        _ embedding: [Float],
        threshold: Float = 0.5  // Slightly relaxed to reduce false negatives
    ) -> (speakerID: UUID, speakerName: String, confidence: Float)? {
        guard embedding.count == 256 else {
            print("[VoiceProfile] ⚠️ Invalid input embedding size: \(embedding.count)")
            return nil
        }

        // Normalize incoming embedding to be comparable with stored normalized vectors
        let normalizedInput = VoiceProfile.l2Normalize(embedding)

        var bestMatch: (UUID, String, Float)?
        let speakerLibrary = SpeakerLibrary.shared

        print("[VoiceProfile] 🔍 Matching embedding against \(profiles.count) profiles...")

        for profile in profiles {
            guard let profileEmbedding = profile.embedding, profileEmbedding.count == 256 else {
                continue  // Skip profiles without embeddings
            }

            let distance = VoiceProfile.cosineDistance(normalizedInput, profileEmbedding)
            let speakerName = speakerLibrary.getSpeaker(byID: profile.speakerID)?.name ?? "Unknown"

            print("[VoiceProfile] 👤 \(speakerName): distance = \(String(format: "%.3f", distance)) (threshold: \(threshold))")

            if distance < threshold {
                if bestMatch == nil || distance < (1.0 - bestMatch!.2) {
                    let confidence = 1.0 - distance  // Convert distance to confidence (0-1)
                    bestMatch = (profile.speakerID, speakerName, confidence)
                }
            }
        }

        if let match = bestMatch {
            print("[VoiceProfile] ✅ Best match: \(match.1) (confidence: \(String(format: "%.1f%%", match.2 * 100)))")
            return match
        } else {
            print("[VoiceProfile] ❌ No match found within threshold")
            return nil
        }
    }

    /// Get all profiles that have embeddings (for bulk matching)
    func getEmbeddingProfiles() -> [String: [Float]] {
        var result: [String: [Float]] = [:]
        let speakerLibrary = SpeakerLibrary.shared

        for profile in profiles {
            guard let embedding = profile.embedding, embedding.count == 256 else { continue }
            let speakerName = speakerLibrary.getSpeaker(byID: profile.speakerID)?.name ?? profile.speakerID.uuidString
            result[speakerName] = embedding
        }

        return result
    }

    /// Train profiles from diarization result (for all assigned speakers)
    func trainFromDiarization(
        _ result: LocalDiarizationResult,
        speakerMapping: [String: String],  // diarization speakerID -> known speaker name
        session: RecordingSession? = nil
    ) async {
        let speakerLibrary = await MainActor.run { SpeakerLibrary.shared }

        for (diarizationID, speakerProfile) in result.speakerProfiles {
            // Check if this speaker was mapped to a known speaker
            guard let knownSpeakerName = speakerMapping[diarizationID] else {
                continue
            }

            // Find the known speaker in the library
            guard let knownSpeaker = await MainActor.run(body: {
                speakerLibrary.speakers.first { $0.name.lowercased() == knownSpeakerName.lowercased() }
            }) else {
                print("[VoiceProfile] ⚠️ Known speaker '\(knownSpeakerName)' not found in library")
                continue
            }

            print("[VoiceProfile] 🎓 Training '\(knownSpeakerName)' from diarization speaker '\(diarizationID)'")

            await MainActor.run {
                trainWithEmbedding(
                    for: knownSpeaker.id,
                    embedding: speakerProfile.embedding,
                    duration: speakerProfile.totalDuration,
                    session: session
                )
            }
        }
    }

    // MARK: - Training Records

    /// Get training records for a speaker
    func getTrainingRecords(for speakerID: UUID) -> [VoiceTrainingRecord] {
        getProfile(for: speakerID)?.trainingRecords ?? []
    }

    /// Clear training records for a speaker (keeps the profile but removes history)
    func clearTrainingRecords(for speakerID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.speakerID == speakerID }) else { return }
        profiles[index].trainingRecords.removeAll()
        saveProfiles()
    }

    /// Reset a profile completely (removes profile and all training records)
    func resetProfile(for speakerID: UUID) {
        profiles.removeAll { $0.speakerID == speakerID }
        saveProfiles()
    }

    /// Get total training duration for a speaker
    func totalTrainingDuration(for speakerID: UUID) -> TimeInterval {
        let records = getTrainingRecords(for: speakerID)
        return records.reduce(0) { $0 + $1.extractedDuration }
    }

    /// Get unique session count used for training
    func trainingSessionCount(for speakerID: UUID) -> Int {
        let records = getTrainingRecords(for: speakerID)
        return Set(records.map { $0.sessionID }).count
    }
}
