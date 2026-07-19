# Handoff & Briefs

Where cross-agent artifacts live in every repo, so any agent — Claude Code, Codex, or a human engineer — knows where to look on session start.

- **Agent briefs** (the unit of work distribution) are posted on the repo's issue tracker and mirrored as a working copy in `docs/briefs/`, one file per brief: `docs/briefs/<issue-id>-<slug>.md`.
- **Handoff docs** (session-to-session continuity) live in `docs/briefs/handoffs/`, named `<yyyy-mm-dd>-<slug>.md`. Delete a handoff once the next session has absorbed it.
- The **issue tracker is the source of truth** for briefs. Trackers vary by client — the repo's own CLAUDE.md/AGENTS.md says which one. If a file and the tracker disagree, the tracker wins; update the file.
- On session start in a repo, check `docs/briefs/` for active briefs and handoffs before asking what to work on.

## Routing work

Briefs are agent-agnostic; route by the work's shape, not by habit:

- **Claude Code** — default for implementation from a brief, refactors, reviews, and anything using the skill library (fintech/compliance reviews, triage→PRD→issues pipeline).
- **Codex** — alternate implementer; use for parallel grabs alongside Claude sessions or as a second opinion on the same brief. Same briefs, same conventions, prose rules only (no hooks inside the tool — git hooks still apply).
- **Human engineer** — anything requiring judgment the brief can't encode: ambiguous product calls, credentials/infra access agents shouldn't hold, irreversible migrations. Hand over the brief itself, not a chat log.
- **Mid-flight handoff** (any direction): write a handoff doc, update the brief's status on the tracker, stop. The next session resumes from `docs/briefs/`, not from memory.
