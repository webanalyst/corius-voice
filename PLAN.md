# Corius Voice — Roadmap (Notion-like)

## Fuente activa

La planificacion activa del producto esta en:

- `PLAN_NOTION_CORIUS_2026.md`

Backlog operativo inmediato:

- `SPRINT_1_BACKLOG_2026-02-05.md`
- `SPRINT_2_BACKLOG_2026-02-06.md`
- `SPRINT_3_BACKLOG_2026-02-06.md`
- `SPRINT_4_BACKLOG_2026-02-06.md`
- `SPRINT_5_BACKLOG_2026-02-06.md`

## Legacy roadmap (completado)

## Fase 1: Editor Unificado (prioridad máxima)
- [x] Unificar editor principal en `PageView` (WorkspaceView → PageView).
- [x] Backlinks navegables desde el editor.
- [x] Unificar renderizado de íconos (SF Symbols + emoji fallback).
- [x] Convertir `SimplePageView` en wrapper de compatibilidad.
- [x] Auto‑guardado debounced en el editor.
- [x] Guardado forzado al cerrar la app.

## Fase 2: Texto Enriquecido (inline formatting)
- [x] Persistencia RTFD en `Block.richTextData`.
- [x] `RichTextEditorView` con `NSTextView`.
- [x] Integración en bloques principales (paragraph, heading, lists, todo, toggle, quote, callout).
- [x] Barra de formato contextual.
- [x] Barra flotante sobre selección.
- [x] Highlight y strikethrough.
- [x] UI de link inline con popover.

## Fase 3: Bases de Datos Avanzadas
- [x] Editor completo de propiedades.
- [x] Tabla editable estilo Notion.
- [x] Filtros, sorts y vistas guardadas.
- [x] Relations + rollups + fórmulas (MVP).

## Fase 4: Búsqueda Total
- [x] Indexar contenido de bloques y propiedades.
- [x] Búsqueda por tags/propiedades.

## Fase 5: Adjuntos
- [x] Imágenes/archivos locales persistentes.
- [x] Previews en bloques.

## Fase 6: Persistencia Robusta y preparada para iOS
- [x] Guardado seguro (debounce + force save).
- [x] Migración a SwiftData/SQLite (preparar para iOS).

## Fase 7: Vistas de Bases de Datos
- [x] Vistas List/Calendar/Gallery operativas.
- [x] Vistas guardadas con filtros/sorts por vista.
- [x] Selector de propiedad de fecha para Calendar.
