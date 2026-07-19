# Domain Docs

How the engineering skills should consume this repo's domain documentation when
exploring the codebase. Skills read the pointers in the **Layout** section below —
they don't hardcode a file name — so this doc is the single place that describes
where domain knowledge lives.

## Layout

This repo uses **one** of the following. Keep the section that applies and delete
the others when `setup-skills` writes this file for a real repo.

### Single-context (most repos)

- **Vocabulary** — `CONTEXT.md` at the repo root (a glossary; see the `/domain-modeling` `CONTEXT-FORMAT.md`).
- **Decisions** — `docs/adr/`.

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

### Multi-context (presence of `CONTEXT-MAP.md` at the root)

- **Vocabulary** — `CONTEXT-MAP.md` at the root points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **Decisions** — `docs/adr/` (system-wide) plus `src/<context>/docs/adr/` (context-scoped).

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

### OKF (Open Knowledge Framework — `docs/knowledge/` with `okf_version` frontmatter)

The domain language is **not** a flat glossary. It lives in per-concept knowledge
docs and is indexed by an entity map. There is no `CONTEXT.md`.

- **Vocabulary** — `docs/knowledge/index.md` (the Knowledge Bundle entry point) and `docs/architecture/domain-model.md` (the conceptual entity map — every entity tagged with build status and linked to its authoritative source). The ubiquitous language lives inside the concept docs these index.
- **Decisions** — `docs/adr/` (an ADR index at `docs/adr/README.md` if present).
- **Principles** — `docs/architecture/principles.md` — architecture principles reconciled against as-built, each tagged **enforced / partial / aspirational**. Treat **enforced** principles like ADRs (below).
- **Test scenarios** — `docs/testing/scenario-matrix.md` — named scenarios mapped to the real test suite. Read it for coverage before adding tests; add new scenarios here and link the tests.

```
/
├── docs/
│   ├── knowledge/                     ← per-concept docs + index.md (the vocabulary)
│   │   ├── index.md
│   │   └── <area>/{index.md, <concept>.md}
│   ├── architecture/
│   │   ├── domain-model.md            ← conceptual entity map
│   │   └── principles.md              ← enforced/partial/aspirational principles
│   ├── testing/scenario-matrix.md
│   └── adr/{README.md, NNN-slug.md}
└── src/ (or app/)
```

Reference implementation of this layout:
the current repository.

## Before exploring, read these

- The **Vocabulary** source(s) for the layout above.
- The **Decisions** (`docs/adr/`) that touch the area you're about to work in.
- For OKF repos, the **Principles** doc and — when your work touches tests — the **Test scenarios** matrix.

If any of these files don't exist, **proceed silently**. Don't flag their absence;
don't suggest creating them upfront. The `/domain-modeling` skill (reached via
`/interview-me` (with docs) and `/improve-codebase-architecture`) creates them lazily when
terms or decisions actually get resolved.

## Use the domain vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a
hypothesis, a test name), use the term as the domain docs define it — the glossary
entry (`CONTEXT.md`) or the concept doc / entity name (`docs/knowledge/`,
`docs/architecture/domain-model.md`). Don't drift to synonyms the docs explicitly
avoid.

If the concept you need isn't in the domain docs yet, that's a signal — either
you're inventing language the project doesn't use (reconsider) or there's a real gap
(note it for `/domain-modeling`).

## Flag conflicts

If your output contradicts an existing **ADR**, surface it explicitly rather than
silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_

For OKF repos, do the same against an **enforced** principle in
`docs/architecture/principles.md`:

> _Contradicts principle #2 (ledger entries are append-only), which is enforced by
> a DB trigger — flagging rather than overriding._

Only flag *enforced* principles this way; *aspirational* ones are guidance, not
guardrails.
