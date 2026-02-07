# Sprint 5 Backlog (2026-02-06)

Referencia maestra:
- `PLAN_NOTION_CORIUS_2026.md`

Objetivo del sprint:
- Entregar Agent v1 interno con acciones seguras sobre el workspace, confirmaciones, rollback y trazabilidad.

Duracion sugerida:
- 2 semanas

## 1. Alcance comprometido

- Catalogo de acciones del agent para operaciones internas (`create_task`, `move_task`, `delete_item`).
- Capa de seguridad con confirmacion obligatoria en acciones ambiguas o destructivas.
- Rollback del ultimo cambio exitoso y auditoria de acciones ejecutadas por IA.

## 2. Historias y tareas tecnicas por archivo

## Historia A - Tooling del agent en chat

Resultado esperado:
- El chat puede listar, ejecutar, confirmar, revertir y auditar acciones del workspace mediante herramientas tipadas.

Archivos foco:
- `CoriusVoice/Models/ChatMessage.swift`
- `CoriusVoice/Services/SpeakerChatService.swift`

Tareas:
- Agregar tools del agent: `list_workspace_actions`, `execute_workspace_action`, `confirm_workspace_action`, `rollback_workspace_action`, `get_workspace_action_audit`.
- Definir DTOs de argumentos para ejecucion, confirmacion y auditoria.
- Integrar dispatch de tools en `SpeakerChatService`.
- Actualizar instrucciones de sistema para reforzar confirmaciones y rollback antes de acciones de impacto.

Criterios de aceptacion:
- El modelo puede descubrir el catalogo de acciones y solicitar ejecucion por tool.
- Acciones ambiguas o destructivas no se ejecutan sin confirmacion.
- Las respuestas del chat incluyen estado claro (`success`, `requiresConfirmation`, `confirmationToken`, `message`).

## Historia B - Seguridad operacional: confirmacion, rollback y auditoria

Resultado esperado:
- Las acciones del agent son reversibles cuando aplica y dejan traza consultable.

Archivos foco:
- `CoriusVoice/Services/SpeakerChatService.swift`

Tareas:
- Implementar `WorkspaceAgentActionService` con catalogo interno y validaciones.
- Resolver tareas por `id` o `query` con estrategia de score y deteccion de ambiguedad.
- Exigir confirmacion para `delete_item` y para `move_task` ambiguo.
- Guardar snapshots para rollback en `create_task`, `move_task` y `delete_item`.
- Registrar auditoria con estados (`success`, `failed`, `pending`, `canceled`, `rolled_back`) y exponer lectura por limite.

Criterios de aceptacion:
- Existe flujo `pending -> confirm/reject -> executed/canceled` con token valido.
- `rollback_workspace_action` revierte el ultimo cambio exitoso cuando hay snapshot.
- `get_workspace_action_audit` devuelve historial util para trazabilidad.

## Historia C - Cobertura de regresion del agent

Resultado esperado:
- Los flujos criticos del agent quedan cubiertos con pruebas automatizadas reproducibles.

Archivos foco:
- `CoriusVoiceTests/IntegrationTests.swift`
- `CoriusVoice/Views/SpeakerChatView.swift`

Tareas:
- Agregar clase `WorkspaceAgentActionServiceTests` con casos de create+rollback, delete+confirm+rollback, move ambiguo+confirm+rollback y reject.
- Etiquetar herramientas nuevas en UI (`ToolCallIndicator`) para depuracion visual.
- Corregir firmas de tests con `throws` donde se usa `XCTUnwrap` con `try`.

Criterios de aceptacion:
- Suite de `WorkspaceAgentActionServiceTests` pasa en build limpio.
- Los cuatro casos verifican comportamiento funcional y de seguridad.

## 3. Estado de ejecucion (2026-02-06)

- [x] Tools del agent agregadas en `ChatMessage.swift` y expuestas en `ChatTool.allTools`.
- [x] Integracion en `SpeakerChatService` (prompt, routing de tools y ejecucion).
- [x] Servicio `WorkspaceAgentActionService` implementado con confirmacion, rollback y auditoria.
- [x] Etiquetas de tools nuevas en `SpeakerChatView`.
- [x] Tests `WorkspaceAgentActionServiceTests` agregados.
- [x] Corregidas firmas `throws` para evitar fallo de compilacion en build limpio.
- [x] Verificacion en clean run: 4/4 tests de `WorkspaceAgentActionServiceTests` en verde.

## 4. Comandos de validacion usados

```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceAgentActionServiceTests \
  -derivedDataPath /tmp/dd-agent-action-tests-20260206-1008 \
  -resultBundlePath /tmp/WorkspaceAgentActionServiceFresh2-20260206-1008.xcresult

xcrun xcresulttool get test-results summary \
  --path /tmp/WorkspaceAgentActionServiceFresh2-20260206-1008.xcresult

xcrun xcresulttool get test-results tests \
  --path /tmp/WorkspaceAgentActionServiceFresh2-20260206-1008.xcresult
```
