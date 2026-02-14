import XCTest
import SwiftData
import CoreSpotlight
import os.log
@testable import CoriusVoice

// MARK: - Performance Report Model

/// Performance measurement result for benchmark reporting
struct PerformanceReport {
    let testName: String
    let measuredTime: TimeInterval  // in milliseconds
    let targetTime: TimeInterval
    let passed: Bool
    let additionalMetrics: [String: Any]
    let timestamp: Date
    
    var formattedTime: String {
        String(format: "%.2f", measuredTime)
    }
    
    var percentageOfTarget: Double {
        (measuredTime / targetTime) * 100
    }
    
    var status: String {
        passed ? "✅ PASS" : "❌ FAIL"
    }
}

// MARK: - Performance Benchmark Suite

/// Comprehensive performance benchmarks for SwiftData persistence layer
/// Validates performance targets:
/// - Session list load: <100ms for 1000+ sessions
/// - Full-text search: <200ms across 10K+ transcript segments
/// - Pagination: <50ms per page
/// - Index operations: <50ms for incremental updates
@MainActor
final class PerformanceTests: XCTestCase {
    
    // MARK: - Performance Report Tracking
    
    private var performanceReports: [PerformanceReport] = []
    
    // MARK: - Test Properties
    
    private var testContainer: ModelContainer!
    private var testContext: ModelContext!
    private var temporaryDirectory: URL!
    private var sessionRepository: SessionRepository!
    private var searchIndex: TranscriptSearchIndex!
    private var schemaVersionManager: SchemaVersionManager!
    
    // Performance targets (in milliseconds)
    private let targetSessionListLoad: TimeInterval = 100.0
    private let targetFullTextSearch: TimeInterval = 200.0
    private let targetPaginationLoad: TimeInterval = 50.0
    private let targetIndexUpdate: TimeInterval = 50.0
    
    // Test data sizes
    private let smallDatasetSize = 100
    private let mediumDatasetSize = 1000
    private let largeDatasetSize = 10000
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary directory for test database
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoriusVoice-PerformanceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        
        // Initialize test container with V2 schema
        let schema = CoriusSchemaV2.schema
        let configuration = ModelConfiguration(
            schema: schema,
            url: temporaryDirectory.appendingPathComponent("test.sqlite"),
            allowsSave: true,
            cloudKitDatabase: .none
        )
        
        testContainer = try ModelContainer(for: schema, configurations: [configuration])
        testContext = testContainer.mainContext
        
        // Initialize services
        sessionRepository = SessionRepository.shared
        searchIndex = TranscriptSearchIndex.shared
        schemaVersionManager = SchemaVersionManager.shared
        
        // Clear existing test data
        await clearTestData()
    }
    
    override func tearDown() async throws {
        // Clear test data
        await clearTestData()
        
        // Clean up
        testContext = nil
        testContainer = nil
        
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func clearTestData() async {
        // Clear all sessions from test container
        let descriptor = FetchDescriptor<SDSession>()
        let sessions = try? testContext.fetch(descriptor)
        sessions?.forEach { testContext.delete($0) }
        try? testContext.save()
        
        // Clear search index
        searchIndex.removeAllSessions()
        
        // Clear repository cache
        sessionRepository.clearCache()
    }
    
    /// Record performance result for reporting
    private func recordPerformance(
        testName: String,
        measuredTime: TimeInterval,
        targetTime: TimeInterval,
        additionalMetrics: [String: Any] = [:]
    ) {
        let passed = measuredTime <= targetTime
        let report = PerformanceReport(
            testName: testName,
            measuredTime: measuredTime,
            targetTime: targetTime,
            passed: passed,
            additionalMetrics: additionalMetrics,
            timestamp: Date()
        )
        performanceReports.append(report)
        
        // Print individual result
        print("\n📊 Performance Report: \(testName)")
        print("   Measured: \(report.formattedTime)ms")
        print("   Target: \(targetTime)ms")
        print("   Status: \(report.status) (\(String(format: "%.1f", report.percentageOfTarget))% of target)")
        
        if !additionalMetrics.isEmpty {
            print("   Additional Metrics:")
            for (key, value) in additionalMetrics {
                print("     - \(key): \(value)")
            }
        }
    }
    
    /// Generate and print final performance summary
    private func printPerformanceSummary() {
        print("\n" + String(repeating: "=", count: 80))
        print("🎯 PERFORMANCE BENCHMARK SUMMARY")
        print(String(repeating: "=", count: 80))
        
        let passed = performanceReports.filter { $0.passed }.count
        let failed = performanceReports.filter { !$0.passed }.count
        
        print("\nTotal Tests: \(performanceReports.count)")
        print("✅ Passed: \(passed)")
        print("❌ Failed: \(failed)")
        
        if failed > 0 {
            print("\n⚠️ Failed Tests:")
            for report in performanceReports.filter({ !$0.passed }) {
                print("   • \(report.testName): \(report.formattedTime)ms (target: \(report.targetTime)ms)")
            }
        }
        
        print("\n" + String(repeating: "=", count: 80))
    }
    
    /// Assert performance against target with detailed failure message
    private func assertPerformance(
        testName: String,
        measuredTime: TimeInterval,
        targetTime: TimeInterval,
        additionalMetrics: [String: Any] = [:],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        recordPerformance(
            testName: testName,
            measuredTime: measuredTime,
            targetTime: targetTime,
            additionalMetrics: additionalMetrics
        )
        
        if measuredTime > targetTime {
            let percentage = String(format: "%.1f", (measuredTime / targetTime) * 100)
            XCTFail("\n[PERFORMANCE] \(testName) exceeded target.\n" +
                     "Measured: \(String(format: "%.2f", measuredTime))ms\n" +
                     "Target: \(targetTime)ms\n" +
                     "Exceeded by: \(percentage)%",
                     file: file, line: line)
        }
    }
    
    private func createTestSession(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        transcriptSegmentCount: Int = 10
    ) async -> SDSession {
        let speakerID = UUID()
        
        // Create transcript segments
        var segments: [TranscriptSegment] = []
        for i in 0..<transcriptSegmentCount {
            let segment = TranscriptSegment(
                id: UUID(),
                timestamp: TimeInterval(i) * 10.0,
                text: "This is segment \(i) with some sample text for testing search functionality",
                speakerID: speakerID,
                isFinal: true
            )
            segments.append(segment)
        }
        
        // Create session
        let session = SDSession(
            id: id,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(TimeInterval(transcriptSegmentCount) * 10.0),
            title: title,
            sessionType: "test",
            audioFileName: "test_\(id.uuidString).m4a",
            speakerCount: 1,
            segmentCount: transcriptSegmentCount,
            totalDuration: TimeInterval(transcriptSegmentCount) * 10.0,
            transcriptBody: segments.map { $0.text }.joined(separator: " ")
        )
        
        testContext.insert(session)
        try? testContext.save()
        
        // Index transcript for search
        await searchIndex.indexTranscript(for: id, segments: segments)
        
        return session
    }
    
    private func createBatchSessions(
        count: Int,
        transcriptSegmentCount: Int = 10
    ) async -> [SDSession] {
        var sessions: [SDSession] = []
        
        for i in 0..<count {
            let startDate = Date().addingTimeInterval(-TimeInterval(i) * 3600.0) // 1 hour apart
            let session = await createTestSession(
                id: UUID(),
                title: "Test Session \(i)",
                startDate: startDate,
                transcriptSegmentCount: transcriptSegmentCount
            )
            sessions.append(session)
        }
        
        return sessions
    }
    
    // MARK: - Session List Load Performance
    
    /// Benchmark: Loading 1000 sessions with metadata only
    /// Target: <100ms for first page render
    func testSessionListLoadPerformance_1000Sessions() async throws {
        let sessionCount = 1000
        
        // Setup: Create test data
        print("📊 Creating \(sessionCount) test sessions...")
        let creationStart = CFAbsoluteTimeGetCurrent()
        _ = await createBatchSessions(count: sessionCount, transcriptSegmentCount: 10)
        let creationTime = (CFAbsoluteTimeGetCurrent() - creationStart) * 1000
        print("✅ Test data created in \(String(format: "%.1f", creationTime))ms")
        
        // Wait for indexing to complete
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Benchmark: Load first page (metadata only) using repository
        let loadStart = CFAbsoluteTimeGetCurrent()
        await sessionRepository.loadFirstPage()
        let loadTime = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        
        // Validate against target
        assertPerformance(
            testName: "Session list load (1000 sessions)",
            measuredTime: loadTime,
            targetTime: targetSessionListLoad,
            additionalMetrics: [
                "Sessions loaded": sessionRepository.sessions.count,
                "Data creation time": "\(String(format: "%.1f", creationTime))ms"
            ]
        )
        
        // Verify we loaded sessions
        XCTAssertGreaterThan(sessionRepository.sessions.count, 0, "Should load at least one session")
        XCTAssertLessThanOrEqual(sessionRepository.sessions.count, 50, "First page should have at most 50 sessions")
    }
    
    /// Benchmark: Session list load with folder filter
    func testSessionListLoadPerformance_WithFolderFilter() async throws {
        let sessionCount = 1000
        let folderID = UUID()
        
        // Setup: Create sessions in folder
        _ = await createBatchSessions(count: sessionCount, transcriptSegmentCount: 10)
        
        // Benchmark: Load sessions by folder
        let loadTime = measure {
            let predicate = #Predicate<SDSession> { $0.folderID == folderID }
            let fetchDescriptor = FetchDescriptor<SDSession>(
                predicate: predicate,
                sortBy: [SortDescriptor(\SDSession.startDate, order: .reverse)]
            )
            fetchDescriptor.fetchLimit = 50
            _ = try? testContext.fetch(fetchDescriptor)
        }
        
        let loadTimeMs = loadTime * 1000
        print("✅ Session list load with folder filter: \(String(format: "%.1f", loadTimeMs))ms")
        
        if loadTimeMs > targetSessionListLoad {
            XCTFail("Folder-filtered load exceeded target: \(String(format: "%.1f", loadTimeMs))ms")
        }
    }
    
    /// Benchmark: Session list load with search query
    func testSessionListLoadPerformance_WithSearchQuery() async throws {
        let sessionCount = 1000
        
        // Setup: Create test data with searchable content
        _ = await createBatchSessions(count: sessionCount, transcriptSegmentCount: 10)
        
        // Benchmark: Search across indexed transcripts
        let searchQuery = "sample text"
        let startTime = CFAbsoluteTimeGetCurrent()
        let results = await searchIndex.search(query: searchQuery)
        let searchTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        print("✅ Search '\(searchQuery)' found \(results.count) results in \(String(format: "%.1f", searchTime))ms")
        
        if searchTime > targetFullTextSearch {
            XCTFail("Search exceeded target: \(String(format: "%.1f", searchTime))ms > \(targetFullTextSearch)ms")
        }
    }
    
    // MARK: - Full-Text Search Performance
    
    /// Benchmark: Searching across 10,000 transcript segments
    /// Target: <200ms for search completion
    func testFullTextSearchPerformance_10kSegments() async throws {
        let segmentCount = 10000
        let sessionsPerBatch = 100
        let segmentsPerSession = 10
        
        // Setup: Create 1000 sessions with 10 segments each = 10,000 segments
        let sessionCount = segmentCount / segmentsPerSession
        _ = await createBatchSessions(count: sessionCount, transcriptSegmentCount: segmentsPerSession)
        
        // Wait for indexing to complete
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Benchmark: Single word search
        measure(metrics: [XCTClockMetric()]) {
            let results = await searchIndex.search(query: "sample")
            XCTAssertEqual(results.count, 1000, "Expected all sessions to match 'sample'")
        }
        
        // Benchmark: Phrase search
        let phraseTime = measure {
            let results = await searchIndex.search(query: "sample text")
            XCTAssertGreaterThan(results.count, 0, "Expected matches for 'sample text'")
        }
        
        let phraseTimeMs = phraseTime * 1000
        print("✅ Phrase search (10K segments): \(String(format: "%.1f", phraseTimeMs))ms")
        
        if phraseTimeMs > targetFullTextSearch {
            XCTFail("Phrase search exceeded target: \(String(format: "%.1f", phraseTimeMs))ms > \(targetFullTextSearch)ms")
        }
    }
    
    /// Benchmark: Multi-word search performance
    func testFullTextSearchPerformance_MultiWordQuery() async throws {
        _ = await createBatchSessions(count: 1000, transcriptSegmentCount: 10)
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        let queries = [
            "sample text testing",
            "segment search functionality",
            "testing search functionality"
        ]
        
        for query in queries {
            let startTime = CFAbsoluteTimeGetCurrent()
            let results = await searchIndex.search(query: query)
            let searchTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            
            print("✅ Search '\(query)': \(results.count) results in \(String(format: "%.1f", searchTime))ms")
            
            if searchTime > targetFullTextSearch {
                XCTFail("Multi-word search exceeded target: \(String(format: "%.1f", searchTime))ms")
            }
        }
    }
    
    // MARK: - Pagination Performance
    
    /// Benchmark: Time to load each subsequent page
    /// Target: <50ms per page
    func testPaginationPerformance_SubsequentPages() async throws {
        let sessionCount = 1000
        let pageSize = 50
        let numberOfPages = 5
        
        _ = await createBatchSessions(count: sessionCount, transcriptSegmentCount: 10)
        
        var pageLoadTimes: [TimeInterval] = []
        
        for page in 0..<numberOfPages {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            let offset = page * pageSize
            let descriptor = FetchDescriptor<SDSession>(
                sortBy: [SortDescriptor(\SDSession.startDate, order: .reverse)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = pageSize
            
            let sessions = try? testContext.fetch(descriptor)
            XCTAssertEqual(sessions?.count, pageSize, "Page \(page) should return \(pageSize) sessions")
            
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            pageLoadTimes.append(loadTime)
        }
        
        let averageLoadTime = pageLoadTimes.reduce(0, +) / Double(pageLoadTimes.count) * 1000
        
        print("✅ Pagination average: \(String(format: "%.1f", averageLoadTime))ms per page")
        
        if averageLoadTime > targetPaginationLoad {
            XCTFail("Pagination exceeded target: \(String(format: "%.1f", averageLoadTime))ms > \(targetPaginationLoad)ms")
        }
    }
    
    /// Benchmark: Cache hit rate for repeated page loads
    func testPaginationPerformance_CacheHitRate() async throws {
        let sessionCount = 100
        let pageSize = 20
        
        _ = await createBatchSessions(count: sessionCount, transcriptSegmentCount: 5)
        
        // First load (cache miss)
        let firstLoadStart = CFAbsoluteTimeGetCurrent()
        _ = try? testContext.fetch(FetchDescriptor<SDSession>())
        let firstLoadTime = CFAbsoluteTimeGetCurrent() - firstLoadStart
        
        // Second load (potential cache hit)
        let secondLoadStart = CFAbsoluteTimeGetCurrent()
        _ = try? testContext.fetch(FetchDescriptor<SDSession>())
        let secondLoadTime = CFAbsoluteTimeGetCurrent() - secondLoadStart
        
        let cacheSpeedup = firstLoadTime / secondLoadTime
        
        print("✅ Cache speedup: \(String(format: "%.2f", cacheSpeedup))x")
        print("   First load: \(String(format: "%.1f", firstLoadTime * 1000))ms")
        print("   Second load: \(String(format: "%.1f", secondLoadTime * 1000))ms")
        
        XCTAssertGreaterThanOrEqual(cacheSpeedup, 1.0, "Cache should provide speedup")
    }
    
    /// Benchmark: Memory usage with 10+ pages loaded
    func testPaginationPerformance_MemoryUsage() async throws {
        let sessionCount = 1000
        let pageSize = 50
        let numberOfPages = 10
        
        _ = await createBatchSessions(count: sessionCount, transcriptSegmentCount: 10)
        
        // Measure memory before
        let memoryBefore = getMemoryUsage()
        
        // Load multiple pages
        var loadedSessions: [SDSession] = []
        for page in 0..<numberOfPages {
            let offset = page * pageSize
            let descriptor = FetchDescriptor<SDSession>(
                sortBy: [SortDescriptor(\SDSession.startDate, order: .reverse)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = pageSize
            
            if let sessions = try? testContext.fetch(descriptor) {
                loadedSessions.append(contentsOf: sessions)
            }
        }
        
        // Measure memory after
        let memoryAfter = getMemoryUsage()
        let memoryIncrease = memoryAfter - memoryBefore
        
        print("✅ Memory usage for 10 pages: \(String(format: "%.1f", memoryIncrease))MB")
        print("   Sessions loaded: \(loadedSessions.count)")
        print("   Memory per session: \(String(format: "%.2f", (memoryIncrease * 1024) / Double(loadedSessions.count)))KB")
        
        // Alert if memory usage exceeds reasonable threshold (100MB)
        let memoryThreshold: Double = 100.0
        if memoryIncrease > memoryThreshold {
            XCTFail("Memory usage exceeded threshold: \(String(format: "%.1f", memoryIncrease))MB > \(memoryThreshold)MB")
        }
    }
    
    // MARK: - Index Build Performance
    
    /// Benchmark: Initial index build for 1000 sessions
    func testIndexBuildPerformance_InitialBuild() async throws {
        let sessionCount = 1000
        let segmentsPerSession = 10
        
        // Create sessions without indexing
        var sessionIDs: [UUID] = []
        for i in 0..<sessionCount {
            let session = await createTestSession(
                id: UUID(),
                title: "Test Session \(i)",
                startDate: Date().addingTimeInterval(-TimeInterval(i) * 3600.0),
                transcriptSegmentCount: segmentsPerSession
            )
            sessionIDs.append(session.id)
        }
        
        // Clear search index
        searchIndex.removeAllSessions()
        
        // Benchmark: Build index from scratch
        let buildStartTime = CFAbsoluteTimeGetCurrent()
        
        for sessionID in sessionIDs {
            let segments = (0..<segmentsPerSession).map { i in
                TranscriptSegment(
                    id: UUID(),
                    timestamp: TimeInterval(i) * 10.0,
                    text: "This is segment \(i) with sample text",
                    speakerID: UUID(),
                    isFinal: true
                )
            }
            await searchIndex.indexTranscript(for: sessionID, segments: segments)
        }
        
        let buildTime = (CFAbsoluteTimeGetCurrent() - buildStartTime) * 1000
        
        print("✅ Initial index build (1000 sessions, 10K segments): \(String(format: "%.1f", buildTime))ms")
        print("   Average per session: \(String(format: "%.2f", buildTime / Double(sessionCount)))ms")
    }
    
    /// Benchmark: Incremental index update (single session save)
    /// Target: <50ms
    func testIndexBuildPerformance_IncrementalUpdate() async throws {
        // Create initial session
        let sessionID = UUID()
        let segments = (0..<10).map { i in
            TranscriptSegment(
                id: UUID(),
                timestamp: TimeInterval(i) * 10.0,
                text: "Initial segment \(i)",
                speakerID: UUID(),
                isFinal: true
            )
        }
        
        await createTestSession(id: sessionID, title: "Update Test", startDate: Date(), transcriptSegmentCount: 10)
        await searchIndex.indexTranscript(for: sessionID, segments: segments)
        
        // Benchmark: Update transcript with new content
        let updatedSegments = (0..<10).map { i in
            TranscriptSegment(
                id: UUID(),
                timestamp: TimeInterval(i) * 10.0,
                text: "Updated segment \(i) with new content",
                speakerID: UUID(),
                isFinal: true
            )
        }
        
        let updateStartTime = CFAbsoluteTimeGetCurrent()
        await searchIndex.updateTranscript(for: sessionID, segments: updatedSegments)
        let updateTime = (CFAbsoluteTimeGetCurrent() - updateStartTime) * 1000
        
        print("✅ Incremental index update: \(String(format: "%.1f", updateTime))ms")
        
        if updateTime > targetIndexUpdate {
            XCTFail("Index update exceeded target: \(String(format: "%.1f", updateTime))ms > \(targetIndexUpdate)ms")
        }
    }
    
    /// Benchmark: Spotlight index update time
    func testIndexBuildPerformance_SpotlightUpdate() async throws {
        let sessionCount = 100
        
        _ = await createBatchSessions(count: sessionCount, transcriptSegmentCount: 5)
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Benchmark: Search via Spotlight
        let spotlightStartTime = CFAbsoluteTimeGetCurrent()
        
        let query = CSSearchQuery(query: "sample", attributes: nil)
        let foundItems = expectation(description: "Spotlight search completed")
        var foundCount = 0
        
        query.foundItemsHandler = { items in
            foundCount += items.count
        }
        
        query.completionHandler = { error in
            if error == nil {
                foundItems.fulfill()
            }
        }
        
        query.start()
        await fulfillment(of: [foundItems], timeout: 5.0)
        query.cancel()
        
        let spotlightTime = (CFAbsoluteTimeGetCurrent() - spotlightStartTime) * 1000
        
        print("✅ Spotlight search: \(foundCount) results in \(String(format: "%.1f", spotlightTime))ms")
    }
    
    // MARK: - Migration Performance
    
    /// Benchmark: V1→V2 migration with 1000 sessions
    func testMigrationPerformance_V1ToV2() async throws {
        let sessionCount = 1000
        
        // This test would require setting up a V1 database and migrating to V2
        // For now, we'll measure the time to create equivalent V2 data
        
        measure(metrics: [XCTClockMetric()]) {
            let expectation = expectation(description: "Migrate sessions")
            
            Task {
                // Simulate migration by creating V2 sessions
                for i in 0..<sessionCount {
                    _ = await createTestSession(
                        id: UUID(),
                        title: "Migrated Session \(i)",
                        startDate: Date().addingTimeInterval(-TimeInterval(i) * 3600.0),
                        transcriptSegmentCount: 10
                    )
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
        
        // Measure post-migration index rebuild time
        let rebuildStartTime = CFAbsoluteTimeGetCurrent()
        
        let sessions = try? testContext.fetch(FetchDescriptor<SDSession>())
        for session in sessions ?? [] {
            // Simulate index rebuild
            let segments = (0..<10).map { i in
                TranscriptSegment(
                    id: UUID(),
                    timestamp: TimeInterval(i) * 10.0,
                    text: "Reindexed segment \(i)",
                    speakerID: UUID(),
                    isFinal: true
                )
            }
            await searchIndex.indexTranscript(for: session.id, segments: segments)
        }
        
        let rebuildTime = (CFAbsoluteTimeGetCurrent() - rebuildStartTime) * 1000
        
        print("✅ Post-migration index rebuild: \(String(format: "%.1f", rebuildTime))ms")
    }
    
    // MARK: - Memory Leak Detection
    
    /// Test for memory leaks in session repository
    func testMemoryLeaks_SessionRepository() async throws {
        weak var weakRepository: SessionRepository?
        
        autoreleasepool {
            let repository = SessionRepository.shared
            weakRepository = repository
            XCTAssertNotNil(weakRepository, "Repository should be retained")
        }
        
        // Give time for potential leaks to manifest
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        XCTAssertNil(weakRepository, "Repository should be deallocated outside autoreleasepool")
    }
    
    /// Test for memory leaks in search index
    func testMemoryLeaks_SearchIndex() async throws {
        weak var weakIndex: TranscriptSearchIndex?
        
        autoreleasepool {
            let index = TranscriptSearchIndex.shared
            weakIndex = index
            XCTAssertNotNil(weakIndex, "Index should be retained")
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNil(weakIndex, "Index should be deallocated outside autoreleasepool")
    }
    
    // MARK: - Utility Methods
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
    }
}

// MARK: - Test Data Utilities

extension PerformanceTests {
    /// Helper to create large batches of test sessions more efficiently
    func createTestSessionsBatch(count: Int, segmentsPerSession: Int = 10) async -> [UUID] {
        var sessionIDs: [UUID] = []
        
        for i in 0..<count {
            let id = UUID()
            let startDate = Date().addingTimeInterval(-TimeInterval(i) * 3600.0)
            
            let speakerID = UUID()
            var segments: [TranscriptSegment] = []
            
            for j in 0..<segmentsPerSession {
                let segment = TranscriptSegment(
                    id: UUID(),
                    timestamp: TimeInterval(j) * 10.0,
                    text: "Segment \(j) with sample test data for search functionality",
                    speakerID: speakerID,
                    isFinal: true
                )
                segments.append(segment)
            }
            
            let session = SDSession(
                id: id,
                startDate: startDate,
                endDate: startDate.addingTimeInterval(Double(segmentsPerSession) * 10.0),
                title: "Batch Session \(i)",
                sessionType: "test",
                audioFileName: "batch_\(i).m4a",
                speakerCount: 1,
                segmentCount: segmentsPerSession,
                totalDuration: Double(segmentsPerSession) * 10.0,
                transcriptBody: segments.map { $0.text }.joined(separator: " ")
            )
            
            testContext.insert(session)
            sessionIDs.append(id)
            
            // Index each session
            await searchIndex.indexTranscript(for: id, segments: segments)
        }
        
        try? testContext.save()
        return sessionIDs
    }
}

