import Foundation
import os.log

// MARK: - Generic Lazy Loading Service

/// Generic lazy loading service for any Identifiable type
/// Provides paginated loading with prefetch and LRU caching
@MainActor
class LazyLoadingService<T: Identifiable & Hashable>: ObservableObject {
    
    // MARK: - Configuration
    
    let pageSize: Int
    let preloadThreshold: Int
    let cacheCapacity: Int
    
    // MARK: - State
    
    @Published private(set) var currentPage = 0
    @Published private(set) var hasMorePages = true
    @Published private(set) var isLoading = false
    @Published private(set) var items: [T] = []
    
    // MARK: - Cache
    
    private var loadedItems: Set<T.ID> = []
    private var lruCache: LRUCache<T.ID, T>
    
    // MARK: - Logger
    
    private let logger = Logger(subsystem: "com.corius.voice", category: "LazyLoading")
    
    // MARK: - Initialization
    
    init(pageSize: Int = 50, preloadThreshold: Int = 10, cacheCapacity: Int = 50) {
        self.pageSize = pageSize
        self.preloadThreshold = preloadThreshold
        self.cacheCapacity = cacheCapacity
        self.lruCache = LRUCache(capacity: cacheCapacity)
    }
    
    // MARK: - Public API
    
    /// Initialize with all items (client-side filtering)
    func initialize(with allItems: [T]) {
        self.items = []
        self.currentPage = 0
        self.hasMorePages = allItems.count > pageSize
        self.loadedItems.removeAll()
        self.lruCache.clear()
        
        loadFirstPage(from: allItems)
    }
    
    /// Load first page of items
    func loadFirstPage(from allItems: [T]) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        currentPage = 0
        items = []
        loadedItems.removeAll()
        
        let endIndex = min(pageSize, allItems.count)
        let firstPage = Array(allItems[0..<endIndex])
        
        items = firstPage
        currentPage = 1
        hasMorePages = allItems.count > pageSize
        
        // Cache loaded items
        for item in firstPage {
            loadedItems.insert(item.id)
            lruCache.put(item.id, value: item)
        }
        
        let loadTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger.debug("📄 First page loaded: \(items.count) items in \(String(format: "%.1f", loadTime))ms")
    }
    
    /// Load next page of items
    func loadNextPage(from allItems: [T]) -> [T] {
        guard hasMorePages, !isLoading else { return [] }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        isLoading = true
        defer { 
            isLoading = false
            
            let loadTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger.debug("📄 Page \(currentPage) loaded: \(items.count) total items in \(String(format: "%.1f", loadTime))ms")
        }
        
        let startIndex = items.count
        let endIndex = min(startIndex + pageSize, allItems.count)
        
        guard startIndex < allItems.count else {
            hasMorePages = false
            return []
        }
        
        let newItems = Array(allItems[startIndex..<endIndex])
        items.append(contentsOf: newItems)
        
        // Cache newly loaded items
        for item in newItems {
            loadedItems.insert(item.id)
            lruCache.put(item.id, value: item)
        }
        
        hasMorePages = endIndex < allItems.count
        currentPage += 1
        
        return newItems
    }
    
    /// Check if more items should be loaded based on current index
    func shouldLoadMore(currentIndex: Int) -> Bool {
        return currentIndex >= items.count - preloadThreshold && hasMorePages && !isLoading
    }
    
    /// Refresh with new items (e.g., after filter change)
    func refresh(with newItems: [T]) {
        initialize(with: newItems)
    }
    
    /// Reset pagination state
    func reset() {
        items = []
        currentPage = 0
        hasMorePages = true
        loadedItems.removeAll()
        lruCache.clear()
    }
    
    /// Get cached item by ID
    func getCached(id: T.ID) -> T? {
        return lruCache.get(id)
    }
    
    /// Cache an item manually
    func cache(_ item: T) {
        lruCache.put(item.id, value: item)
    }
    
    /// Get cache statistics
    var cacheStats: (hitRate: Double, size: Int) {
        return (lruCache.hitRate, lruCache.count)
    }
}

// MARK: - Speaker Lazy Loading Service

/// Specialized lazy loading for speakers
typealias SpeakerLazyLoadingService = LazyLoadingService<KnownSpeaker>

// MARK: - SessionMatch Lazy Loading Service

/// Specialized lazy loading for search results
typealias SearchResultsLazyLoadingService = LazyLoadingService<SessionMatch>

// MARK: - Paginated Query Service

/// Servicio para ejecutar queries paginadas
struct PaginatedQuery {
    
    let pageSize: Int
    let items: [WorkspaceItem]
    
    var totalPages: Int {
        (items.count + pageSize - 1) / pageSize
    }
    
    func itemsForPage(_ pageNumber: Int) -> [WorkspaceItem] {
        let startIndex = (pageNumber - 1) * pageSize
        let endIndex = min(startIndex + pageSize, items.count)
        
        guard startIndex < items.count else { return [] }
        
        return Array(items[startIndex..<endIndex])
    }
    
    func allPages() -> [[WorkspaceItem]] {
        var pages: [[WorkspaceItem]] = []
        for page in 1...totalPages {
            pages.append(itemsForPage(page))
        }
        return pages
    }
}

// MARK: - Batch Operations

/// Servicio para operaciones en batch de items
@MainActor
class BatchOperationService {
    
    let batchSize: Int
    
    init(batchSize: Int = 100) {
        self.batchSize = batchSize
    }
    
    func batchUpdate(
        items: [WorkspaceItem],
        storage: any WorkspaceStorageProtocol,
        transform: (WorkspaceItem) -> WorkspaceItem,
        progress: ((Int, Int) -> Void)? = nil
    ) async {
        var processed = 0
        
        for i in stride(from: 0, to: items.count, by: batchSize) {
            let endIndex = min(i + batchSize, items.count)
            let batch = items[i..<endIndex]
            
            // Procesar batch
            for item in batch {
                let updated = transform(item)
                await MainActor.run {
                    storage.updateItem(updated)
                }
            }
            
            processed += batch.count
            progress?(processed, items.count)
            
            // Yield para no bloquear UI
            try? await Task.sleep(nanoseconds: 1_000_000) // 0.001 segundos
        }
    }
    
    func batchDelete(
        ids: [UUID],
        storage: any WorkspaceStorageProtocol,
        progress: ((Int, Int) -> Void)? = nil
    ) async {
        var processed = 0
        
        for i in stride(from: 0, to: ids.count, by: batchSize) {
            let endIndex = min(i + batchSize, ids.count)
            let batch = ids[i..<endIndex]
            
            for id in batch {
                await MainActor.run {
                    storage.deleteItem(id)
                }
            }
            
            processed += batch.count
            progress?(processed, ids.count)
            
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

// MARK: - Virtual Scrolling Helper

/// Helper para virtual scrolling (solo renderizar items visibles)
struct VirtualScrollingHelper {
    
    let itemHeight: CGFloat
    let containerHeight: CGFloat
    let overscanRows: Int // Cuántas rows renderizar fuera de pantalla
    
    func visibleRange(for contentOffset: CGFloat) -> Range<Int> {
        let firstVisibleRow = Int(max(0, contentOffset / itemHeight))
        let visibleRows = Int(ceil(containerHeight / itemHeight))
        
        let start = max(0, firstVisibleRow - overscanRows)
        let end = start + visibleRows + (overscanRows * 2)
        
        return start..<end
    }
    
    func shouldRenderItem(at index: Int, for contentOffset: CGFloat) -> Bool {
        let range = visibleRange(for: contentOffset)
        return range.contains(index)
    }
}
