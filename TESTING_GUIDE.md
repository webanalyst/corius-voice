# 🧪 Guía de Ejecución de Tests

## ⚡ Quick Start

### 1. Ejecutar Todos los Tests
```bash
cd /Users/marius/Proyectos/personal/corius-voice
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice
```

**Salida esperada:**
```
Test Suite 'All Tests' started at ...
Test Suite 'ViewModelTests' started ...
  ✅ WorkspaceViewModelTests (15 tests)
  ✅ SimplePageViewModelTests (16 tests)
  ✅ KanbanBoardViewModelTests (13 tests)
Test Suite 'IntegrationTests' started ...
  ✅ WorkspaceIntegrationTests (9 tests)
  ✅ PerformanceIntegrationTests (3 tests)

Test Suite 'All Tests' passed (59 tests, 0 failures)
```

### 2. Ejecutar Tests Específicos

#### Solo ViewModels
```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceViewModelTests
```

#### Solo Integración
```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceIntegrationTests
```

#### Solo Hardening de storage (Sprint 1)
```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceStorageHardeningTests
```

### 3. Con Code Coverage
```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -enableCodeCoverage YES
```

---

## 📊 Test Descriptions

### Unit Tests: WorkspaceViewModel (15 tests)

```
✅ testInitializesWithEmptyState
   Verifica que el ViewModel se inicializa vacío

✅ testCreateNewItem
   Crea item y verifica que se agregó al storage

✅ testCreateNewItemWithParent
   Crea item hijo verificando parentID

✅ testDeleteItem
   Elimina item y verifica que se quitó

✅ testDeleteItemClearsSelection
   Elimina item seleccionado y limpia selectedItemID

✅ testToggleFavorite
   Toggle de favorito on/off

✅ testArchiveItem
   Archiva item y verifica isArchived

✅ testArchiveItemClearsSelection
   Archiva item seleccionado

✅ testSelectItem
   Selecciona item

✅ testSearchFiltersItems
   Busca por texto y filtra resultados

✅ testClearSearch
   Limpia texto de búsqueda

✅ testSetCategory
   Filtra por categoría

✅ testFavoriteItems
   Computed property devuelve solo favoritos

✅ testRecentItems
   Computed property devuelve items recientes

✅ testHasItems
   Boolean para verificar si hay items
```

### Unit Tests: SimplePageViewModel (16 tests)

```
✅ testAddBlock
   Agrega bloque al final

✅ testDeleteBlock
   Elimina bloque específico

✅ testDeleteBlockClearsFocus
   Limpia focus cuando se elimina

✅ testUpdateBlock
   Actualiza contenido de bloque

✅ testMoveBlock
   Mueve bloque entre posiciones

✅ testDuplicateBlock
   Duplica bloque con mismo contenido

✅ testChangeBlockType
   Cambia tipo de bloque

✅ testUpdateTitle
   Actualiza título de página

✅ testUpdateNotes
   Actualiza notas de página

✅ testFocusBlock
   Setea focus en bloque específico

✅ testSaveRecordsUpdate
   Verifica que save() registre actualización

✅ testIsSaving
   Boolean para verificar si está guardando

✅ testBlockCount
   Cuenta total de bloques

✅ testBlockWithID
   Obtiene bloque por ID
```

### Unit Tests: KanbanBoardViewModel (13 tests)

```
✅ testAddColumn
   Agrega columna al kanban

✅ testUpdateColumn
   Actualiza nombre de columna

✅ testDeleteColumn
   Elimina columna

✅ testAddCard
   Agrega tarjeta a columna

✅ testMoveCard
   Mueve tarjeta entre columnas

✅ testDeleteCard
   Elimina tarjeta

✅ testDeleteCardClearsSelection
   Limpia selección al eliminar

✅ testToggleColumnExpansion
   Toggle expansión de columna

✅ testIsColumnExpanded
   Verifica si columna está expandida

✅ testCompletionPercentage
   Calcula % de tareas completadas

✅ testCardCount
   Cuenta tarjetas en columna

✅ testTotalCards
   Cuenta total de tarjetas
```

### Integration Tests (14 tests)

```
✅ testCreateEditSaveWorkflow
   End-to-end: crear → editar → guardar

✅ testKanbanDragDropWorkflow
   Drag & drop de tarjetas entre columnas

✅ testSearchAndFilterWorkflow
   Búsqueda + categoría filter

✅ testHierarchyWorkflow
   Crear parent/children, verificar relaciones

✅ testFavoritesWorkflow
   Marcar favoritos y verificar

✅ testMultiBlockPageWorkflow
   Crear página con múltiples bloques

✅ testArchiveWorkflow
   Archivar y verificar que no aparezca

✅ testConcurrentOperations
   100 items simultáneamente

✅ testCreateManyItemsPerformance
   Baseline: crear 1000 items

✅ testSearchPerformanceWith1000Items
   Baseline: búsqueda en 1000 items

✅ testFilteringPerformanceWith1000Items
   Baseline: filtering en 1000 items

✅ testBurstUpdatesPersistLatestState
   Burst writes y verificación de persistencia final

✅ testFlushIfPendingIsSafeWithoutWrites
   Flush sin cambios pendientes no rompe ni degrada estado
```

---

## 📉 Baseline Técnico Sprint 1

Comandos recomendados para baseline reproducible:

```bash
# Compilación del proyecto
xcodebuild build -project CoriusVoice.xcodeproj -scheme CoriusVoice

# Hardening de guardado
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceStorageHardeningTests

# Flujo crítico representativo
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceIntegrationTests/testCreateEditSaveWorkflow

# Baseline de métricas core (p95 save/search + voice error rate)
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceBaselineMetricsTests

# Regresion Sprint 2 (consistencia DB views + linked DB)
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/DatabaseViewQueryEngineTests
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceRegressionCoverageTests
```

Resultados iniciales versionados:
- `SPRINT_1_BASELINE_2026-02-06.md`

---

## 🔧 Modo Xcode

### 1. Abrir Xcode
```bash
open /Users/marius/Proyectos/personal/corius-voice/CoriusVoice.xcodeproj
```

### 2. Ejecutar Tests
- **⌘U**: Ejecutar todos los tests
- **⌘U** (con file seleccionado): Ejecutar tests del archivo
- **Control+⌘U**: Ejecutar test a la vez

### 3. Ver Resultados
- **⌘9**: Abrir Test Navigator
- Click en test para ir a código
- Red/Green circle indica pass/fail

---

## 📈 Performance Baselines

### Load Test: 1000 Items

```swift
let runner = LoadTestRunner()
await runner.runComprehensiveTest(itemCount: 1000)
```

**Salida esperada:**
```
🚀 Starting Comprehensive Load Test
==================================================

1️⃣  Creating items...
💾 Memory [before_create]: 45.2 MB
✅ Created 1000 items in 0.45s
   Average: 0.00045s per item
💾 Memory [after_create]: 52.1 MB

2️⃣  Testing search...
✅ Found 1000 results in 0.002s

3️⃣  Testing filters...
✅ Filtered 500 items in 0.001s
✅ Filtered 500 items in 0.001s

4️⃣  Testing updates...
✅ Updated 100 items in 0.05s
   Average: 0.0005s per item
💾 Memory [after_updates]: 52.3 MB

📈 Performance Report:
  createNewItem: avg=0.45ms, min=0.01ms, max=2.34ms, count=1000
  search(text:): avg=0.002ms, min=0.001ms, max=0.003ms, count=1
  items(ofType:): avg=0.001ms, min=0.001ms, max=0.002ms, count=2

💾 Memory Snapshots:
  before_create: 45.2 MB
  after_create: 52.1 MB
  after_updates: 52.3 MB
```

---

## 🐛 Debugging Tests

### Ver logs de un test
```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -testClass WorkspaceViewModelTests -testName testCreateNewItem \
  -verbose
```

### Pausar en breakpoint
1. Agregar `sleep(1)` en el test para dar tiempo
2. Click izquierdo en línea para crear breakpoint
3. Ejecutar test con ⌘U

### Mock debugging
```swift
mockStorage.resetCallTracking()
// ... ejecutar operación ...
print("Calls to updateItem:", mockStorage.getCallCount(for: "updateItem(_:)"))
print("All calls:", mockStorage.getCalls(for: "updateItem(_:)"))
```

---

## 📊 Coverage Report

### Generar report
```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -enableCodeCoverage YES \
  -derivedDataPath build/
```

### Abrir en Xcode
```bash
open build/Logs/Test/*.xcresult
```

O en Xcode:
1. Product → Scheme → Edit Scheme
2. Test → Code Coverage → Enable

---

## ✅ Checklist Pre-Deploy

- [ ] Todos los tests pasan (59/59)
- [ ] Code coverage > 80%
- [ ] Load test con 5000 items <2s
- [ ] Memory <100MB con 1000 items
- [ ] No AttributeGraph cycles
- [ ] 60 FPS consistent en scroll

---

## 🚨 Troubleshooting

### Tests no compilan
```
// Solución: Verificar que todos los archivos están en target
CoriusVoiceTests:
  - ViewModelTests.swift
  - IntegrationTests.swift
  - MockWorkspaceStorage.swift
  - LoadTestHelper.swift
```

### Tests timeout
```
// Aumentar timeout en test:
func testSomething() {
    let expectation = expectation(description: "desc")
    // ...
    waitForExpectations(timeout: 5)  // Default es 1
}
```

### Mock storage no persiste
```
// El mock es in-memory, los cambios se pierden entre tests
override func tearDown() {
    mockStorage.resetCallTracking()  // No resetea data
    super.tearDown()
}
```

---

## 📚 Recursos

- [ViewModelTests.swift](CoriusVoiceTests/ViewModelTests.swift) - Unit tests
- [IntegrationTests.swift](CoriusVoiceTests/IntegrationTests.swift) - Integration tests
- [MockWorkspaceStorage.swift](CoriusVoice/Testing/MockWorkspaceStorage.swift) - Mock
- [LoadTestHelper.swift](CoriusVoice/Testing/LoadTestHelper.swift) - Load testing

---

**Ready to test! 🚀**
