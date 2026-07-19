---
name: interview-me
description: Interview the user relentlessly about a plan or design. Use when the user wants to stress-test a plan before building, gather requirements, or uses "interview me" or any "grill" trigger phrases.
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Variant: with docs

When asked to grill "with docs" (or when decisions should outlive the
conversation), also apply [domain-modeling](../domain-modeling/) as we go:
record each resolved decision as an ADR and grow the glossary, per its
ADR-FORMAT and CONTEXT-FORMAT. Same interview, durable output.
