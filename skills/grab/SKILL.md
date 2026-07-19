---
name: grab
description: Grab a unit of work — take an issue or brief, create the branch and worktree, write the working brief to docs/briefs/, and start implementing. User-invoked as /grab <issue-or-brief>.
disable-model-invocation: true
---

# Grab

Connects the pipeline's pieces into one motion: issue → worktree → brief →
implementation. Designed so several grabs can run in parallel, one agent
session per worktree.

## Procedure

1. **Resolve the work item.** `/grab <issue-id>` fetches the issue from the
   repo's tracker (which tracker: see the repo's CLAUDE.md/AGENTS.md and
   [setup-skills](../setup-skills/)). `/grab` with no argument: list open,
   unassigned, ready-labeled issues and ask which one. If pointed at an
   existing `docs/briefs/` file, use it directly.

2. **Qualify before building.** Read the issue. If it lacks what
   [AGENT-BRIEF](../triage/AGENT-BRIEF.md) requires — context, constraints,
   verification criteria — apply [interview-me](../interview-me/) to close the gaps
   (asking the user or the issue thread) rather than guessing. A brief
   without "done means…" is not grabbable yet.

3. **Create the workspace.** Branch name `feature/<issue-id>-<slug>` (or
   `fix/…`), then create the worktree with
   `llm-context/bin/worktree.sh new <branch>`. All subsequent work happens
   inside that worktree, leaving the main checkout free for parallel grabs.

4. **Write the working brief** to `docs/briefs/<issue-id>-<slug>.md` in the
   worktree, per the AGENT-BRIEF format, and note on the tracker issue that
   it's been grabbed (assignee/label per repo convention).

5. **Implement** via [implement](../implement/), honoring the brief's
   verification criteria as the definition of done. On completion or when
   stopping mid-flight, write a handoff per [handoff](../handoff/) so any
   agent — or a human — can resume.

## Rules
- One grab = one branch = one worktree = one brief. No batching.
- Never grab onto main/master; the worktree step makes this structural.
- If the tracker and the brief file disagree, the tracker wins (see the
  global handoff-and-briefs conventions).

## Related
- [triage](../triage/) · [to-issues](../to-issues/) · [implement](../implement/) · [handoff](../handoff/)
