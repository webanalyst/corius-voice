import Foundation
import SwiftData
import os.log

// MARK: - Schema Version Support Extension

extension SwiftDataService {
    /// Performs a schema migration if needed, handling version transitions safely
    func performSchemaMigrationIfNeeded() async throws {
        let schemaVersionManager = SchemaVersionManager.shared
        
        guard schemaVersionManager.needsMigration() else {
            logger.info("✅ Schema is up to date (V\(schemaVersionManager.currentSchemaVersion.rawValue))")
            return
        }
        
        guard !schemaVersionManager.isMigrationInProgress else {
            logger.warning("⚠️ Migration already in progress, skipping")
            return
        }
        
        schemaVersionManager.isMigrationInProgress = true
        let fromVersion = schemaVersionManager.storedSchemaVersion
        let toVersion = schemaVersionManager.currentSchemaVersion.rawValue
        
        logger.info("🔄 Starting schema migration from V\(fromVersion) to V\(toVersion)")
        
        do {
            // Perform the actual migration steps here
            // For now, V1 is baseline, so this is a no-op
            // Future: Add migration stages for V1->V2, V2->V3, etc.
            
            try await schemaVersionManager.performPostMigrationTasks(
                fromVersion: fromVersion,
                toVersion: toVersion
            )
            
            schemaVersionManager.markMigrationComplete(to: schemaVersionManager.currentSchemaVersion)
            logger.info("✅ Schema migration completed successfully")
        } catch {
            schemaVersionManager.handleMigrationError(error, fromVersion: fromVersion, toVersion: toVersion)
            throw error
        }
    }
}
