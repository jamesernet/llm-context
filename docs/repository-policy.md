# Repository policy

`.llmctx.json` is a small committed declaration of repository intent. It does not contain machine paths, identities, credentials, or client secrets.

## Schema

```json
{
  "schemaVersion": 1,
  "profile": "personal",
  "branchPolicy": "remind",
  "protectedBranches": ["main", "master"]
}
```

All fields except `schemaVersion` are optional. Profiles are `personal` or `client`. Branch policies are `off`, `remind`, `ask`, or `deny`. `protectedBranches` must be a non-empty array of non-empty strings.

## Resolution

Values resolve in this order:

1. repository-local `git config llmctx.*` values;
2. committed `.llmctx.json` values;
3. global `git config --global llmctx.*` values where supported;
4. built-in defaults.

The built-in profile is `personal`. Its branch policy is `remind`. A committed `client` profile changes that default to `deny`. Protected branches default to `main master`.

Inspect the effective value and its source with:

```sh
bin/llmctx explain profile
bin/llmctx explain branchPolicy
bin/llmctx explain protectedBranches
```

## Adoption

Run `bin/llmctx repo diff /path/to/repo`. It checks policy resolution, canonical `AGENTS.md`, the Claude import, the briefs convention, and Git-hook state. It does not create or edit anything.

Statuses are:

- `OK`: matches the resolved standard;
- `OVERRIDE`: an intentional repository-local Git override;
- `MISSING`: a required convention is absent;
- `CONFLICT`: policy is invalid;
- `STALE`: an installed managed component differs from this release;
- `UNKNOWN`: another hook framework or foreign component owns the seam.

`MISSING`, `CONFLICT`, and `STALE` make the command non-compliant. `OVERRIDE` and `UNKNOWN` are reported without pretending the tool owns an external framework.
