# Briefs

GitHub Issues are the source of truth for units of work. This directory holds
agent-agnostic working copies so another session can resume without relying on
chat history.

- Store briefs as `<issue-id>-<slug>.md`.
- Store temporary handoffs as `handoffs/<yyyy-mm-dd>-<slug>.md`.
- Keep status and acceptance criteria synchronized with the issue.
- If a file and its issue disagree, the issue wins and the file should be
  corrected.
- Delete a handoff after the receiving session has absorbed it.
- Do not place credentials, client secrets, or private machine values here.
