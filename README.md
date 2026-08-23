# llm-context

Portable, versioned defaults for how my coding agents work across machines and repositories.

This repository is the source of truth for global behavior, communication style, portable Claude safety settings, shared skills, third-party skill pins, Git safety hooks, and intentionally public brand context. Project-specific instructions remain in each project. Personal permissions, machine-specific identities, credentials, and application setup remain in the workstation repository.

## What this solves

- The same core rules reach Claude Code and Codex without maintaining two independent copies.
- A new machine can install a known release and verify its state.
- Repositories can declare a small committed policy while retaining local overrides.
- Shared skills are installed as versioned copies, so moving or deleting this checkout does not break them.
- Local drift is visible through deterministic commands rather than agent interpretation.
- Public content publication is separate from local agent installation.

The boundary is deliberate: `llm-context` owns portable agent behavior; a project owns its local context; `workstation` owns machine setup and private values.

## Quick start

Prerequisites are Git, Bash, jq, and either `shasum` or `sha256sum`. macOS and Linux are supported.

```sh
git clone https://github.com/jamesernet/llm-context.git
cd llm-context
./install.sh
bin/llmctx doctor
```

Installation generates the global adapters, merges the managed Claude settings, installs versioned skill copies for Claude and Codex, and installs this repository's Git hooks. It does not publish website content or initialize other repositories.

For normal workstation automation, check out an intentional `vMAJOR.MINOR.PATCH` tag before running `install.sh`; do not track a floating `main`.

## Daily commands

```sh
bin/llmctx version [--json]
bin/llmctx install
bin/llmctx doctor [--json|--quiet]
bin/llmctx repo diff [repo] [--json]
bin/llmctx explain <profile|branchPolicy|protectedBranches> [repo]
bin/llmctx skills install [--dev] [--bundle <name>]
bin/llmctx vendor check
bin/llmctx publish sync [--check]
```

Use `doctor` for machine-level state. Use `repo diff` inside a project to compare that repository with the standard. Both are read-only and return non-zero when required attention is found. JSON output is intended for workstation automation.

`skills install` uses managed copies by default. `--dev` is an explicit development mode that links directly to this checkout so skill edits take effect immediately.

`--bundle` narrows what lands in `~/.claude/skills` to a named group from [`skills/bundles.conf`](skills/bundles.conf) — `core`, `website`, `webapp`, `platform`, `fintech`, `cloudflare`, or several comma-separated. The default is `all`, so existing installs are unchanged.

Narrowing here is the only thing that makes skill selection real. A project's own `.claude/skills/` is **additive** and cannot hide a globally installed skill, so until the global set is reduced every project sees everything. The choice persists in `git config --global llmctx.skillBundle`; without that, the next `llmctx install` would silently widen it back to `all`. `llmctx doctor` reports the active bundle, so "absent on purpose" stays distinguishable from "install went wrong".

An unknown bundle name is refused and changes nothing — resolving it to the empty set would prune every installed skill over one missing letter.

## Data flow

```text
global/ ───────────────> ~/.claude/CLAUDE.md
       └───────────────> ~/.codex/AGENTS.md
claude/settings.json ──> ~/.claude/settings.json (portable keys merged)
skills/ + vendor/ ─────> ~/.claude/skills/ and ~/.codex/skills/
brand/ ── explicit ────> existing publication repositories
```

`AGENTS.md` is the canonical project instruction file. A project's `CLAUDE.md` should import it with `@AGENTS.md`, avoiding two drifting project rule sets.

Generated global adapters and portable managed settings are never edited as their source. Change files here, rebuild with `llmctx install`, and verify with `llmctx doctor`. Settings that identify private tools or grant personal permissions belong in a private machine configuration; the merge preserves keys this repository does not declare.

## Repository policy

Projects may commit `.llmctx.json`:

```json
{
  "schemaVersion": 1,
  "profile": "client",
  "protectedBranches": ["main", "stage"]
}
```

Resolution order is repository-local Git config, committed policy, global Git config, then built-in defaults. A `client` profile defaults to `deny`; `personal` defaults to `remind`. Local overrides stay local:

```sh
git config llmctx.branchPolicy off
bin/llmctx explain branchPolicy
```

There is intentionally no repository-init command. `llmctx repo diff` reports missing conventions and exact remediation without modifying an external repository. See [repository policy](docs/repository-policy.md) for the schema, precedence, statuses, and adoption workflow.

## Skills and provenance

Owned skills live in `skills/`; third-party skills live in `vendor/`. Every installed copy contains `.llmctx-managed.json` with its source path, release or revision, and content hash. The installer updates or prunes only marked copies and known development links. An unrelated real directory is preserved as a conflict.

`vendor.lock.json` records the full upstream commit, selected skills, and deterministic content digest. Vendor updates require an explicit tag or commit:

```sh
bin/update-vendor.sh <tag-or-commit>
bin/llmctx vendor check
```

Floating `main`, `master`, and `HEAD` are rejected.

## Safe multi-agent work

Never build directly on `main` or `master`. A single session may use a feature branch in its checkout. Concurrent sessions should use one worktree per branch:

```sh
bin/worktree.sh new feature/example
bin/worktree.sh ls
bin/worktree.sh rm feature/example
```

Briefs live in a project's `docs/briefs/`; handoffs live in `docs/briefs/handoffs/`. The issue tracker remains the source of truth. Commits should be logically scoped, use a clear subject of at most 72 characters, and omit `Co-authored-by` trailers. Nothing pushes or opens a PR without an explicit request.

Once a local branch is proven merged into `main` or `stage`, an agent may remove its clean worktree and delete the merged local branch with the safe Git checks documented in the global guidelines. It never force-deletes or removes a remote branch as part of that cleanup.

## Publishing

Local installation never touches website repositories. Publication is explicit:

```sh
bin/llmctx publish sync
bin/llmctx publish sync --check
```

Normal sync skips consumer repositories that are not cloned and never creates repository roots. Check mode treats missing repositories and marker-block drift as failures. Content intended to remain private does not belong in `global/`, `brand/`, or any published target.

## Client profiles

`templates/client-profile.example.toml` is the canonical shape for describing a client engagement: identity, AWS SSO, enforcement level, collaboration etiquette, and AI/egress policy in one file.

**The pattern lives here; the instances live in `workstation`** (`config/clients/<slug>.toml`, private to that machine). Same split as everything else in this repo — llm-context owns the reusable form, the consuming repo owns the content.

Two ideas carry most of the value:

- **One enforcement dial.** `level = "low" | "standard" | "high"` expands into branch policy, signing, secret scanning and push policy, because that is how the decision is actually made — "this client has real auditors", not twelve independent switches. Explicit keys still override it.
- **An `[ai]` section.** `agents_allowed` and `allow_code_egress` record whether you are contractually permitted to run an agent against a client's code. That question has real consequences in regulated work, and nothing else on the machine encodes the answer.

Resolution order is preset → client → repo-local git config, mirroring git's own `includeIf` layering.

**Status: schema and documentation only — there is no generator.** The profile is currently a structured onboarding checklist. A generator should emit files (`config-<slug>`, `includeIf` entries, `.envrc`, AWS blocks) with a `--check` drift mode, exactly like `build-adapters.sh` — but it should be written against two real clients rather than an imagined schema, or it will grow fields nobody uses.

## Layout

```text
global/       portable behavioral, communication, and handoff rules
claude/       portable Claude safety settings
skills/       owned skills
vendor/       pinned third-party skills
brand/        intentionally public personal-brand context
bin/          stable CLI, installers, checks, hooks, and libraries
tests/        deterministic shell tests and portable runner
docs/         detailed operating references
```

## Development and releases

```sh
bin/lint-skills.sh
bin/check-vendor-lock.sh
tests/run.sh
pre-commit run --all-files
```

CI runs the portable suite on Ubuntu and macOS and the full quality hooks on Ubuntu. Release tags must match `vMAJOR.MINOR.PATCH` and point exactly at the tested commit. `llmctx version --json` exposes the tag, full revision, and dirty state for automation.

See [operations](docs/operations.md) for installation ownership, diagnostics, updates, publication, release steps, and recovery guidance.

## License

Original code, skills, and documentation are available under Apache-2.0.
Personal material under `brand/` is reserved, and third-party content retains
its upstream terms. See [LICENSING.md](LICENSING.md) for the exact boundary.
