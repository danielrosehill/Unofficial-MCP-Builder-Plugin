# Publishing an unofficial MCP server to npm

Only when the user asks. Publishing is public and effectively irreversible —
unpublish windows are narrow and a name, once taken, stays taken.

## Naming

- `<vendor>-mcp`, or scoped `@yourscope/<vendor>-mcp`.
- **Do not** publish under the vendor's own scope or a name implying they
  maintain it. `@acme/mcp-server` is theirs; `acme-mcp` under your own scope is
  yours.
- Check availability *and* whether an existing package already does this before
  choosing.

## package.json

```jsonc
{
  "name": "@yourscope/acme-mcp",
  "version": "0.1.0",
  "description": "Unofficial MCP server for the Acme API. Not affiliated with Acme.",
  "type": "module",
  "bin": { "acme-mcp": "./dist/index.js" },
  "files": ["dist", "README.md", "LICENSE", "api-surface.yaml"],
  "engines": { "node": ">=20" },
  "keywords": ["mcp", "model-context-protocol", "acme", "unofficial"],
  "license": "MIT",
  "repository": { "type": "git", "url": "git+https://github.com/…" }
}
```

- `bin` matters — `npx @yourscope/acme-mcp` is how people will run it. The
  entrypoint needs a `#!/usr/bin/env node` shebang and the built file needs to
  be executable.
- `files` keeps the tarball to what's needed. Ship `api-surface.yaml`; it's the
  honest statement of what's verified.
- Start at `0.1.0`. An unofficial wrapper of an API you don't control has no
  business claiming 1.0 until it's been smoke-tested against real usage.

## Before publishing

- `npm pack --dry-run` and read the file list. Check for `.env`, fixtures with
  real data, and anything under `docs/upstream/` that shouldn't ship.
- Confirm no secret is in the tarball, git history, or the README's examples.
- README states unofficial and unaffiliated in the first paragraph, gives the
  install and client-config snippet, lists the tools, names the API version and
  verification date, and links `api-surface.yaml`.
- LICENSE present. MIT unless the user says otherwise.
- Smoke test passes.

## Publishing

```bash
npm publish --access public          # scoped packages default to restricted
```

Tell the user the exact command before running it, and confirm. For a scoped
private package, `--access restricted` (the default) — worth stating explicitly
so nobody publishes a private wrapper by accident.

## Versioning after publish

- **patch** — bug fix, no surface change.
- **minor** — new tool or new optional parameter.
- **major** — tool renamed or removed, parameter now required, output shape
  changed. Agents have prompts written against your tool names; renaming one is
  a breaking change even though nothing type-checks against it.

CHANGELOG entries name the upstream change, not just the code change —
"Acme moved `created` to `created_at` in the v2 widget response" is what a
future reader needs. `revalidate-api-surface` produces exactly this.

## Deprecating

If the vendor ships an official MCP, say so in the README, point at it, and
`npm deprecate` with a message naming the replacement. Leaving a redundant
unofficial server undeprecated on npm wastes other people's time.
