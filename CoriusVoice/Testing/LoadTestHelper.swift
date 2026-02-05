import Foundation
@testable import CoriusVoice

// MARK: - Load Test Generator

/// Generador de datos de prueba para load testing
@MainActor
class LoadTestDataGenerator {
    
    static let shared = LoadTestDataGenerator()
    
    // MARK: - Generation Methods
    
    func generateItems(count: Int) -> [WorkspaceItem] {
        var items: [WorkspaceItem] = []
        
        for i in 0..<count {
            let title = "Item \(i)"
            let type: WorkspaceItemType = [.page, .database, .task].randomElement() ?? .page
            
            var item = WorkspaceItem(title: title, itemType: type)
            
            // Random metadata
            if Bool.random() {
                item.isFavorite = true
            }
            
            
            items.append(item)
        }
        
        return items
    }
    
    func generateDatabases(count: Int) -> [Database] {
        var databases: [Database] = []
        
        for i in 0..<count {
            let viewType: DatabaseViewType = [.kanban, .table, .list].randomElement() ?? .kanban
            let db = Database(
                name: "Database \(i)",
                defaultView: viewType,
                kanbanColumns: KanbanColumn.defaultColumns
            )
            databases.append(db)
        }
        
        return databases
    }
    
    func generateHierarchy(parentCount: Int, childrenPerParent: Int) -> [WorkspaceItem] {
        var items: [WorkspaceItem] = []
        
        for p in 0..<parentCount {
            let parent = WorkspaceItem(title: "Parent \(p)", itemType: .page)
            items.append(parent)
            
            for c in 0..<childrenPerParent {
                let child = WorkspaceItem(
                    title: "Child \(p)-\(c)",
                    parentID: parent.id,
                    itemType: .page
                )
                items.append(child)
            }
        }
        
        return items
    }
    
    func generateItemsWithBlocks(count: Int, blocksPerItem: Int) -> [WorkspaceItem] {
        var items: [WorkspaceItem] = []
        
        for i in 0..<count {
            var item = WorkspaceItem(title: "Page \(i)", itemType: .page)
            
            for b in 0..<blocksPerItem {
                let blockType: BlockType = [
                    .paragraph, .heading1, .heading2,
                    .bulletList, .todo, .code
                ].randomElement() ?? .paragraph
                
                let block = Block(
                    id: UUID(),
                    type: blockType,
                    content: "Block \(b) content"
                )
                
                item.blocks.append(block)
            }
            
            items.append(item)
        }
        
        return items
    }
}

// MARK: - Load Test Runner

/// Ejecuta pruebas de carga y mide performance
@MainActor
class LoadTestRunner {
    
    let storage: any WorkspaceStorageProtocol
    private let profiler = PerformanceProfiler.shared
    
    init(storage: any WorkspaceStorageProtocol = WorkspaceStorageServiceOptimized.shared) {
        self.storage = storage
    }
    
    // MARK: - Test Scenarios
    
    func testCreateItems(count: Int) async {
        print("📊 Load Test: Creating \(count) items...")
        
        let items = LoadTestDataGenerator.shared.generateItems(count: count)
        
        let startTime = Date()
        for item in items {
            storage.addItem(item)
        }
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ Created \(count) items in \(String(format: "%.2f", duration))s")
        print("   Average: \(String(format: "%.4f", duration / Double(count)))s per item")
    }
    
    func testUpdateItems(count: Int) async {
        print("📊 Load Test: Updating \(count) items...")
        
        let items = storage.items.prefix(count)
        
        let startTime = Date()
        for item in items {
            var updated = item
            updated.title = updated.title + " [Updated]"
            storage.updateItem(updated)
        }
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ Updated \(count) items in \(String(format: "%.2f", duration))s")
        print("   Average: \(String(format: "%.4f", duration / Double(count)))s per item")
    }
    
    func testSearchPerformance(searchText: String) async {
        print("📊 Load Test: Searching for '\(searchText)'...")
        
        let startTime = Date()
        let results = storage.items.filter { item in
            item.title.localizedCaseInsensitiveContains(searchText)
        }
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ Found \(results.count) results in \(String(format: "%.4f", duration))s")
    }
    
    func testFilterByType(_ type: WorkspaceItemType) async {
        print("📊 Load Test: Filtering by type '\(type)'...")
        
        let startTime = Date()
        let results = storage.items(ofType: type)
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ Filtered \(results.count) items in \(String(format: "%.4f", duration))s")
    }
    
    func runComprehensiveTest(itemCount: Int = 1000) async {
        print("\n🚀 Starting Comprehensive Load Test")
        print("=" * 50)
        
        profiler.reset()
        
        // 1. Create items
        print("\n1️⃣  Creating items...")
        profiler.captureMemory(label: "before_create")
        
        await testCreateItems(count: itemCount)
        
        profiler.captureMemory(label: "after_create")
        
        // 2. Search performance
        print("\n2️⃣  Testing search...")
        await testSearchPerformance(searchText: "Item")
        
        // 3. Filter by type
        print("\n3️⃣  Testing filters...")
        await testFilterByType(.page)
        await testFilterByType(.database)
        
        // 4. Update items
        print("\n4️⃣  Testing updates...")
        await testUpdateItems(count: min(100, itemCount))
        
        profiler.captureMemory(label: "after_updates")
        
        // 5. Generate report
        print("\n📈 Performance Report:")
        print(profiler.generateReport())
    }
}

// MARK: - Memory Analyzer

/// Analiza el uso de memoria durante pruebas
@MainActor
class MemoryAnalyzer {
    
    static let shared = MemoryAnalyzer()
    
    private var snapshots: [(label: String, memory: UInt64, timestamp: Date)] = []
    
    func captureSnapshot(label: String) {
        let memory = getMemoryUsage()
        snapshots.append((label, memory, Date()))
        print("💾 Memory [\(label)]: \(formatBytes(memory))")
    }
    
    func generateReport() -> String {
        var report = "\n💾 Memory Report\n"
        report += "=" * 50 + "\n\n"
        
        for (i, snapshot) in snapshots.enumerated() {
            report += "\(i+1). \(snapshot.label): \(formatBytes(snapshot.memory))\n"
            
            if i > 0 {
                let delta = Int64(snapshot.memory) - Int64(snapshots[i-1].memory)
                let deltaStr = delta > 0 ? "+\(formatBytes(UInt64(delta)))" : "-\(formatBytes(UInt64(-delta)))"
                report += "   Change: \(deltaStr)\n"
            }
        }
        
        return report
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size)/4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        
        guard kerr == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .decimal
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func reset() {
        snapshots.removeAll()
    }
}

// MARK: - Helper Extension

extension String {
    static func * (string: String, count: Int) -> String {
        return String(repeating: string, count: count)
    }
}
