# Plan Maestro Notion-like para Corius Voice (2026)

Este documento es la referencia operativa para evolucionar Corius Voice hacia un workspace tipo Notion, priorizando la ventaja de voz/IA ya existente.

## 1. Objetivo

Construir un producto Notion-like centrado en reuniones y ejecución de trabajo:

1. Capturar reuniones con voz.
2. Convertirlas en conocimiento estructurado.
3. Convertir ese conocimiento en tareas y seguimiento.
4. Potenciar búsqueda y automatización con IA.

## 2. Estado actual (base real del repo)

Implementado y usable:

- Editor de bloques con rich text y guardado robusto.
- Tipos de bloque amplios (texto, listas, callouts, embeds, tabla, columnas, meeting blocks).
- Bases de datos con vistas `kanban`, `table`, `list`, `calendar`, `gallery`.
- Filtros, sorts, vistas guardadas, linked database.
- Propiedades avanzadas: `relation`, `rollup`, `formula`, `status`, `priority`.
- Búsqueda indexada y caché.
- Plantillas y adjuntos.
- Pipeline de sesiones: transcripción, resumen, extracción de acciones, integración en workspace.
- Comandos de voz para crear/mover/completar tareas y crear páginas.

Gaps principales frente a Notion 2026:

- Enterprise Search cross-app (Slack/Drive/GitHub/Jira/etc.).
- Agent más capaz con automatizaciones por trigger/horario.
- Colaboración multiusuario robusta con permisos granulares.
- Integraciones de calendario/correo de nivel producto.
- Controles enterprise (SSO/SCIM/audit avanzados).

## 3. Principios de priorización

1. Potenciar primero el diferencial de Corius Voice: reuniones + voz + ejecución.
2. Entregar valor visible por sprint, evitando iniciativas largas sin impacto.
3. Hacer una integración externa por vez.
4. Endurecer calidad y métricas antes de escalar alcance enterprise.

## 4. Roadmap por fases (16 semanas)

## Fase A (Semanas 1-3) - Product Core Hardening

Objetivo:
- Cerrar fricción en flujos existentes de workspace y reuniones.

Entregables:
- Unificación UX de linked databases y vistas guardadas.
- Mejora de robustez de autosave, recuperación y migraciones.
- Comandos de voz con mejor parsing y desambiguación de entidades.
- QA de regresión en flujos: crear/editar/mover/buscar/archivar.

Definition of Done:
- Cero pérdida de datos en pruebas de estrés de guardado.
- Latencia de acciones CRUD percibida como instantánea en uso normal.
- Pruebas automatizadas para los flujos críticos del workspace.

KPIs:
- Crash-free sessions > 99.5%.
- Tiempo medio de guardado efectivo < 150 ms.
- Error rate en comandos de voz críticos < 10%.

## Fase B (Semanas 4-7) - AI Meeting OS (diferencial)

Objetivo:
- Convertir reuniones en sistema operativo de ejecución.

Entregables:
- Pipeline estable `session -> meeting note -> action items -> tracking`.
- Extracción de tareas con owner, prioridad y fecha sugerida.
- Vista consolidada de acciones por reunión, persona y estado.
- Enlaces bidireccionales sesión/reunión/acción con navegación clara.

Definition of Done:
- Flujo completo funcional sin pasos manuales técnicos.
- Corrección manual mínima tras extracción automática.
- Cobertura de tests para extracción y sincronización de acciones.

KPIs:
- Precision de extracción de action items >= 70% (benchmark interno).
- Tiempo de procesamiento post-reunión <= 30 s en sesiones estándar.
- % de reuniones que terminan con acciones trackeadas >= 60%.

## Fase C (Semanas 8-11) - Agent + Search

Objetivo:
- Dar salto en productividad con IA operativa sobre el workspace.

Entregables:
- Agent v1 para operaciones: crear/editar/resumir/actualizar estados.
- Búsqueda semántica local en páginas, bloques y sesiones con citaciones.
- Primer conector externo en producción (recomendado: Google Drive o Slack).
- Modo Research básico para respuesta con fuentes internas + conector activo.

Definition of Done:
- Respuestas con referencias verificables.
- Acciones del agent con confirmación y rollback seguro.
- Telemetría de calidad para prompts, latencia y errores.

KPIs:
- Tiempo de respuesta de consultas comunes < 3 s.
- Tasa de éxito de acciones del agent >= 90%.
- Al menos 1 integración externa estable con uso real.

## Fase D (Semanas 12-16) - Collaboration + Integrations

Objetivo:
- Completar capacidades estructurales para escalar uso en equipo.

Entregables:
- Modelo de permisos por workspace/page/database (`owner/editor/viewer`).
- Comentarios y menciones en páginas con historial.
- Integraciones v2 (GitHub/Jira/Calendar) en alcance acotado y seguro.
- Base de auditoría de acciones sensibles.

Definition of Done:
- Permisos respetados en lectura/escritura/acciones IA.
- Comentarios y menciones funcionales de punta a punta.
- Integraciones v2 con fallback claro ante errores externos.

KPIs:
- Incidentes de permisos: 0 en QA.
- Adopción de colaboración (comentarios/menciones) en uso interno.
- Error rate de sincronización de integraciones < 5%.

## 5. Plan por sprints (8 sprints, 2 semanas)

## Sprint 1

Foco:
- Hardening de storage y autosave.

Backlog:
- Pruebas de estrés de escritura concurrente.
- Validación de recuperación tras cierre inesperado.
- Métricas de guardado y latencia.

## Sprint 2

Foco:
- UX de DB views y linked DB.

Backlog:
- Refinar editor de filtros/sorts/vistas guardadas.
- Mejorar consistencia de UI entre vistas.
- Tests de regresión de vistas y propiedades.

## Sprint 3

Foco:
- Comandos de voz v2.

Backlog:
- Entity resolution para tareas/columnas/páginas.
- Confirmaciones en acciones de alto impacto.
- Métricas de éxito y fallos por intención.

## Sprint 4

Foco:
- Meeting OS v1 completo.

Backlog:
- End-to-end de extracción de acciones.
- Asignación sugerida de owner/due date/priority.
- Vista de seguimiento de acciones.

## Sprint 5

Foco:
- Agent v1 (operaciones internas).

Backlog:
- Catálogo de acciones seguras del agent.
- Confirmación/rollback y trazabilidad de cambios.
- Tests de regresión de acciones automatizadas.

## Sprint 6

Foco:
- Search semántico + citaciones.

Backlog:
- Índice combinado de contenido estructurado y transcripciones.
- Ranking semántico + lexical fallback.
- UI de resultados con evidencia/citas.

## Sprint 7

Foco:
- Integración externa v1 (1 conector).

Backlog:
- Arquitectura de conectores y sync jobs.
- Pull incremental con control de permisos.
- Búsqueda federada con resultados externos.

## Sprint 8

Foco:
- Permisos + colaboración + cierre de release.

Backlog:
- ACL básica por workspace/page/database.
- Comentarios/menciones y auditoría mínima.
- Hardening final y checklist de lanzamiento.

## 6. Matriz de prioridades

- P0 (imprescindible):
- Meeting OS end-to-end.
- Agent v1 interno.
- Search semántico con citas.
- 1 integración externa estable.

- P1 (alta):
- Permisos básicos + comentarios/menciones.
- Integraciones v2.

- P2 (posterior):
- Automatizaciones avanzadas por triggers/horarios.
- Capacidades enterprise completas (SSO/SCIM/retención avanzada).
- Mail client y funcionalidades equivalentes a Notion Mail.

## 7. Riesgos y mitigaciones

- Riesgo: aumento de complejidad en IA y acciones automáticas.
- Mitigación: action catalog limitado, confirmaciones y rollback.

- Riesgo: calidad variable en extracción de tareas.
- Mitigación: evaluación offline con dataset interno y bucle de feedback.

- Riesgo: deuda técnica por integraciones múltiples.
- Mitigación: framework de conectores con contrato único y un conector por fase.

- Riesgo: regressions en workspace por cambios transversales.
- Mitigación: suite de tests por flujos críticos + canary interno.

## 8. Métricas de seguimiento

- Producto:
- % reuniones con acciones ejecutables generadas.
- % tareas completadas provenientes de reuniones.
- Retención semanal de usuarios activos en workspace.

- Técnica:
- Crash-free rate.
- p95 latencia de guardado, búsqueda y acciones IA.
- Error rate de integraciones y sync.

- Calidad IA:
- Precision/recall de extracción de action items.
- Tasa de corrección manual post-IA.
- Tasa de aceptación de propuestas del agent.

## 9. Próxima ejecución inmediata (siguiente sesión)

Orden recomendado:

1. Implementar Sprint 1 backlog completo.
2. Ejecutar benchmark base y guardar métricas iniciales.
3. Abrir Sprint 2 con mejoras de vistas de DB.

---

Ultima actualización: 2026-02-05
Archivo de referencia principal para planificación: `PLAN_NOTION_CORIUS_2026.md`
