# targets

One file per hosting target a project can declare in `.llmctx.json`:

```json
"environment": { "target": "cloudflare-pages" }
```

A target is a directory listing, not a registry. Adding one is adding a file;
nothing enumerates them, so nothing rots when one is added. Same idiom as
`skills/bundles.conf` and project-scaffold's `templates/<kind>/files.conf`.

## Fields

Flat `key=value`, one per line, `#` comments. Every field is optional except
`description`. Lists are comma-separated with no spaces.

| key | meaning |
|---|---|
| `description` | One line. Shown by `llmctx env explain`. |
| `requires_env` | Environment variable names the target cannot deploy without. |
| `requires_cli` | Commands that must be on `PATH`. |
| `optional_cli` | Commands that help but are not required. |
| `optional_secrets` | Secret NAMES this kind of destination *may* need. Informational: shown by `llmctx env explain`, never checked. A project declares the ones it actually uses in its own `environment.secrets`, and only those are checked — a target cannot know whether a given Pages site uses Functions. |
| `check_files` | Files whose presence indicates the project really is this kind. |
| `skills` | Skill bundle this kind of project usually wants. |
| `onboard_hint` | The manual steps a human still performs. |
| `offboard_hint` | The reverse, including what must be revoked server-side. |

## What a target file must never contain

Account identifiers, profile names, vault names, URLs carrying a tenant, or any
credential. A target describes a *kind* of destination. Which account, which
profile and which vault are per-project and per-machine, and they live in the
project's own declaration and in workstation respectively.

## Adding one

Model it on a project that exists. `other.conf` carries hints only and is the
honest answer for a destination with one instance and no pattern yet — the same
reason `templates/client-profile.example.toml` still has no generator.
