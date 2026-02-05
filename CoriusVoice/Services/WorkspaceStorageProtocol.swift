import Foundation

// MARK: - Workspace Storage Protocol

/// Protocolo para abstracción de almacenamiento de workspace
/// Permite testing, inyección de dependencias, y múltiples implementaciones
protocol WorkspaceStorageProtocol: AnyObject, ObservableObject {
    
    // MARK: - Published Properties
    var lastUpdate: Date { get }
    
    // MARK: - Queries (O(1) Lookups)
    
    /// Obtener database por ID
    func database(withID id: UUID) -> Database?
    
    /// Obtener item por ID
    func item(withID id: UUID) -> WorkspaceItem?
    
    /// Obtener todos los databases (sorted por fecha)
    var databases: [Database] { get }
    
    /// Obtener todos los items (sorted por fecha)
    var items: [WorkspaceItem] { get }
    
    /// Obtener items favoritos (no archivados)
    var favoriteItems: [WorkspaceItem] { get }
    
    /// Obtener items de un tipo específico
    func items(ofType type: WorkspaceItemType) -> [WorkspaceItem]
    
    /// Obtener items de una database específica
    func items(inDatabase databaseID: UUID) -> [WorkspaceItem]
    
    /// Obtener items hijos de un parent
    func items(withParent parentID: UUID?) -> [WorkspaceItem]
    
    /// Obtener items recientes
    func recentItems(limit: Int) -> [WorkspaceItem]
    
    // MARK: - Mutations
    
    /// Agregar nueva database
    func addDatabase(_ database: Database)
    
    /// Actualizar database existente
    func updateDatabase(_ database: Database)
    
    /// Eliminar database y archivar items
    func deleteDatabase(_ id: UUID)
    
    /// Agregar nuevo item
    func addItem(_ item: WorkspaceItem)
    
    /// Actualizar item existente
    func updateItem(_ item: WorkspaceItem)
    
    /// Eliminar item
    func deleteItem(_ id: UUID)
    
    // MARK: - Saving
    
    /// Forzar guardado inmediato
    func forceSave() async
}

// MARK: - Conformance

extension WorkspaceStorageServiceOptimized: WorkspaceStorageProtocol {
    // Todos los métodos ya están implementados
}
