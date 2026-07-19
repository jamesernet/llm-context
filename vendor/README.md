# vendor/

Third-party skills, vendored so the setup is reproducible. Not authored here
— don't edit in place; update wholesale with `bin/update-vendor.sh <tag-or-commit>`.
The machine-readable full commit and content hash live in `vendor.lock.json`.

Installed into `~/.claude/skills/` and `~/.codex/skills/` by
`bin/install-skills.sh`, same as `skills/`.

## Contents

| skill set | source | pinned commit |
|---|---|---|
| agents-sdk, cloudflare, cloudflare-email-service, cloudflare-one, cloudflare-one-migrations, durable-objects, sandbox-sdk, turnstile-spin, web-perf, workers-best-practices, wrangler | [cloudflare/skills](https://github.com/cloudflare/skills) `skills/` | `27ce0c0e159225caa7ed30ebefd4107aa6c52497` |
