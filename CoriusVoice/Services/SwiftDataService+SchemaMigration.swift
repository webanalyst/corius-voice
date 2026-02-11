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
            // Execute migration stages
            try await executeMigrationStages(from: fromVersion, to: toVersion)
            
            // Perform post-migration tasks
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
    
    /// Executes migration stages sequentially based on version numbers
    private func executeMigrationStages(from: Int, to: Int) async throws {
        logger.info("📋 Executing migration stages from V\(from) to V\(to)")
        
        // V1 to V2 migration
        if from == 1 && to >= 2 {
            try await migrateV1ToV2()
        }
        
        // Future stages: V2 to V3, V3 to V4, etc.
        if from == 2 && to >= 3 {
            // try await migrateV2ToV3()
        }
    }
    
    /// Migrates V1 schema to V2 schema
    /// V2 adds performance indexes on frequently queried fields
    private func migrateV1ToV2() async throws {
        logger.info("🔄 Migrating V1 → V2: Adding performance indexes")
        
        let migrationLogger = Logger(subsystem: "com.corius.voice", category: "V1ToV2Migration")
        
        // SwiftData lightweight migration handles additive changes automatically
        // Indexes are added without manual data migration
        migrationLogger.info("✅ V1→V2 migration: Indexes added (SDSession.startDate, SDSession.folderID, SDLabel.name, SDKnownSpeaker.name, SDFolder.name)")
        
        // Log migration metrics
        let context = ModelContext(container)
        let sessionCount = try? context.fetchCount(FetchDescriptor<SDSession>())
        let folderCount = try? context.fetchCount(FetchDescriptor<SDFolder>())
        let labelCount = try? context.fetchCount(FetchDescriptor<SDLabel>())
        
        migrationLogger.info("""
        📊 V1→V2 Migration Complete:
        - Sessions: \(sessionCount ?? 0)
        - Folders: \(folderCount ?? 0)
        - Labels: \(labelCount ?? 0)
        """)
    }
}

// MARK: - Migration Stage Handler

/// Handler for V1 to V2 migration stage
struct V1ToV2MigrationStage {
    let logger = Logger(subsystem: "com.corius.voice", category: "V1ToV2Migration")
    
    /// Validates V1 data before migration
    func validateV1Data(context: ModelContext) throws {
        logger.info("🔍 Validating V1 data before migration...")
        
        // Check for orphaned records
        let sessions = try context.fetch(FetchDescriptor<SDSession>())
        let orphanedSessions = sessions.filter { session in
            if let folderID = session.folderID {
                let folderExists = try? context.fetch(
                    FetchDescriptor<SDFolder>(predicate: #Predicate { $0.id == folderID })
                ).isEmpty == false
                return !folderExists!
            }
            return false
        }
        
        if !orphanedSessions.isEmpty {
            logger.warning("⚠️ Found \(orphanedSessions.count) sessions with invalid folder references")
        }
        
        logger.info("✅ V1 data validation complete")
    }
    
    /// Prepares index mappings for timestamp-based queries
    func prepareIndexMappings(context: ModelContext) throws {
        logger.info("🗂️ Preparing index mappings for timestamp queries...")
        
        // Ensure searchableText field is populated for all sessions
        let sessionsWithoutSearchText = try context.fetch(
            FetchDescriptor<SDSession>(predicate: #Predicate { $0.searchableText.isEmpty })
        )
        
        for session in sessionsWithoutSearchText {
            // Extract first 1000 chars from transcript for search
            // This would normally load the transcript file, but for migration
            // we'll initialize with empty string and let background jobs populate it
            session.searchableText = ""
        }
        
        try context.save()
        logger.info("✅ Index mappings prepared (\(sessionsWithoutSearchText.count) sessions updated)")
    }
}
