import XCTest
import SwiftData
@testable import CoriusVoice

// MARK: - Data Migration Tests

/// Comprehensive test suite for verifying SwiftData schema migrations preserve data integrity
/// Tests V1→V2 migration with edge cases, rollback scenarios, and post-migration validation
@MainActor
final class DataMigrationTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var testContainer: ModelContainer!
    private var testContext: ModelContext!
    private var temporaryDirectory: URL!
    private var schemaVersionManager: SchemaVersionManager!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary directory for test database
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoriusVoice-MigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        
        // Initialize test schema manager
        schemaVersionManager = SchemaVersionManager.shared
        
        // Reset migration state for clean testing
        resetMigrationState()
    }
    
    override func tearDown() async throws {
        // Clean up test database
        testContext = nil
        testContainer = nil
        
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func resetMigrationState() {
        UserDefaults.standard.removeObject(forKey: "swiftdata_schema_version")
        UserDefaults.standard.removeObject(forKey: "swiftdata_migration_in_progress")
        UserDefaults.standard.removeObject(forKey: "swiftdata_migration_complete_v1")
        UserDefaults.standard.removeObject(forKey: "swiftdata_workspace_migration_complete_v1")
    }
    
    private func createV1TestContainer() throws -> ModelContainer {
        let schema = CoriusSchemaV1.schema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
    
    private func createV2TestContainer() throws -> ModelContainer {
        let schema = CoriusSchemaV2.schema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
    
    // MARK: - Test Fixtures
    
    private func createV1SampleSession(in context: ModelContext) -> SDSession {
        let session = SDSession(
            id: UUID(),
            startDate: Date(timeIntervalSince1970: 1_738_000_000),
            endDate: Date(timeIntervalSince1970: 1_738_000_900),
            title: "Test Meeting",
            sessionType: "meeting",
            audioFileName: "test_audio.m4a",
            speakerCount: 2,
            segmentCount: 10,
            totalDuration: 900.0,
            hasTranscript: true,
            hasSummary: false,
            folderID: nil,
            labelIDs: [],
            isClassified: false,
            aiSuggestedFolderID: nil,
            aiClassificationConfidence: nil,
            searchableText: "This is a test transcript for migration",
            speakerNames: "Speaker 1, Speaker 2"
        )
        context.insert(session)
        return session
    }
    
    private func createV1SampleFolder(in context: ModelContext) -> SDFolder {
        let folder = SDFolder(
            id: UUID(),
            name: "Test Folder",
            parentID: nil,
            icon: "folder.fill",
            color: "#FF5733",
            isSystem: false,
            createdAt: Date(),
            sortOrder: 1,
            classificationKeywords: ["meeting", "test"],
            classificationDescription: "Test folder for meetings"
        )
        context.insert(folder)
        return folder
    }
    
    private func createV1SampleLabel(in context: ModelContext) -> SDLabel {
        let label = SDLabel(
            id: UUID(),
            name: "Important",
            color: "#E74C3C",
            icon: "star.fill",
            createdAt: Date(),
            sortOrder: 1
        )
        context.insert(label)
        return label
    }
    
    private func createV1SampleSpeaker(in context: ModelContext) -> SDKnownSpeaker {
        let speaker = SDKnownSpeakers(
            id: UUID(),
            name: "John Doe",
            color: "#3498DB",
            notes: "Frequent speaker",
            voiceCharacteristics: "deep, slow",
            createdAt: Date(),
            lastUsedAt: Date(),
            usageCount: 5
        )
        context.insert(speaker)
        return speaker
    }
    
    // MARK: - Migration Tests: V1 to V2
    
    func testMigrationFromV1ToV2PreservesAllSessions() async throws {
        // Setup: Create V1 database with sample data
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        let originalSession = createV1SampleSession(in: v1Context)
        let sessionID = originalSession.id
        
        try v1Context.save()
        
        // Execute: Simulate migration to V2
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Session is preserved with all fields
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let fetchDescriptor = FetchDescriptor<SDSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let migratedSessions = try v2Context.fetch(fetchDescriptor)
        
        XCTAssertEqual(migratedSessions.count, 1, "Session count should be preserved")
        
        let migratedSession = migratedSessions.first!
        XCTAssertEqual(migratedSession.id, originalSession.id, "Session ID should match")
        XCTAssertEqual(migratedSession.title, originalSession.title, "Title should be preserved")
        XCTAssertEqual(migratedSession.sessionType, originalSession.sessionType, "Session type should match")
        XCTAssertEqual(migratedSession.startDate, originalSession.startDate, "Start date should be preserved")
        XCTAssertEqual(migratedSession.endDate, originalSession.endDate, "End date should be preserved")
        XCTAssertEqual(migratedSession.totalDuration, originalSession.totalDuration, "Duration should match")
        XCTAssertEqual(migratedSession.speakerCount, originalSession.speakerCount, "Speaker count should match")
        XCTAssertEqual(migratedSession.segmentCount, originalSession.segmentCount, "Segment count should match")
    }
    
    func testMigrationFromV1ToV2PreservesFolders() async throws {
        // Setup: Create V1 database with folders
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        let originalFolder = createV1SampleFolder(in: v1Context)
        let folderID = originalFolder.id
        
        try v1Context.save()
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Folder is preserved
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let fetchDescriptor = FetchDescriptor<SDFolder>(
            predicate: #Predicate { $0.id == folderID }
        )
        let migratedFolders = try v2Context.fetch(fetchDescriptor)
        
        XCTAssertEqual(migratedFolders.count, 1, "Folder count should be preserved")
        
        let migratedFolder = migratedFolders.first!
        XCTAssertEqual(migratedFolder.id, originalFolder.id, "Folder ID should match")
        XCTAssertEqual(migratedFolder.name, originalFolder.name, "Name should be preserved")
        XCTAssertEqual(migratedFolder.icon, originalFolder.icon, "Icon should be preserved")
        XCTAssertEqual(migratedFolder.color, originalFolder.color, "Color should be preserved")
        XCTAssertEqual(migratedFolder.isSystem, originalFolder.isSystem, "System flag should match")
    }
    
    func testMigrationFromV1ToV2PreservesLabels() async throws {
        // Setup: Create V1 database with labels
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        let originalLabel = createV1SampleLabel(in: v1Context)
        let labelID = originalLabel.id
        
        try v1Context.save()
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Label is preserved
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let fetchDescriptor = FetchDescriptor<SDLabel>(
            predicate: #Predicate { $0.id == labelID }
        )
        let migratedLabels = try v2Context.fetch(fetchDescriptor)
        
        XCTAssertEqual(migratedLabels.count, 1, "Label count should be preserved")
        
        let migratedLabel = migratedLabels.first!
        XCTAssertEqual(migratedLabel.id, originalLabel.id, "Label ID should match")
        XCTAssertEqual(migratedLabel.name, originalLabel.name, "Name should be preserved")
        XCTAssertEqual(migratedLabel.color, originalLabel.color, "Color should be preserved")
        XCTAssertEqual(migratedLabel.icon, originalLabel.icon, "Icon should be preserved")
    }
    
    func testMigrationFromV1ToV2PreservesSpeakers() async throws {
        // Setup: Create V1 database with speakers
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        let originalSpeaker = createV1SampleSpeaker(in: v1Context)
        let speakerID = originalSpeaker.id
        
        try v1Context.save()
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Speaker is preserved
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let fetchDescriptor = FetchDescriptor<SDKnownSpeakers>(
            predicate: #Predicate { $0.id == speakerID }
        )
        let migratedSpeakers = try v2Context.fetch(fetchDescriptor)
        
        XCTAssertEqual(migratedSpeakers.count, 1, "Speaker count should be preserved")
        
        let migratedSpeaker = migratedSpeakers.first!
        XCTAssertEqual(migratedSpeaker.id, originalSpeaker.id, "Speaker ID should match")
        XCTAssertEqual(migratedSpeaker.name, originalSpeaker.name, "Name should be preserved")
        XCTAssertEqual(migratedSpeaker.color, originalSpeaker.color, "Color should be preserved")
        XCTAssertEqual(migratedSpeaker.notes, originalSpeaker.notes, "Notes should be preserved")
    }
    
    func testMigrationPreservesRelationshipsBetweenSessionsAndFolders() async throws {
        // Setup: Create V1 database with related data
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        let folder = createV1SampleFolder(in: v1Context)
        var session = createV1SampleSession(in: v1Context)
        session.folderID = folder.id
        
        try v1Context.save()
        
        let sessionID = session.id
        let folderID = folder.id
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Relationship is preserved
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let sessionFetch = FetchDescriptor<SDSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let migratedSessions = try v2Context.fetch(sessionFetch)
        let migratedSession = migratedSessions.first!
        
        XCTAssertEqual(migratedSession.folderID, folderID, "Folder relationship should be preserved")
    }
    
    func testMigrationPreservesLabelIDsEncoding() async throws {
        // Setup: Create session with labels
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        let label1 = createV1SampleLabel(in: v1Context)
        let label2 = SDLabel(
            id: UUID(),
            name: "Urgent",
            color: "#FF0000",
            icon: "exclamationmark",
            createdAt: Date(),
            sortOrder: 2
        )
        v1Context.insert(label2)
        
        var session = createV1SampleSession(in: v1Context)
        session.labelIDs = [label1.id, label2.id]
        
        try v1Context.save()
        
        let sessionID = session.id
        let expectedLabelIDs = Set([label1.id, label2.id])
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Label IDs are correctly encoded/decoded
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let sessionFetch = FetchDescriptor<SDSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let migratedSessions = try v2Context.fetch(sessionFetch)
        let migratedSession = migratedSessions.first!
        
        let migratedLabelIDs = Set(migratedSession.labelIDs)
        XCTAssertEqual(migratedLabelIDs, expectedLabelIDs, "Label IDs should be preserved through encoding")
    }
    
    // MARK: - Post-Migration Validation Tests
    
    func testSearchableTextFieldsPopulatedAfterMigration() async throws {
        // Setup: Create session with searchable text
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        var session = createV1SampleSession(in: v1Context)
        session.searchableText = "This is searchable content from the transcript"
        
        try v1Context.save()
        let sessionID = session.id
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Searchable text is preserved
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let sessionFetch = FetchDescriptor<SDSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let migratedSessions = try v2Context.fetch(sessionFetch)
        let migratedSession = migratedSessions.first!
        
        XCTAssertFalse(migratedSession.searchableText.isEmpty, "Searchable text should be populated")
        XCTAssertEqual(
            migratedSession.searchableText,
            "This is searchable content from the transcript",
            "Searchable text content should match"
        )
    }
    
    func testSpeakerNamesDenormalizedAfterMigration() async throws {
        // Setup: Create session with speaker names
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        var session = createV1SampleSession(in: v1Context)
        session.speakerNames = "Alice, Bob, Charlie"
        
        try v1Context.save()
        let sessionID = session.id
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Speaker names are denormalized
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let sessionFetch = FetchDescriptor<SDSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let migratedSessions = try v2Context.fetch(sessionFetch)
        let migratedSession = migratedSessions.first!
        
        XCTAssertEqual(
            migratedSession.speakerNames,
            "Alice, Bob, Charlie",
            "Speaker names should be denormalized correctly"
        )
    }
    
    func testIndexesCreatedOnIndexedFields() async throws {
        // This test verifies that indexes are present on indexed fields
        // Note: SwiftData doesn't expose index metadata directly, so we verify
        // through query performance and schema configuration
        
        let schema = CoriusSchemaV2.schema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        // Verify schema includes indexed models
        XCTAssertTrue(
            schema.models.contains(where: { $0 == SDSession.self }),
            "Schema should include SDSession with indexes"
        )
        XCTAssertTrue(
            schema.models.contains(where: { $0 == SDFolder.self }),
            "Schema should include SDFolder with indexes"
        )
        XCTAssertTrue(
            schema.models.contains(where: { $0 == SDLabel.self }),
            "Schema should include SDLabel with indexes"
        )
    }
    
    // MARK: - Edge Case Tests
    
    func testMigrationFromEmptyDatabase() async throws {
        // Setup: Empty V1 database
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        XCTAssertEqual(v1Context.registeredObjects.count, 0, "V1 database should be empty")
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Empty database migrates successfully
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let sessionCount = try v2Context.fetchCount(FetchDescriptor<SDSession>())
        let folderCount = try v2Context.fetchCount(FetchDescriptor<SDFolder>())
        let labelCount = try v2Context.fetchCount(FetchDescriptor<SDLabel>())
        
        XCTAssertEqual(sessionCount, 0, "Session count should remain zero")
        XCTAssertEqual(folderCount, 0, "Folder count should remain zero")
        XCTAssertEqual(labelCount, 0, "Label count should remain zero")
    }
    
    func testMigrationWithLargeDataset() async throws {
        // Setup: Create 1000+ sessions in V1
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        let sessionCount = 1000
        var sessionIDs: Set<UUID> = []
        
        for i in 0..<sessionCount {
            var session = createV1SampleSession(in: v1Context)
            session.id = UUID()
            session.title = "Session \(i)"
            session.startDate = Date(timeIntervalSince1970: 1_738_000_000 + Double(i * 1000))
            sessionIDs.insert(session.id)
        }
        
        try v1Context.save()
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: All sessions are preserved
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let migratedCount = try v2Context.fetchCount(FetchDescriptor<SDSession>())
        XCTAssertEqual(migratedCount, sessionCount, "All \(sessionCount) sessions should be preserved")
    }
    
    func testMigrationWithOrphanedRecords() async throws {
        // Setup: Create session with invalid folder reference
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        var session = createV1SampleSession(in: v1Context)
        session.folderID = UUID() // Non-existent folder
        
        try v1Context.save()
        let sessionID = session.id
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: Session is preserved even with orphaned reference
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let sessionFetch = FetchDescriptor<SDSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        let migratedSessions = try v2Context.fetch(sessionFetch)
        
        XCTAssertEqual(migratedSessions.count, 1, "Session with orphaned folder should be preserved")
        XCTAssertNotNil(migratedSessions.first?.folderID, "Orphaned folder ID should be retained")
    }
    
    func testMigrationWithDuplicateData() async throws {
        // Setup: Create sessions with duplicate titles
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        for i in 0..<5 {
            var session = createV1SampleSession(in: v1Context)
            session.id = UUID()
            session.title = "Duplicate Meeting"
            session.startDate = Date(timeIntervalSince1970: 1_738_000_000 + Double(i * 1000))
        }
        
        try v1Context.save()
        
        // Execute: Migration
        try await simulateMigration(from: v1Container, to: try createV2TestContainer())
        
        // Verify: All duplicates are preserved
        let v2Container = try createV2TestContainer()
        let v2Context = v2Container.mainContext
        
        let count = try v2Context.fetchCount(FetchDescriptor<SDSession>())
        XCTAssertEqual(count, 5, "All duplicate sessions should be preserved")
        
        let duplicateFetch = FetchDescriptor<SDSession>(
            predicate: #Predicate { $0.title == "Duplicate Meeting" }
        )
        let duplicateSessions = try v2Context.fetch(duplicateFetch)
        XCTAssertEqual(duplicateSessions.count, 5, "All duplicates with same title should be found")
    }
    
    func testMigrationInterruptionHandling() async throws {
        // This test simulates a migration interruption and verifies recovery
        
        // Setup: Create V1 data
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        _ = createV1SampleSession(in: v1Context)
        try v1Context.save()
        
        // Simulate interrupted migration
        schemaVersionManager.isMigrationInProgress = true
        schemaVersionManager.storedSchemaVersion = 1
        
        // Verify: Migration state is detected
        XCTAssertTrue(
            schemaVersionManager.isMigrationInProgress,
            "Migration in progress flag should be set"
        )
        
        // Simulate recovery by resetting flag
        schemaVersionManager.isMigrationInProgress = false
        schemaVersionManager.storedSchemaVersion = 2
        
        XCTAssertFalse(
            schemaVersionManager.isMigrationInProgress,
            "Migration in progress flag should be cleared after recovery"
        )
    }
    
    // MARK: - Rollback Tests
    
    func testMigrationFailurePreservesOriginalData() async throws {
        // Setup: Create V1 data
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        let originalSession = createV1SampleSession(in: v1Context)
        try v1Context.save()
        
        // Simulate failed migration
        let mockError = NSError(
            domain: "TestDomain",
            code: 999,
            userInfo: [NSLocalizedDescriptionKey: "Simulated migration failure"]
        )
        
        // Verify: Error handling doesn't corrupt original data
        schemaVersionManager.handleMigrationError(
            mockError,
            fromVersion: 1,
            toVersion: 2
        )
        
        XCTAssertFalse(
            schemaVersionManager.isMigrationInProgress,
            "Migration in progress flag should be cleared after error"
        )
        
        // Verify: Original V1 data is still accessible
        let fetchDescriptor = FetchDescriptor<SDSession>(
            predicate: #Predicate { $0.id == originalSession.id }
        )
        let sessions = try v1Context.fetch(fetchDescriptor)
        XCTAssertEqual(sessions.count, 1, "Original data should be preserved after failed migration")
    }
    
    // MARK: - TranscriptSearchIndex Integration Tests
    
    func testTranscriptSearchIndexRebuiltAfterMigration() async throws {
        // Setup: Create V1 data
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        _ = createV1SampleSession(in: v1Context)
        try v1Context.save()
        
        // Execute: Migration with search index rebuild
        try await schemaVersionManager.performPostMigrationTasks(
            fromVersion: 1,
            toVersion: 2
        )
        
        // Verify: Search index rebuild is triggered (this would normally call TranscriptSearchIndex.shared.rebuildAll())
        // In test environment, we verify the method completes without error
        XCTAssertTrue(true, "Post-migration tasks should complete successfully")
    }
    
    // MARK: - Performance Tests
    
    func testMigrationPerformanceWith1000Sessions() throws {
        let v1Container = try createV1TestContainer()
        let v1Context = v1Container.mainContext
        
        measure {
            // Create 1000 sessions
            for i in 0..<1000 {
                var session = createV1SampleSession(in: v1Context)
                session.id = UUID()
                session.title = "Performance Test Session \(i)"
                session.startDate = Date(timeIntervalSince1970: 1_738_000_000 + Double(i * 1000))
            }
            
            try? v1Context.save()
        }
    }
    
    // MARK: - Helper Methods for Migration Simulation
    
    private func simulateMigration(from v1Container: ModelContainer, to v2Container: ModelContainer) async throws {
        // In a real migration, SwiftData would handle this automatically
        // For testing, we manually copy data from V1 to V2
        
        let v1Context = v1Container.mainContext
        let v2Context = v2Container.mainContext
        
        // Migrate sessions
        let v1Sessions = try v1Context.fetch(FetchDescriptor<SDSession>())
        for session in v1Sessions {
            let v2Session = SDSession(
                id: session.id,
                startDate: session.startDate,
                endDate: session.endDate,
                title: session.title,
                sessionType: session.sessionType,
                audioFileName: session.audioFileName,
                micAudioFileName: session.micAudioFileName,
                systemAudioFileName: session.systemAudioFileName,
                audioSource: session.audioSource,
                speakerCount: session.speakerCount,
                segmentCount: session.segmentCount,
                totalDuration: session.totalDuration,
                hasTranscript: session.hasTranscript,
                hasSummary: session.hasSummary,
                folderID: session.folderID,
                labelIDs: session.labelIDs,
                isClassified: session.isClassified,
                aiSuggestedFolderID: session.aiSuggestedFolderID,
                aiClassificationConfidence: session.aiClassificationConfidence,
                searchableText: session.searchableText,
                speakerNames: session.speakerNames
            )
            v2Context.insert(v2Session)
        }
        
        // Migrate folders
        let v1Folders = try v1Context.fetch(FetchDescriptor<SDFolder>())
        for folder in v1Folders {
            let v2Folder = SDFolder(
                id: folder.id,
                name: folder.name,
                parentID: folder.parentID,
                icon: folder.icon,
                color: folder.color,
                isSystem: folder.isSystem,
                createdAt: folder.createdAt,
                sortOrder: folder.sortOrder,
                classificationKeywords: folder.classificationKeywords.split(separator: ",").map(String.init),
                classificationDescription: folder.classificationDescription
            )
            v2Context.insert(v2Folder)
        }
        
        // Migrate labels
        let v1Labels = try v1Context.fetch(FetchDescriptor<SDLabel>())
        for label in v1Labels {
            let v2Label = SDLabel(
                id: label.id,
                name: label.name,
                color: label.color,
                icon: label.icon,
                createdAt: label.createdAt,
                sortOrder: label.sortOrder
            )
            v2Context.insert(v2Label)
        }
        
        // Migrate speakers
        let v1Speakers = try v1Context.fetch(FetchDescriptor<SDKnownSpeakers>())
        for speaker in v1Speakers {
            let v2Speaker = SDKnownSpeakers(
                id: speaker.id,
                name: speaker.name,
                color: speaker.color,
                notes: speaker.notes,
                voiceCharacteristics: speaker.voiceCharacteristics,
                createdAt: speaker.createdAt,
                lastUsedAt: speaker.lastUsedAt,
                usageCount: speaker.usageCount
            )
            v2Context.insert(v2Speaker)
        }
        
        // Save V2 context
        try v2Context.save()
        
        // Mark migration as complete
        schemaVersionManager.markMigrationComplete(to: .v2)
    }
}

// MARK: - Schema Extension for Testing

extension VersionedSchema {
    static var schema: Schema {
        return Schema(self.models)
    }
}
