# Sprint 4 Backlog (2026-02-06)

Referencia maestra:
- `PLAN_NOTION_CORIUS_2026.md`

Objetivo del sprint:
- Completar Meeting OS v1 en el flujo `session -> meeting note -> action items -> tracking`.

Duracion sugerida:
- 2 semanas

## 1. Alcance comprometido

- End-to-end de extraccion y sincronizacion de action items.
- Asignacion sugerida de owner, due date y priority.
- Vista de seguimiento de acciones integrada en el embed de meeting note.

## 2. Historias y tareas tecnicas por archivo

## Historia A - Pipeline E2E meeting -> actions

Resultado esperado:
- El sistema crea/actualiza meeting notes y genera action items deduplicados con relaciones consistentes.

Archivos foco:
- `CoriusVoice/Services/SessionIntegrationService.swift`
- `CoriusVoiceTests/IntegrationTests.swift`

Tareas:
- Mantener `upsertMeetingNote`, `syncActions` y `reconcileMeetingGraph` idempotentes.
- Reforzar metadata de embed de acciones (databaseID, relation property, relation target).
- Cubrir regresion E2E con assertions de relaciones meeting/session.

Criterios de aceptacion:
- Sync repetido no duplica acciones.
- Meeting note conserva `Action Count` y `Actions` correctos.
- Cada action item queda relacionado a meeting note y session item.

## Historia B - Sugerencias de owner/due/priority

Resultado esperado:
- Las acciones extraidas incluyen valores sugeridos utiles desde el contenido de la sesion.

Archivos foco:
- `CoriusVoice/Services/SessionIntegrationService.swift`
- `CoriusVoice/Models/SessionSummary.swift`

Tareas:
- Sugerir owner desde `@assignee` o inferencia por speaker name.
- Resolver owner contra `SpeakerLibrary` cuando exista, con fallback textual.
- Sugerir due date por heuristicas (`hoy`, `mañana`, `next week`, weekday, fechas explicitas).
- Sugerir prioridad por señales de urgencia y cercania de vencimiento.

Criterios de aceptacion:
- Action items con `@Nombre` quedan con owner sugerido.
- Action items urgentes/fecha cercana elevan prioridad.
- Due date sugerida queda persistida y testeada.

## Historia C - Tracking view de acciones

Resultado esperado:
- La base `Meeting Actions` incluye vistas listas para seguimiento operativo.

Archivos foco:
- `CoriusVoice/Services/SessionIntegrationService.swift`
- `CoriusVoice/Models/Workspace/Database.swift`

Tareas:
- Crear/asegurar vistas guardadas `Action Tracker` y `Open Actions`.
- Configurar embed de acciones para usar `viewType` + `viewID` del tracking principal.
- Persistir `relationPropertyID` para robustez ante renombres.

Criterios de aceptacion:
- `Meeting Actions` contiene vistas de tracking tras bootstrap.
- El embed de meeting note apunta a `Action Tracker` por `viewID`.
- Filtro por relacion en embed se mantiene estable por `relationPropertyID`.

## 3. Estado de ejecucion (2026-02-06)

- [x] Heuristicas de owner/due/priority aplicadas en `applyActionProperties`.
- [x] Enriquecimiento de embeds con `viewType`, `viewID`, `relationPropertyID`.
- [x] Provision automatica de vistas `Action Tracker` y `Open Actions`.
- [x] Reforzada actualizacion de meeting notes existentes (`patchMeetingBlocks`).
- [x] Test E2E actualizado con checks de sugerencias y metadata de tracking.
- [x] Suite completa (`xcodebuild test`) en verde.

## 4. Comandos de validacion usados

```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceRegressionCoverageTests/testSessionMeetingActionsEndToEndAndDeduplicates

xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceRegressionCoverageTests

xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice
```
