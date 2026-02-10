import Foundation
import SwiftData
import os.log

// MARK: - Schema Version Management

/// Enum representing all schema versions in the migration path
enum CoriusSchemaVersion: Int, CaseIterable {
    case v1 = 1
    // Future versions: v2, v3, etc.
    
    var schema: Schema {
        switch self {
        case .v1:
            return CoriusSchemaV1.schema
        }
    }
}

// MARK: - V1 Schema (Baseline)

/// V1 Schema - Captures the initial model state as baseline for future migrations
enum CoriusSchemaV1 {
    static let versionNumber = 1
    static let currentSchema = Schema([
        SDSession.self,
        SDFolder.self,
        SDLabel.self,
        SDKnownSpeaker.self,
        SDWorkspaceDatabase.self,
        SDWorkspaceItem.self
    ])
}

// MARK: - Migration Plan

/// Staged migration plan for evolving the SwiftData schema
typealias CoriusSchemaMigrationPlan = SchemaMigrationPlan

enum CoriusMigrationStage: Int, CaseIterable {
    case v1ToV2 = 1
    // Future stages: v2ToV3, v3ToV4, etc.
}

// MARK: - Schema Version Manager

@MainActor
final class SchemaVersionManager {
    static let shared = SchemaVersionManager()
    
    private let logger = Logger(subsystem: "com.corius.voice", category: "SchemaVersionManager")
    
    private let currentSchemaVersionKey = "swiftdata_schema_version"
    private let migrationInProgressKey = "swiftdata_migration_in_progress"
    
    private init() {}
    
    // MARK: - Current Version
    
    var currentSchemaVersion: CoriusSchemaVersion {
        return .v1
    }
    
    var storedSchemaVersion: Int {
        get {
            UserDefaults.standard.integer(forKey: currentSchemaVersionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: currentSchemaVersionKey)
        }
    }
    
    // MARK: - Migration State
    
    var isMigrationInProgress: Bool {
        get {
            UserDefaults.standard.bool(forKey: migrationInProgressKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: migrationInProgressKey)
        }
    }
    
    // MARK: - Schema Retrieval
    
    func getCurrentSchema() -> Schema {
        return currentSchemaVersion.schema
    }
    
    // MARK: - Version Check
    
    func needsMigration() -> Bool {
        return storedSchemaVersion < currentSchemaVersion.rawValue
    }
    
    func checkSchemaVersion(onLaunch: Bool = true) {
        let stored = storedSchemaVersion
        let current = currentSchemaVersion.rawValue
        
        if onLaunch {
            logger.info("📊 Schema version check - Stored: \(stored), Current: \(current)")
        }
        
        if stored > current {
            logger.error("⚠️ Schema version rollback detected! Stored: \(stored) > Current: \(current)")
        }
    }
    
    // MARK: - Migration Completion
    
    func markMigrationComplete(to version: CoriusSchemaVersion) {
        storedSchemaVersion = version.rawValue
        isMigrationInProgress = false
        logger.info("✅ Migration to V\(version.rawValue) complete")
    }
    
    // MARK: - Post-Migration Hooks
    
    func performPostMigrationTasks(fromVersion: Int, toVersion: Int) async throws {
        logger.info("🔧 Performing post-migration tasks from V\(fromVersion) to V\(toVersion)")
        
        // Rebuild search indexes after schema changes
        if toVersion >= 1 {
            try await rebuildTranscriptSearchIndex()
        }
        
        // Future: Add data validation, consistency checks, etc.
    }
    
    private func rebuildTranscriptSearchIndex() async throws {
        logger.info("🔍 Rebuilding transcript search index...")
        try await TranscriptSearchIndex.shared.rebuildAll()
        logger.info("✅ Transcript search index rebuilt")
    }
    
    // MARK: - Migration Error Handling
    
    func handleMigrationError(_ error: Error, fromVersion: Int, toVersion: Int) {
        logger.error("❌ Migration failed from V\(fromVersion) to V\(toVersion): \(error.localizedDescription)")
        
        isMigrationInProgress = false
        
        // Create user-facing alert
        #if canImport(AppKit)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Migration Error", comment: "Migration error alert title")
            alert.informativeText = String(format: NSLocalizedString(
                "A database migration failed while upgrading from version %d to %d. Your data has been preserved. Please contact support.",
                comment: "Migration error message"
            ), fromVersion, toVersion)
            alert.alertStyle = .critical
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModal()
        }
        #endif
    }
    
    // MARK: - Migration Statistics
    
    func logMigrationStatistics() {
        let version = storedSchemaVersion
        logger.info("""
        📊 Schema Migration Statistics:
        - Current Schema Version: \(currentSchemaVersion.rawValue)
        - Stored Schema Version: \(version)
        - Migration Needed: \(needsMigration())
        - Migration In Progress: \(isMigrationInProgress)
        """)
    }
}

// MARK: - ModelContainer Configuration Extension

extension ModelContainer {
    static func createWithVersionedSchema() throws -> ModelContainer {
        let schema = SchemaVersionManager.shared.getCurrentSchema()
        
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
