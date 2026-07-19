# OKF Knowledge Format

The write path for repos that use the **OKF layout** (`docs/knowledge/` with
`okf_version` frontmatter — see `docs/agents/domain.md`). Use this instead of
`CONTEXT-FORMAT.md` in those repos. Unlike a flat `CONTEXT.md` glossary, OKF
concept docs are *how-it-works* documents — they carry tables, lifecycles, and key
fields, not just a one-line definition.

Reference implementation: a repository-local `docs/domain/` directory.

## Where knowledge lives

```
docs/knowledge/
├── index.md                 ← Knowledge Bundle: links every area + concept
└── <area>/                  ← e.g. ledger/, identity/, auth/
    ├── index.md             ← area index: links the concepts in this area
    └── <concept>.md         ← one concept per file
docs/architecture/
├── domain-model.md          ← conceptual entity map (build status + source links)
└── principles.md            ← enforced/partial/aspirational principles
```

## Concept doc frontmatter

Every knowledge doc starts with YAML frontmatter:

```md
---
type: Concept
title: Value Lot
description: One-sentence summary used to decide relevance when scanning the index.
tags: [ledger, value-lot, playthrough, adr-010]
timestamp: 2026-06-28T00:00:00Z
---

A value lot (`value_lots` table) wraps a segment of value with its provenance and
any restrictions attached to it. …
```

`type` vocabulary:

- **Concept** — a single domain concept (most files).
- **Index** — an area index (`<area>/index.md`).
- **Reference** — a map or catalog (e.g. `domain-model.md`, `principles.md`).
- **Knowledge Bundle** — the root `docs/knowledge/index.md`. Carries `okf_version`.

## Rules

- **New concept → new file.** Create `docs/knowledge/<area>/<slug>.md` with
  frontmatter, then add a link to it from the area `index.md` **and** the root
  `index.md`. Pick the area that already exists; only create a new area folder (with
  its own `index.md`) when no existing one fits.
- **Refining an existing term → edit the concept doc in place.** Don't add a second
  home for the same term. There is no flat glossary to also update.
- **Cite, don't duplicate.** Link related concepts, ADRs (`../../adr/NNN-slug.md`),
  and — where the schema is the source of truth — migrations. End a doc with a
  `# Citations` list when it references several. Don't re-paste column DDL that the
  migration owns.
- **Definitions belong to the concept; the map belongs to `domain-model.md`.** When
  a *new domain entity* appears, add a row to `docs/architecture/domain-model.md`
  (entity, build status, purpose, source link) as well as its concept doc.
- **Keep `type`/`title`/`description`/`tags`/`timestamp` present** on every file so
  the index and future scans stay reliable.

## What does NOT go here

Ephemeral decisions, scratch notes, and implementation TODOs. Knowledge docs
describe how the domain works; decisions and their rationale go in `docs/adr/`
(see `ADR-FORMAT.md`).
