# Skills

Personal, in-development skill set. Each skill is a flat directory with a `SKILL.md`
(Claude Code does **not** discover nested category folders), so the grouping below is
organizational only.

**Workflow:** these live in the `llm-context` repo (version-controlled) and are symlinked
into `~/.claude/skills/<name>/`, so they load in every project and edits here take effect
immediately — no copy step. A project-local skill of the same name shadows the global one.

`/name` = user-invocable. "auto" = can also self-trigger from the description's trigger phrases
(skills marked `disable-model-invocation: true` are user-invoked only).

## requirements
| skill | invoke | what it does |
|---|---|---|
| [to-prd](to-prd/) | `/to-prd` | turn the current conversation into a PRD on the issue tracker |
| [to-issues](to-issues/) | `/to-issues` | break a plan/PRD into independently-grabbable vertical-slice issues |
| [interview-me](interview-me/) | `/interview-me` · auto | relentless plan interview; "with docs" variant records ADRs + glossary via domain-modeling |

## engineering
| skill | invoke | what it does |
|---|---|---|
| [improve-codebase-architecture](improve-codebase-architecture/) | `/improve-codebase-architecture` | scan for deepening opportunities → HTML report → grill the chosen one |
| [implement](implement/) | `/implement` | implement work from a PRD or set of issues |
| [diagnosing-bugs](diagnosing-bugs/) | `/diagnosing-bugs` · auto | diagnosis loop for hard bugs and perf regressions |

## domain-modeling
| skill | invoke | what it does |
|---|---|---|
| [domain-modeling](domain-modeling/) | `/domain-modeling` · auto | build/sharpen the domain model; supporting [ADR-FORMAT](domain-modeling/ADR-FORMAT.md), [CONTEXT-FORMAT](domain-modeling/CONTEXT-FORMAT.md) |

## tdd
| skill | invoke | what it does |
|---|---|---|
| [tdd](tdd/) | `/tdd` · auto | red-green-refactor; supporting [tests](tdd/tests.md), [mocking](tdd/mocking.md), [refactoring](tdd/refactoring.md) |

## agent-handoff
| skill | invoke | what it does |
|---|---|---|
| [handoff](handoff/) | `/handoff` | compact the conversation into a handoff doc for another agent |
| [grab](grab/) | `/grab` | issue → worktree → brief → implement, one motion; built for parallel sessions |

## dependencies (pulled to close the graph)
These are referenced by the skills above; imported so the set is self-contained.
| skill | invoke | needed by |
|---|---|---|
| [codebase-design](codebase-design/) | auto | improve-codebase-architecture, tdd (module/seam/depth vocabulary) |
| [setup-skills](setup-skills/) | `/setup-skills` | to-prd, to-issues, triage (per-project tracker + label config) |
| [triage](triage/) | `/triage` · auto | front-end of the intake→triage→prd→issues pipeline |

_`review` was dropped 2026-07 — `implement` uses the built-in `/code-review`; it lives in git history if ever needed._

## payments & fintech (mine — not upstream)
| skill | invoke | scope |
|---|---|---|
| [money-modeling](money-modeling/) | `/money-modeling` · auto | minor units, decimals, currency, rounding, allocation, FX |
| [payment-flow-review](payment-flow-review/) | `/payment-flow-review` · auto | auth/capture/settle/refund states, idempotency, webhooks, reconciliation |
| [ledger-and-reconciliation](ledger-and-reconciliation/) | `/ledger-and-reconciliation` · auto | double-entry, immutability, balance derivation, settlement matching, breaks |
| [tech-due-diligence](tech-due-diligence/) | `/tech-due-diligence` | architecture/team/risk/compliance diligence pass (investor · M&A · situation review) |

## security & compliance (mine — not upstream)
| skill | invoke | scope |
|---|---|---|
| [threat-model](threat-model/) | `/threat-model` · auto | DFD, trust boundaries, STRIDE, ranked mitigations |
| [data-privacy-review](data-privacy-review/) | `/data-privacy-review` · auto | PII inventory, retention/deletion, DSAR, residency, processors |
| [pci-dss-scoping](pci-dss-scoping/) | `/pci-dss-scoping` | card-data flow mapping, CDE shrinking, SAQ selection |
| [kyc-aml-review](kyc-aml-review/) | `/kyc-aml-review` | IDV, screening, risk rating, monitoring, SAR workflow |

## Attribution
Seeded verbatim from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT,
© 2026 Matt Pocock). Full notice in [LICENSE.upstream](LICENSE.upstream). These are
starting points — adapt into your own voice/structure as you go.
