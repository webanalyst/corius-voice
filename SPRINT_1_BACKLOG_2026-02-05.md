# Sprint 1 Backlog (2026-02-05)

Referencia maestra:
- `PLAN_NOTION_CORIUS_2026.md`

Objetivo del sprint:
- Endurecer Product Core (autosave, resiliencia de datos, comandos de voz v2, regresion critica).

Duracion sugerida:
- 2 semanas

## 1. Alcance comprometido

- Hardening de guardado y recuperacion.
- Robustez de comandos de voz para workspace.
- Baseline de metricas tecnicas del core.
- Suite de pruebas de regresion para flujos criticos.

## 2. Historias y tareas tecnicas por archivo

## Historia A - Autosave y recuperacion robusta

Resultado esperado:
- No perdida de datos en cierres inesperados o bursts de escritura.

Archivos foco:
- `CoriusVoice/Services/WorkspaceStorageServiceOptimized.swift`
- `CoriusVoice/CoriusVoiceApp.swift`
- `CoriusVoice/Services/SwiftDataService.swift`

Tareas:
- Revisar el pipeline de `saveDebounced` y `forceSave` para cubrir caso background/terminacion.
- Garantizar flush final al cerrar app sin bloquear UI.
- Agregar logs estructurados de guardado (inicio, exito, fallo, duracion).
- Definir politica de retry segura para errores transitorios de I/O.
- Agregar prueba de "burst updates" (muchos updates seguidos) y verificacion de persistencia final.

Criterios de aceptacion:
- Cambios realizados en menos de 500 ms de inactividad se persisten consistentemente.
- Cierre de app dispara persistencia final sin corrupcion.
- En test de burst, estado final coincide con ultimo update.

## Historia B - Comandos de voz v2 (parsing + desambiguacion)

Resultado esperado:
- Mayor tasa de acierto al crear/mover/completar tareas por voz.

Archivos foco:
- `CoriusVoice/Services/WorkspaceVoiceCommandsService.swift`
- `CoriusVoice/Services/WorkspaceStorageServiceOptimized.swift`
- `CoriusVoice/Views/Workspace/WorkspaceView.swift`

Tareas:
- Separar parseo de intencion y resolucion de entidades en helpers dedicados.
- Mejorar matching de tareas y columnas con estrategia por score (exacto > prefijo > contiene).
- Agregar confirmacion opcional para comandos destructivos (delete/move ambiguo).
- Registrar telemetria basica por comando (intent, exito/fallo, razon).
- Mejorar mensajes de error para guiar al usuario cuando falta contexto.

Criterios de aceptacion:
- Comandos criticos (`createTask`, `moveTask`, `completeTask`) ejecutan correctamente en casos comunes.
- En ambiguedad, no se ejecuta accion destructiva sin confirmacion.
- Existe log/telemetria util para medir tasa de exito.

## Historia C - Regresion critica de Workspace

Resultado esperado:
- Flujos principales protegidos por tests automatizados.

Archivos foco:
- `CoriusVoiceTests/ViewModelTests.swift`
- `CoriusVoiceTests/IntegrationTests.swift`
- `CoriusVoice/Testing/MockWorkspaceStorage.swift`

Tareas:
- Agregar tests para create/edit/archive/delete en paginas y tareas.
- Agregar tests para filtros/sorts/vistas guardadas minimas.
- Agregar test de integracion para flujo "session -> meeting note -> action items".
- Agregar test de regresion para linked database basico.
- Asegurar fixtures deterministas y pequenos.

Criterios de aceptacion:
- Tests nuevos pasan de forma estable localmente.
- Sin flakes observados en ejecuciones consecutivas.
- Cobertura aumenta en servicios tocados.

## Historia D - Baseline de metricas del core

Resultado esperado:
- Tener linea base para comparar mejoras del roadmap.

Archivos foco:
- `CoriusVoice/Services/PerformanceProfiler.swift`
- `CoriusVoice/Testing/LoadTestHelper.swift`
- `TESTING_GUIDE.md`

Tareas:
- Definir set minimo de metricas: p95 guardado, p95 busqueda, error rate comandos voz.
- Ejecutar benchmark inicial con dataset controlado.
- Guardar resultados en documento de referencia de sprint.
- Documentar como repetir benchmark de forma consistente.

Criterios de aceptacion:
- Baseline capturado y versionado en markdown.
- Comando/procedimiento reproducible en local.

## 3. No alcance del sprint

- Integraciones externas (Slack, Drive, GitHub, Jira).
- Permisos multiusuario y colaboracion avanzada.
- Agent autonomo por triggers/horario.

## 4. Riesgos y mitigacion del sprint

- Riesgo: cambios en persistencia introducen regressions silenciosas.
- Mitigacion: pruebas de burst + cierre inesperado + snapshot de estado.

- Riesgo: parser de voz incrementa falsos positivos.
- Mitigacion: estrategia de score + confirmacion en ambiguos/destructivos.

## 5. Checklist de salida del sprint

- [ ] Historias A-D completadas.
- [ ] Test suite relevante en verde.
- [ ] Baseline tecnico documentado.
- [ ] Sin regressions visibles en flujos core.

## 6. Comandos de validacion sugeridos

```bash
xcodebuild build -project CoriusVoice.xcodeproj -scheme CoriusVoice
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice -testClass IntegrationTests
```

## 7. Definicion de listo para Sprint 2

- Guardado y recuperacion estables.
- Comandos de voz core con error rate controlado.
- Baseline tecnico disponible para medir mejoras de Fase B.
