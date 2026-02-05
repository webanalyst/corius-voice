import Foundation

// MARK: - Lazy Loading Service

/// Servicio para lazy loading de items en listas
/// Carga items en paginas para no sobrecargar la UI
@MainActor
class LazyLoadingService: ObservableObject {
    
    // MARK: - Configuration
    
    let pageSize: Int
    let preloadThreshold: Int // Cuántos items antes del final para precargar
    
    // MARK: - State
    
    @Published private(set) var currentPage = 0
    @Published private(set) var hasMorePages = true
    @Published private(set) var isLoading = false
    
    private var allItems: [WorkspaceItem] = []
    @Published private(set) var items: [WorkspaceItem] = []
    
    // MARK: - Initialization
    
    init(pageSize: Int = 50, preloadThreshold: Int = 10) {
        self.pageSize = pageSize
        self.preloadThreshold = preloadThreshold
    }
    
    // MARK: - Public API
    
    func initialize(with items: [WorkspaceItem]) {
        self.allItems = items
        self.currentPage = 0
        self.hasMorePages = items.count > pageSize
        self.items = []
        loadFirstPage()
    }
    
    func loadFirstPage() {
        currentPage = 0
        items = []
        let range = 0..<min(pageSize, allItems.count)
        items.append(contentsOf: allItems[range])
        currentPage = 1
        hasMorePages = allItems.count > pageSize
    }
    
    func loadNextPage() -> [WorkspaceItem] {
        guard hasMorePages, !isLoading else { return [] }
        
        isLoading = true
        defer { isLoading = false }
        
        let startIndex = items.count
        let endIndex = min(startIndex + pageSize, allItems.count)
        
        guard startIndex < allItems.count else {
            hasMorePages = false
            return []
        }
        
        let newItems = Array(allItems[startIndex..<endIndex])
        items.append(contentsOf: newItems)
        
        hasMorePages = endIndex < allItems.count
        currentPage += 1
        
        return newItems
    }
    
    func shouldLoadMore(currentIndex: Int) -> Bool {
        return currentIndex >= items.count - preloadThreshold && hasMorePages && !isLoading
    }
    
    func refresh(with newItems: [WorkspaceItem]) {
        initialize(with: newItems)
    }
}

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
