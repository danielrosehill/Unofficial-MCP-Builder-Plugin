---
name: smoke-test-mcp
description: Exercise an unofficial MCP server end-to-end against the live third-party API using the user's own key — connect, list tools, run real read operations unattended and write operations with per-operation confirmation, then fix whatever breaks. Proactive debugging: finds the schema mismatches, pagination bugs, and error-handling gaps that only appear against real data. Use for "smoke test the MCP", "does this server actually work", "test it against the real API", after a build or a revalidation, or before publishing.
---

# Smoke-test an MCP server against the live API

Unit tests against recorded fixtures prove the code does what it was written to
do. This proves the server works against the API as it is today, with a real
key, on real data — which is where unofficial servers actually fail.

Ends in fixes, not just a report.

## 1. Set up

- Confirm the key: the user's own or one they're authorised to test with, in the
  environment, never on a command line and never written to a file. Prefer a
  sandbox or test-tier key if the vendor has one, and say so if they do and it
  isn't being used.
- Read `api-surface.yaml`, in particular the `smoke_test` block:
  `safe_actions` run unattended, `requires_confirmation` are asked per run,
  `never_automated` are not run at all without an explicit instruction naming
  them. If the block is absent, treat every read as safe and every write as
  requiring confirmation.
- Agree the blast radius before touching anything: which account or workspace,
  whether test records may be created, and whether they should be cleaned up
  afterwards. On a production account with live customer data, default to
  read-only and say why.

## 2. Connect and inspect the surface

Start the server as a client would and check the protocol layer before the API
layer:

- It starts, handshakes, and lists tools without error.
- Every tool has a description, and the descriptions still describe what the
  tools do.
- Input schemas are valid JSON Schema, with types, enums, and required fields
  populated — an `action` enum missing a value the handler supports is a common
  and invisible defect.
- No secret appears in any tool description, schema default, or startup log.

Protocol-level failures stop the run: nothing downstream is meaningful if the
server won't hand over a tool list.

## 3. Read path — unattended

Run every read-only action. For each, check that:

- It returns without error, and the payload matches the declared output shape.
- **Pagination genuinely works.** Request more than one page. Truncating at
  page one while reporting success is the single most common bug in generated
  MCP servers, and it looks fine until someone relies on it.
- **Empty results are handled** — an empty list is not an error.
- **Filters actually filter.** Pass one and confirm the result set changes;
  silently-ignored parameters are common and pass any test that doesn't check.
- Output is shaped and trimmed, not raw upstream JSON. Note the token cost of
  the largest response — a tool that returns 40k tokens is broken in practice
  even when it's correct.
- Dates, IDs, and enums come back in the declared types.

Then deliberately break things: a bad ID, an invalid enum value, an
out-of-range page size. The server should return a clear, actionable error —
not a stack trace, not a raw upstream body, not a false success.

## 4. Write path — one confirmation per operation

For each action in `requires_confirmation`, ask before running it, stating
exactly what will be created or changed and where. Not a blanket "may I run
write tests" at the start — per operation, so the user can decline one without
declining all.

When permitted:

- Use the `fixture_prefix` from `api-surface.yaml` in every created record's
  name so test data is identifiable at a glance.
- Verify by reading back, not by trusting the write's response.
- Prefer a create → read → update → read → delete cycle on a record this run
  created, so cleanup is complete and nothing pre-existing is touched.
- Clean up as agreed. If cleanup fails, say so loudly and name the leftover
  records — silent orphans in someone's production account are the worst
  outcome this skill can produce.

Actions in `never_automated` are run only if the user names them explicitly in
this session. Nothing bulk, nothing recursive, nothing against a record the
user didn't agree to.

Throughout: sequential requests, respect rate limits, back off and record any
429.

## 5. Fix what broke

This is the point of the exercise. For each failure, work out which layer it
sits in:

- **Server bug** — wrong path, wrong parameter name, bad schema, unhandled
  pagination, swallowed error. Fix the code.
- **Surface-map error** — the API behaves differently from what
  `api-surface.yaml` claims. Fix the map, record it under
  `known_discrepancies`, then fix the code to match reality.
- **Upstream change** — the API moved since the last verification. Fix it here
  if it's small; hand off to `revalidate-api-surface` if the docs need a full
  re-diff.
- **Permission or plan limit** — the key lacks scope, or the account tier
  doesn't include the endpoint. Not a bug: record it in `scopes_observed` and
  make the tool's error message say so plainly, because the next person to hit
  it will assume it's broken.

Re-run the affected operation after each fix. Update `api-surface.yaml`:
promote everything exercised to `evidence: live` with today's date, and set
`smoke_test.last_run` and `last_result`.

## 6. Report

- Tools exercised, passed, failed, and skipped — with why for each skip.
- Every defect found, its layer, and whether it's fixed or outstanding.
- Discrepancies between the API and its documentation.
- Records created and whether cleanup succeeded.
- Response sizes worth worrying about.
- What remains untested and what it would take to test it.

Commit fixes with the surface-map update in the same change, referencing what
the live run showed.
