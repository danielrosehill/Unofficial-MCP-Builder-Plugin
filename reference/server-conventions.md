# House style for an unofficial MCP server

Conventions the skills in this plugin generate against. Deviate where the API
demands it; say so in the README when you do.

## Stack

- **TypeScript**, ESM, targeting Node 20+.
- **`@modelcontextprotocol/sdk`** — the official SDK. Don't hand-roll the
  protocol.
- **zod** for input schemas, converted to JSON Schema for the tool definitions.
  One source of truth for validation and documentation.
- **stdio transport by default**, streamable HTTP as an option behind a flag.
  SSE is deprecated; don't generate it.
- No heavyweight HTTP client. `fetch` is in Node 20.

## Layout

```
src/
  index.ts          # entrypoint: transport wiring, server construction
  config.ts         # env parsing, fails fast with a clear message
  client.ts         # thin typed HTTP client: auth, retry, timeout, errors
  errors.ts         # upstream error → useful message
  tools/
    widgets.ts      # one module per resource, exporting definition + handler
    reports.ts
  types.ts
api-surface.yaml    # the verified surface — committed, kept current
docs/upstream/      # raw fetched vendor docs, dated
```

## Tool design

The endpoint list is not the tool list. Every tool description is loaded into
every conversation's context; the surface is a budget, not a catalogue.

- **One tool per resource with an `action` enum.** `widgets(action, ...)` beats
  `list_widgets` / `get_widget` / `create_widget` / …. A 40-endpoint API should
  land at 5–12 tools.
- **Model the user's intent.** If the common request takes three calls, that's
  one tool making three calls internally.
- **Descriptions are the interface.** Say when to use it, what comes back, and
  what it costs. Write for an agent that cannot read the API docs. Put
  parameter detail in the schema, not the description.
- **Shape the output.** Select fields, cap page sizes, paginate. A tool that
  returns 40k tokens of raw JSON is broken in practice even when it's correct.
- **Mark destructive actions** in the description and require explicit
  confirmation before executing.
- **Fail informatively.** "Acme returned 403 `insufficient_scope`: this key
  lacks `widgets:write`. Regenerate it with that scope." — not a stack trace,
  not a raw body.

## Client

- Auth from the environment only. Never a constructor argument that could be
  logged, never a default, never a file.
- Timeout on every request (30s is a sane default).
- One bounded retry on 429 and 5xx with exponential backoff, honouring
  `Retry-After`. No unbounded retry loops.
- Never log the key, headers containing it, or a request URL with it in a query
  param. If the API takes the key as a query param, redact it explicitly in
  every error path.

## Naming and honesty

- npm package: `<vendor>-mcp` or scoped `@yourscope/<vendor>-mcp`. Do not
  publish under a name that implies the vendor owns it, and do not squat a
  vendor's scope.
- README says **unofficial** and **unaffiliated** in the first paragraph, names
  the API version it was verified against, and links `api-surface.yaml`.
- Respect the vendor's terms of service and rate limits. An unofficial client
  that hammers an API gets the API's key policy tightened for everyone.

## Testing

- Unit tests against recorded, redacted fixtures — no key needed, runs in CI.
- Live verification is `smoke-test-mcp`'s job and stays out of CI.
- Fixtures are redacted at capture time, not before commit. Identifiers,
  emails, tokens, and anything personal get replaced at the point of writing
  the file.
