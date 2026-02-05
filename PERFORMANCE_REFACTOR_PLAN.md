# 🚀 Plan de Refactorización y Optimización de Performance - Corius Voice

## 📊 Análisis de Problemas Detectados

### 🔴 Críticos (Alto Impacto en Performance)

1. **Múltiples instancias de `@StateObject` para singletons**
   - **Problema**: 30+ vistas crean instancias nuevas de `WorkspaceStorageService.shared`
   - **Impacto**: Re-renderizado masivo, ciclos AttributeGraph
   - **Archivos afectados**: Todas las vistas de Workspace, Kanban, BlockEditor

2. **Publicación de arrays completos en `@Published`**
   - **Problema**: `@Published var items: [WorkspaceItem]` notifica cambios en TODO el array
   - **Impacto**: Re-renderizado de TODAS las vistas que observan items
   - **Archivos**: `WorkspaceStorageService.swift`

3. **Guardado síncrono en Main Thread**
   - **Problema**: Cada cambio dispara I/O en el hilo principal
   - **Impacto**: UI bloqueada, lag al escribir
   - **Archivos**: `WorkspaceStorageService`, `StorageService`

4. **Sin lazy loading en listas**
   - **Problema**: Todas las vistas cargan todos los items
   - **Impacto**: Memoria alta, scroll lento con muchos items

### 🟡 Moderados (Performance Mejorable)

5. **Búsquedas lineales O(n) en arrays**
   - **Problema**: `items.filter`, `items.first(where:)` en loops
   - **Impacto**: Lentitud con >100 items
   - **Solución**: Usar Dictionary indexados

6. **Debouncing inconsistente**
   - **Problema**: Algunos lugares usan debouncing, otros no
   - **Impacto**: Guardados excesivos

7. **Computaciones repetidas**
   - **Problema**: Computed properties se recalculan en cada render
   - **Solución**: Cachear resultados

### 🟢 Bajos (Mejoras Estructurales)

8. **Servicios sin protocols**
   - **Problema**: Dificulta testing y desacoplamiento
   - **Solución**: Crear protocols para cada servicio

9. **Falta de arquitectura clara**
   - **Problema**: Lógica mezclada en vistas
   - **Solución**: MVVM consistente

---

## 🎯 Plan de Ejecución (Priorizado)

### ✅ FASE 1: Fixes Críticos de Performance (30 min)

#### 1.1 Eliminar `@StateObject` duplicados
- [x] WorkspaceView y sub-vistas → `@ObservedObject`
- [ ] KanbanBoardView (7 instancias)
- [ ] BlockEditor/BlockRowView (2 instancias)
- [ ] RelationViews (5 instancias)
- [ ] Todas las demás vistas

#### 1.2 Optimizar `@Published` collections
```swift
// ❌ ANTES
@Published var items: [WorkspaceItem] = []

// ✅ DESPUÉS
private var _items: [UUID: WorkspaceItem] = [:]
var items: [WorkspaceItem] { Array(_items.values) }

// Métodos específicos que SÍ notifican
func itemDidChange(_ id: UUID)
func itemsDidChange(_ ids: Set<UUID>)
```

#### 1.3 Guardado asíncrono con debouncing
```swift
private var saveTask: Task<Void, Never>?
private let saveQueue = DispatchQueue(label: "storage.save", qos: .utility)

func saveDebounced() {
    saveTask?.cancel()
    saveTask = Task {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await saveToD disk()
    }
}
```

---

### ✅ FASE 2: Arquitectura y Estructura (45 min)

#### 2.1 Crear ViewModels dedicados
```
ViewModels/
  ├── WorkspaceViewModel.swift
  ├── SimplePageViewModel.swift
  ├── KanbanBoardViewModel.swift
  └── BlockEditorViewModel.swift
```

#### 2.2 Protocols para servicios
```swift
protocol WorkspaceStorageProtocol {
    func item(withID: UUID) -> WorkspaceItem?
    func updateItem(_ item: WorkspaceItem) async
    // ...
}

class WorkspaceStorageService: ObservableObject, WorkspaceStorageProtocol {
    // Implementación
}
```

#### 2.3 Dependency Injection
```swift
// ✅ Testeable, desacoplado
struct SimplePageView: View {
    @ObservedObject var viewModel: SimplePageViewModel
    
    init(item: WorkspaceItem, storage: WorkspaceStorageProtocol = WorkspaceStorageService.shared) {
        viewModel = SimplePageViewModel(item: item, storage: storage)
    }
}
```

---

### ✅ FASE 3: Optimizaciones Avanzadas (60 min)

#### 3.1 Indexación con Dictionary
```swift
class WorkspaceStorageService {
    private var itemsById: [UUID: WorkspaceItem] = [:]
    private var itemsByType: [WorkspaceItemType: Set<UUID>] = [:]
    private var itemsByParent: [UUID: Set<UUID>] = [:]
    
    func items(ofType type: WorkspaceItemType) -> [WorkspaceItem] {
        guard let ids = itemsByType[type] else { return [] }
        return ids.compactMap { itemsById[$0] }
    }
}
```

#### 3.2 Lazy Loading & Pagination
```swift
struct PaginatedList<T: Identifiable>: View {
    let items: [T]
    let pageSize: Int = 50
    @State private var loadedCount = 50
    
    var visibleItems: ArraySlice<T> {
        items.prefix(loadedCount)
    }
    
    var body: some View {
        List {
            ForEach(visibleItems) { item in
                // Row
            }
            
            if loadedCount < items.count {
                ProgressView()
                    .onAppear { loadedCount += pageSize }
            }
        }
    }
}
```

#### 3.3 Cacheo de computed properties
```swift
class WorkspaceStorageService {
    private var recentItemsCache: [WorkspaceItem]?
    private var favoriteItemsCache: [WorkspaceItem]?
    
    func invalidateCache() {
        recentItemsCache = nil
        favoriteItemsCache = nil
    }
    
    var recentItems: [WorkspaceItem] {
        if let cached = recentItemsCache { return cached }
        let items = computeRecentItems()
        recentItemsCache = items
        return items
    }
}
```

---

### ✅ FASE 4: Testing & Monitoreo (30 min)

#### 4.1 Performance Tests
```swift
func testItemLookupPerformance() {
    measure {
        for _ in 0..<1000 {
            _ = storage.item(withID: testID)
        }
    }
}
```

#### 4.2 Memory Profiling
- Instruments: Allocations
- Buscar leaks en closures
- Verificar retain cycles

#### 4.3 Logging selectivo
```swift
#if DEBUG
let perfLog = OSLog(subsystem: "com.corius", category: "performance")
os_signpost(.begin, log: perfLog, name: "SaveItems")
// operación
os_signpost(.end, log: perfLog, name: "SaveItems")
#endif
```

---

## 📈 Métricas de Éxito

| Métrica | Antes | Objetivo |
|---------|-------|----------|
| Tiempo de guardado | ~500ms | <50ms |
| FPS al escribir | 30-40 | 60 |
| Memoria (100 items) | ~150MB | <80MB |
| Tiempo búsqueda (1000 items) | O(n) | O(1) |
| AttributeGraph cycles | 50+ | 0 |
| "Publishing changes" warnings | 10+ | 0 |

---

## 🔧 Orden de Implementación

1. **Ahora mismo**: Fase 1.1 (fixes críticos `@StateObject`)
2. **Hoy**: Fase 1.2-1.3 (optimizar storage)
3. **Mañana**: Fase 2 (arquitectura)
4. **Esta semana**: Fase 3-4 (optimizaciones avanzadas)

---

## 🚨 Riesgos

- **Alto**: Cambios en WorkspaceStorageService pueden romper funcionalidad existente
- **Medio**: Migrar a ViewModels requiere cambios en muchas vistas
- **Bajo**: Optimizaciones de cacheo tienen poco riesgo

---

## ✅ Quick Wins (Para empezar AHORA)

1. Cambiar todos los `@StateObject private var storage` a `@ObservedObject`
2. Envolver guardados en `Task { await ... }`
3. Agregar debouncing a `SimplePageView`
4. Indexar items por ID en Dictionary

---

¿Comenzamos con la Fase 1.1? 🚀
