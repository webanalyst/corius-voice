import Foundation
import os.log

// MARK: - Search Index Integration Extension
// Extends SwiftDataService with transcript search index management

extension SwiftDataService {
    
    /// Rebuild transcript search index after migration or import
    func rebuildTranscriptSearchIndex() async {
        logger.info("🔍 Rebuilding transcript search index...")
        let startTime = Date()
        
        do {
            try await TranscriptSearchIndex.shared.rebuildAll()
            let duration = Date().timeIntervalSince(startTime)
            logger.info("✅ Transcript search index rebuilt in \(String(format: "%.2f", duration))s")
        } catch {
            logger.error("❌ Failed to rebuild transcript search index: \(error.localizedDescription)")
        }
    }
    
    /// Batch index multiple sessions (for import operations)
    func batchIndexSessions(_ sessions: [RecordingSession]) async {
        logger.info("📝 Batch indexing \(sessions.count) sessions...")
        let startTime = Date()
        var successCount = 0
        var errorCount = 0
        
        for session in sessions {
            do {
                if let sdSession = getSession(id: session.id) {
                    TranscriptSearchIndex.shared.indexSession(sdSession, transcriptSegments: session.transcriptSegments)
                    successCount += 1
                }
            } catch {
                errorCount += 1
                logger.warning("⚠️ Failed to index session \(session.id): \(error.localizedDescription)")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        logger.info("✅ Batch indexing complete: \(successCount) succeeded, \(errorCount) failed in \(String(format: "%.2f", duration))s")
    }
}
