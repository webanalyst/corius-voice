# Sprint 1 Baseline Técnico (2026-02-06)

Referencia de plan:
- `PLAN_NOTION_CORIUS_2026.md`
- `SPRINT_1_BACKLOG_2026-02-05.md`

## Scope medido

Métricas mínimas solicitadas para Sprint 1:
- p95 de guardado.
- p95 de búsqueda.
- error rate de comandos de voz.

## Entorno y comando reproducible

Comando ejecutado:

```bash
xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice \
  -only-testing:CoriusVoiceTests/WorkspaceBaselineMetricsTests
```

Resultado:
- `TEST SUCCEEDED` (3/3 tests)
- Fecha de ejecución: 2026-02-06

## Resultados baseline (inicial)

Valores extraídos de logs del test (`WorkspaceBaselineMetricsTests`):

1. Guardado (`testBaselineSaveP95`)
- `save_p50_ms = 1.53`
- `save_p95_ms = 2.17`

2. Búsqueda (`testBaselineSearchP95`)
- `search_p95_ms = 16.16`

3. Voz (`testBaselineVoiceCommandErrorRate`)
- `voice_error_rate_pct = 40.00`
- `voice_total = 5`

## Observaciones

- El p95 de guardado está muy por debajo del objetivo de fase (<150 ms).
- El p95 de búsqueda se mantiene bajo en dataset controlado de baseline local.
- El error rate de voz es alto para el mix de escenarios del benchmark (incluye casos forzados de fallo para calibración).

## Próximos ajustes recomendados para Sprint 2

1. Separar baseline de voz por `intent` para comparar `create/move/complete/delete` por canal.
2. Definir dos cortes de voz:
- `happy_path_error_rate`
- `mixed_scenarios_error_rate` (con fallos forzados).
3. Repetir baseline después de cambios de DB views/linked DB para detectar regresiones.
