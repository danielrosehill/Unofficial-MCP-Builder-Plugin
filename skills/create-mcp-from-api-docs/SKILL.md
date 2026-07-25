---
name: create-mcp-from-api-docs
description: Build an unofficial MCP server for a third-party API that doesn't ship one, starting from the vendor's API documentation and (optionally) a working API key used to verify the real surface before any code is written. Produces a publishable npm package plus a committed api-surface.yaml recording what was verified live versus taken on the docs' word. Use for "write an MCP for <service>", "there's no official MCP for X", "wrap this API as an MCP", "generate an MCP from these docs / this OpenAPI spec".
---

# Create an MCP server from a third party's API docs

The documentation is a starting hypothesis, not a specification. Where a key is
available, the API itself is the source of truth and the docs are a lead to be
checked. This skill front-loads that verification so the generated server
reflects the API as it behaves, and records the difference.

## 0. Check nobody already did this

Before anything else:

- Search npm (`npm search "<service> mcp"`, and the `@modelcontextprotocol` and
  vendor scopes) and GitHub for an existing server.
- Check the vendor's own docs for a first-party MCP — several ship one now
  without advertising it outside a changelog entry.

If something exists, say so with the link and ask whether to contribute there,
fork it, or proceed anyway. Building a fourth redundant wrapper is rarely the
right outcome. If proceeding, note in the README how this one differs.

## 1. Gather inputs

Ask for whatever isn't already provided:

- **Docs** — a URL, an OpenAPI/Swagger spec, a Postman collection, or pasted
  text. An OpenAPI spec is worth a great deal more than prose; ask explicitly
  whether one exists at `/openapi.json`, `/swagger.json`, or in the docs footer.
- **API key** *(optional but changes the outcome substantially)* — offered for
  verifying the surface. Confirm it is the user's own key or one they're
  authorised to test with, and ask for a sandbox/test-tier key if the vendor
  offers one.
- **Scope** — which parts of the API matter. Most third-party APIs are far
  larger than the useful MCP surface. Ask what they actually want to do with it.
- **Package name and visibility** — scoped npm name, public or private.

If no key is offered, proceed docs-only: everything gets `evidence: docs`, and
the README says plainly that the server is unverified against a live API.

Fetch the docs with `fetch_markdown` / `fetch_json`, or `tavily_crawl` for a
multi-page docs site. Save the raw fetch under `docs/upstream/` in the new repo
and record each source with its date and a hash in `api-surface.yaml` — the
hashes are what `revalidate-api-surface` diffs against later.

## 2. Draft the surface map from the docs

Copy `templates/api-surface.yaml` from this plugin into the new repo and fill in
what the docs claim: base URL, auth mechanism, endpoints, parameters, response
shapes, pagination style, rate limits, error format. Everything is
`evidence: docs` at this stage.

Flag the things docs habitually get wrong, so step 3 targets them: default and
maximum page sizes, which parameters are genuinely required, date/time formats
and timezone handling, whether IDs are strings or integers, nullability, and
whether errors come back as HTTP status codes, a body field, or both.

## 3. Verify against the live API — read-only first

With a key, and only with the user's agreement to spend calls against it:

1. **Prove auth works.** Call the cheapest read endpoint. Getting a 401 right
   here saves a lot of wasted work; check header name, prefix (`Bearer` vs raw),
   and whether the key belongs in a header or a query param.
2. **Walk the read endpoints in scope.** For each: confirm the path, confirm
   required parameters really are required (omit them and see), capture the
   actual response shape from a real payload rather than the docs' example, and
   note the pagination fields.
3. **Probe boundaries gently.** Page-size maxima, one invalid value per endpoint
   to capture the error shape, one call with a bad key to capture the auth error
   shape. That's enough. Do not fuzz, do not enumerate, do not loop.
4. **Note what the key can't reach.** A 403 tells you the endpoint exists and
   the key lacks scope — that is a different fact from "endpoint doesn't exist"
   and belongs in `scopes_observed`.

Write-side endpoints (`POST`/`PATCH`/`PUT`/`DELETE`) are **not** exercised here.
They're recorded from the docs, marked `evidence: docs`, and left for
`smoke-test-mcp`, which asks per operation.

Rules for this phase, which apply throughout:

- One request at a time, no parallel bursts; back off on any 429 and record it.
- Stay within documented rate limits and the vendor's terms.
- Never log, echo, or commit the key. Read it from the environment.
- Redact identifiers, emails, and tokens from anything saved as a fixture.
- Ask before any call that creates, modifies, or deletes data.

Update `api-surface.yaml` as you go: promote verified entries to
`evidence: live` with today's date, and record every place the API disagreed
with its documentation under `known_discrepancies`. That list is the most
valuable output of this step.

## 4. Design the tool surface

The endpoint list is not the tool list. See
`reference/server-conventions.md` for the full house style; the load-bearing
parts:

- **Consolidate.** One tool per resource with an `action` enum beats five tools.
  A 40-endpoint API should land at roughly 5–12 tools. Every tool description
  is loaded into every conversation's context, so the surface is a budget.
- **Model what a user asks for**, not what the API exposes. If a common request
  takes three calls, that's one tool doing three calls internally.
- **Descriptions are the interface.** State when to use the tool, what it
  returns, and what it costs. Write them for an agent that cannot see the API.
- **Mark destructive actions** and require explicit confirmation.
- **Return shaped, trimmed output.** Raw upstream JSON blows the context window;
  select fields and paginate.

Show the proposed tool list to the user before generating code.

## 5. Generate the server

Follow `reference/server-conventions.md`: TypeScript, `@modelcontextprotocol/sdk`,
zod schemas, stdio by default with streamable HTTP as an option, a thin typed
HTTP client, and one module per resource. Non-negotiables:

- Config from environment; the process fails fast with a clear message when the
  key is missing.
- Every upstream error is translated to a useful message — status, upstream
  code, and what the caller should do — never a raw stack trace.
- Timeouts and a single bounded retry on 429/5xx with backoff.
- No secret ever reaches a log line or a tool response.

Write the README as documentation of an **unofficial** server: state that it's
unaffiliated with the vendor, which API version it was verified against, the
date, and link `api-surface.yaml` for what's verified versus assumed.

## 6. Wire it up and hand off

- Add the server to the user's client config and confirm it lists its tools.
- Run `smoke-test-mcp` for the first real end-to-end check.
- Publish per `reference/npm-publishing.md` when the user asks — never
  unprompted, and never to a name that squats a vendor's namespace.

## Output

A repo containing the server, `api-surface.yaml`, `docs/upstream/`, a README,
and a summary to the user covering: the tool surface and why it was grouped that
way, what was verified live versus taken from docs, every discrepancy found, and
what remains untested.
