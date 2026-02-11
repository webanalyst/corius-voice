import Foundation
import os.log

/// Performance metrics tracking for cache operations
/// Monitors hit rates, prefetch efficiency, and query performance
@MainActor
final class CacheMetrics: ObservableObject {
    static let shared = CacheMetrics()
    
    private let logger = Logger(subsystem: "com.corius.voice", category: "CacheMetrics")
    
    // MARK: - Cache Statistics
    
    private var metadataCacheHits: Int = 0
    private var metadataCacheMisses: Int = 0
    private var sessionCacheHits: Int = 0
    private var sessionCacheMisses: Int = 0
    
    // MARK: - Query Performance
    
    private var queryDurations: [TimeInterval] = []
    private var prefetchDurations: [TimeInterval] = []
    
    // MARK: - Published Metrics
    
    @Published private(set) var totalHits: Int = 0
    @Published private(set) var totalMisses: Int = 0
    @Published private(set) var averageQueryTime: TimeInterval = 0
    @Published private(set) var averagePrefetchTime: TimeInterval = 0
    
    // MARK: - Constants
    
    private let maxSampleSize = 100
    private let performanceTargetQuery: TimeInterval = 100  // ms
    private let performanceTargetPrefetch: TimeInterval = 500  // ms
    
    private init() {}
    
    // MARK: - Cache Hit/Miss Recording
    
    func recordMetadataCache(hit: Bool) {
        if hit {
            metadataCacheHits += 1
            totalHits += 1
        } else {
            metadataCacheMisses += 1
            totalMisses += 1
        }
    }
    
    func recordSessionCache(hit: Bool) {
        if hit {
            sessionCacheHits += 1
            totalHits += 1
        } else {
            sessionCacheMisses += 1
            totalMisses += 1
        }
    }
    
    // MARK: - Query Performance Recording
    
    func recordQuery(duration: TimeInterval) {
        queryDurations.append(duration)
        if queryDurations.count > maxSampleSize {
            queryDurations.removeFirst()
        }
        
        updateAverageQueryTime()
        
        if duration > performanceTargetQuery {
            logger.warning("⚠️ Query exceeded \(performanceTargetQuery)ms target: \(String(format: "%.1f", duration))ms")
        }
    }
    
    func recordPrefetch(count: Int, duration: TimeInterval) {
        prefetchDurations.append(duration)
        if prefetchDurations.count > maxSampleSize {
            prefetchDurations.removeFirst()
        }
        
        updateAveragePrefetchTime()
        
        let throughput = Double(count) / (duration / 1000)  // sessions per second
        logger.debug("📦 Prefetch: \(count) sessions in \(String(format: "%.1f", duration))ms (\(String(format: "%.1f", throughput)) sessions/sec)")
        
        if duration > performanceTargetPrefetch {
            logger.warning("⚠️ Prefetch exceeded \(performanceTargetPrefetch)ms target: \(String(format: "%.1f", duration))ms")
        }
    }
    
    // MARK: - Statistics Computation
    
    private func updateAverageQueryTime() {
        guard !queryDurations.isEmpty else {
            averageQueryTime = 0
            return
        }
        averageQueryTime = queryDurations.reduce(0, +) / Double(queryDurations.count)
    }
    
    private func updateAveragePrefetchTime() {
        guard !prefetchDurations.isEmpty else {
            averagePrefetchTime = 0
            return
        }
        averagePrefetchTime = prefetchDurations.reduce(0, +) / Double(prefetchDurations.count)
    }
    
    var metadataCacheHitRate: Double {
        let total = metadataCacheHits + metadataCacheMisses
        return total > 0 ? Double(metadataCacheHits) / Double(total) : 0
    }
    
    var sessionCacheHitRate: Double {
        let total = sessionCacheHits + sessionCacheMisses
        return total > 0 ? Double(sessionCacheHits) / Double(total) : 0
    }
    
    var overallCacheHitRate: Double {
        let total = totalHits + totalMisses
        return total > 0 ? Double(totalHits) / Double(total) : 0
    }
    
    // MARK: - Reporting
    
    func logStatistics() {
        logger.info("""
        📊 Cache Metrics:
        - Metadata Hit Rate: \(String(format: "%.1f", metadataCacheHitRate * 100))%
        - Session Hit Rate: \(String(format: "%.1f", sessionCacheHitRate * 100))%
        - Overall Hit Rate: \(String(format: "%.1f", overallCacheHitRate * 100))%
        - Avg Query Time: \(String(format: "%.1f", averageQueryTime))ms
        - Avg Prefetch Time: \(String(format: "%.1f", averagePrefetchTime))ms
        """)
    }
    
    func reset() {
        metadataCacheHits = 0
        metadataCacheMisses = 0
        sessionCacheHits = 0
        sessionCacheMisses = 0
        queryDurations.removeAll()
        prefetchDurations.removeAll()
        
        totalHits = 0
        totalMisses = 0
        averageQueryTime = 0
        averagePrefetchTime = 0
    }
}
