---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save it to `docs/briefs/handoffs/<yyyy-mm-dd>-<slug>.md` in the current repo (create the directory if needed) — that's the fixed, tool-agnostic home any agent checks on session start. Delete the file once the next session has absorbed it. If there is no repo (a non-code session), fall back to the OS temporary directory.

This is for **session-to-session continuity** of work you're already carrying — not for distributing a unit of work to someone else, and not where requirements live. If you're handing a task to another agent or person to own, write an agent brief on the issue instead (see the `triage` skill's `AGENT-BRIEF.md`) and keep the durable requirements there. A handoff doc points at those artifacts; it does not replace them.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
