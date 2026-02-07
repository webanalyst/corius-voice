# Sprint 3 Backlog (2026-02-06)

Referencia maestra:
- `PLAN_NOTION_CORIUS_2026.md`

Objetivo del sprint:
- Comandos de voz v2 con mejor resolucion de entidades, confirmaciones seguras y telemetria accionable.

Duracion sugerida:
- 2 semanas

## 1. Alcance comprometido

- Mejorar entity resolution en comandos de voz para tareas, columnas y paginas.
- Exigir confirmacion en acciones ambiguas o de alto impacto.
- Estandarizar telemetria por intent para medir tasa de exito/fallo.

## 2. Historias y tareas tecnicas por archivo

## Historia A - Entity resolution robusto

Resultado esperado:
- El sistema selecciona entidades con una estrategia de score consistente y segura.

Archivos foco:
- `CoriusVoice/Services/WorkspaceVoiceCommandsService.swift`

Tareas:
- Consolidar scoring por coincidencia exacta/prefijo/contiene/tokens.
- Aplicar resolucion por score a apertura de paginas (`openPage`).
- Marcar ambiguedad cuando la diferencia de score sea minima.

Criterios de aceptacion:
- `openPage` no abre paginas por accidente con contexto vacio.
- Consultas ambiguas piden confirmacion en lugar de ejecutar directo.

## Historia B - Confirmaciones en acciones sensibles

Resultado esperado:
- No se ejecutan acciones de riesgo cuando hay ambiguedad o falta de certeza.

Archivos foco:
- `CoriusVoice/Services/WorkspaceVoiceCommandsService.swift`
- `CoriusVoiceTests/IntegrationTests.swift`

Tareas:
- Mantener confirmacion para `deleteTask`.
- Exigir confirmacion en `moveTask` ambiguo.
- Exigir confirmacion en `completeTask` ambiguo.
- Exigir confirmacion en `openPage` ambiguo.

Criterios de aceptacion:
- Flujo `comando ambiguo -> confirmacion -> si/no` estable y testeado.

## Historia C - Telemetria por intent

Resultado esperado:
- Los eventos de voz permiten medir error rate por intencion real.

Archivos foco:
- `CoriusVoice/Services/WorkspaceVoiceCommandsService.swift`
- `CoriusVoice/Services/WorkspaceStorageServiceOptimized.swift`
- `CoriusVoiceTests/IntegrationTests.swift`

Tareas:
- Emitir `intent` canonico (ej. `deleteTask`) en lugar de regex raw.
- Registrar eventos de exito/fallo y razon.
- Exponer lectura acotada de metricas recientes para verificacion automatizada.

Criterios de aceptacion:
- Tests verifican intent canonico y razon de fallo en comandos con confirmacion.

## 3. Estado de ejecucion (2026-02-06)

- [x] `openPage` ahora valida contexto vacio y usa resolucion por score.
- [x] Confirmacion agregada para `openPage` ambiguo.
- [x] Confirmacion agregada para `completeTask` ambiguo.
- [x] Telemetria usa intent canonico (`metricKey`) en success/failure/rejected.
- [x] API de lectura `recentMetricEvents(limit:)` para validacion en tests.
- [x] Tests nuevos de voz para ambiguedad, confirmacion y telemetria.
- [x] Suite completa (`xcodebuild test`) en verde tras cambios.

## 4. Comandos de validacion usados

```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceVoiceCommandsServiceTests

xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice
```
