# Sprint 2 Backlog (2026-02-06)

Referencia maestra:
- `PLAN_NOTION_CORIUS_2026.md`

Objetivo del sprint:
- Unificar UX y comportamiento de DB views y linked DB (filtros, sorts y vistas guardadas).

Duracion sugerida:
- 2 semanas

## 1. Alcance comprometido

- Consistencia funcional de filtros/sorts entre vistas de base de datos y embeds linked DB.
- Persistencia robusta de configuracion de vista activa en linked database embeds.
- Regresion automatizada para escenarios de views + propiedades.

## 2. Historias y tareas tecnicas por archivo

## Historia A - Motor de consulta unificado para DB views

Resultado esperado:
- Mismo resultado de filtros/sorts sin importar si se ejecuta en vista principal o linked DB.

Archivos foco:
- `CoriusVoice/Services/RelationService.swift`
- `CoriusVoice/Views/Workspace/Kanban/KanbanBoardView.swift`

Tareas:
- Centralizar aplicacion de `ViewFilter` y `ViewSort` en `DatabaseViewQueryEngine`.
- Mantener soporte de `propertyId` y fallback por nombre legacy.
- Resolver propiedades derivadas (`rollup`, `formula`, `created*`) con el mismo criterio en todos los puntos.

Criterios de aceptacion:
- Filtros/sorts producen orden y subset equivalentes entre Kanban y linked DB.
- Cambios de nombre de propiedad no rompen filtros/sorts si hay `propertyId`.

## Historia B - Linked DB embed robusto para vistas guardadas

Resultado esperado:
- El embed conserva vista activa y evita estado inconsistente al cambiar tipo de vista.

Archivos foco:
- `CoriusVoice/Views/Workspace/BlockEditor/BlockRowView.swift`

Tareas:
- Soportar `viewID` para seleccionar una vista guardada especifica dentro del embed.
- Validar que `viewID` corresponda al `viewType` activo.
- Persistir metadata de relacion con `relationPropertyID` ademas de nombre para evitar drift en renames.

Criterios de aceptacion:
- `viewID` y `viewType` persisten tras reload.
- Si `viewID` no corresponde al tipo actual, se usa fallback seguro.
- Filtro por relacion sigue funcionando tras renombre de propiedad relacionada.

## Historia C - Regresion de views y propiedades

Resultado esperado:
- Flujos de vistas guardadas cubiertos por tests estables y deterministas.

Archivos foco:
- `CoriusVoiceTests/IntegrationTests.swift`

Tareas:
- Cubrir filtro/sort con `propertyId` cuando `propertyName` queda obsoleto.
- Cubrir persistencia de metadata `viewID` en bloques `databaseEmbed`.
- Mantener prueba de workflow core para validar que cambios de Sprint 2 no rompen flujo base.

Criterios de aceptacion:
- `DatabaseViewQueryEngineTests` en verde con escenarios de nombre obsoleto.
- `WorkspaceRegressionCoverageTests` en verde con persistencia de linked DB.
- `WorkspaceIntegrationTests/testCreateEditSaveWorkflow` en verde.

## 3. No alcance del sprint

- Integraciones externas y busqueda federada.
- Permisos multiusuario y colaboracion avanzada.
- Agent autonomo con rollback transaccional.

## 4. Riesgos y mitigacion del sprint

- Riesgo: divergencia silenciosa entre vistas por logica duplicada.
- Mitigacion: unificar motor de consulta y cubrirlo con pruebas por `propertyId`.

- Riesgo: metadata de linked DB inconsistente tras cambios de vista.
- Mitigacion: persistir `viewID` y validar compatibilidad por tipo.

## 5. Estado inicial de ejecucion (2026-02-06)

- [x] Motor de consulta unificado aplicado en Kanban y linked DB.
- [x] Persistencia y seleccion de `viewID` en linked DB embed.
- [x] Soporte de `relationPropertyID` en linked DB embed.
- [x] Tests de regresion para `propertyId` con `propertyName` obsoleto.
- [x] Test de persistencia de `viewID` tras reload.
- [x] Pulido UX visual de editores de filtros/sorts (copys y affordances).
- [x] Corrida completa de suite (`xcodebuild test` total) sin cancelaciones.
  Estado actual: corrida completa ejecutada en CLI con resultado verde.

## 6. Comandos de validacion usados

```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/DatabaseViewQueryEngineTests

xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceRegressionCoverageTests

xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceIntegrationTests/testCreateEditSaveWorkflow

xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice
```
