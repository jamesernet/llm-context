---
name: implement
description: "Implement a piece of work based on a PRD or set of issues."
disable-model-invocation: true
---

Implement the work described by the user in the PRD or issues.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Before review, check the work against the verification criteria the issue or PRD gave you. State each criterion and the evidence that it is met — a test name, a command's output, a file path — not a claim that it is met. Where a criterion cannot be verified as stated, say so rather than reinterpreting it into something that passes.

Unmet or unverifiable criteria go on the ticket, not into the commit message.

Once done, use /code-review to review the work.

Commit your work to the current branch.
