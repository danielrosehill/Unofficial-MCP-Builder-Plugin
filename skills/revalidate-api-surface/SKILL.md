---
name: revalidate-api-surface
description: Periodic drift check for an unofficial MCP server — re-fetch the vendor's current API documentation, diff it against the committed api-surface.yaml, and update the server for anything that changed upstream. Catches new endpoints, renamed or removed fields, changed defaults, deprecations, and auth changes before users hit them as bugs. Use for "check if the API changed", "revalidate the MCP", "is this server still in sync", scheduled maintenance runs, or after a vendor changelog entry.
---

# Revalidate an MCP server against its upstream API

Third-party APIs move without telling their unofficial clients. This is the
recurring check: what has the vendor changed since the surface map was last
verified, and what does the server need to do about it.

Designed to be run on a schedule (monthly is usually right; weekly for an API
under active development) and to be **safe to run unattended in report-only
mode** — it changes nothing until it has shown you the diff.

## 1. Establish the baseline

Read `api-surface.yaml` from the server repo. It records every doc source with
its URL, fetch date, and content hash, plus the version signal and every claim's
evidence level. If it's missing, the server predates this workflow: reconstruct
it from `templates/api-surface.yaml` and the current code, mark everything
`evidence: inferred`, and say so — this run becomes a baselining run rather than
a drift check.

Note how long it's been since `verified` on each endpoint. Anything unverified
for more than a couple of months should be treated as suspect regardless of what
the diff says.

## 2. Check the cheap signals first

In order, stopping early if nothing has moved:

1. **Changelog.** If `version_signal.changelog_url` is set, read entries since
   the last verification date. This is the highest-value source by a wide margin
   — vendors announce breaking changes there and nowhere else.
2. **Version header or endpoint.** Compare `version_signal.observed` against
   what a live request returns now.
3. **Doc hashes.** Re-fetch each source in `docs:` and compare the hash of the
   normalised content. Normalise before hashing (strip nav, timestamps, session
   IDs, "last updated" strings) or you'll get a diff on every run and learn to
   ignore it.
4. **OpenAPI spec.** If one exists, diff it structurally rather than
   textually — added/removed paths, changed required-ness, changed types,
   new enum values, new deprecation markers. Re-download it and diff against the
   committed snapshot with oasdiff:

   ```bash
   docker run --rm -v "$PWD":/r:ro -v /tmp/w:/w:ro tufin/oasdiff changelog /r/spec/<vendor>-openapi.json /w/new.json
   ```

   Then diff the spec against what the **code** calls, operation by operation
   (method + path, not just path):

   ```bash
   # list the server's calls as "METHOD /path" lines; adapt the grep to the client code
   grep -o -E 'client\.(get|post|put|delete)\([^,)]*' src/*.ts \
     | sed -E 's/client\.(get|post|put|delete)\(/\1 /; s/[`"]//g' | awk '{print toupper($1), $2}' > /tmp/w/calls.txt
   python3 -I scripts/spec-diff.py /tmp/w/new.json /tmp/w/calls.txt   # --json for machine output
   ```

   "In spec, not called" are gaps, or calls made through other host constants
   (auth, upload, CDN). Check those by hand. "Called, not in spec" are undocumented
   or dead; probe them (`reference/probing-playbook.md`). A path-only comparison
   misses a route the code never calls in that method, and a reference doc that
   lists an endpoint doesn't prove the code wires it up. Record the expected
   entries in `api-surface.yaml` so the next run only looks at new ones.

If every signal is unchanged, report "no drift, last verified <date>", update
the check date in `api-surface.yaml`, and stop. That's a successful run.

## 3. Classify what changed

For each difference, sort into:

- **Breaking** — removed endpoint or field, renamed field, type change, a
  parameter becoming required, auth or base-URL change. The server is or will
  soon be wrong.
- **Deprecation** — still works, marked for removal. Record the sunset date if
  given; this is the one that bites six months later.
- **Additive** — new endpoint, new optional parameter, new response field. No
  urgency; may be worth exposing.
- **Documentation-only** — prose rewritten, examples changed, endpoint
  behaviour identical. Re-hash and move on.

Cross-check against `known_discrepancies`: if the docs now describe what the API
was already doing, the discrepancy is resolved, not new. Conversely, a doc
change with no behaviour change is often the vendor documenting something that
shipped long ago.

## 4. Verify the interesting ones live

Docs lie in both directions — an endpoint can be removed from the docs and still
work, or documented and never have shipped. With a key available, confirm the
changes that matter:

- Call each endpoint reported as removed. Still 200? It's undocumented now, not
  gone; keep it working but mark it `undocumented` and unsupported.
- Call each endpoint whose response shape supposedly changed and capture the
  real shape.
- Confirm auth still works if anything auth-adjacent moved.

Read-only calls only. Same discipline as always: sequential, within rate limits,
no writes, nothing logged that contains the key. If verifying a change requires
a write, note it and leave it to `smoke-test-mcp`.

## 5. Update the server

For anything confirmed, in this order:

1. **Breaking changes first.** Update the client, schemas, and tool handlers.
   If a tool's behaviour changes for callers, update its description too — a
   stale description is a bug an agent can't see around.
2. **Deprecations** — keep working, add a note in the tool description or
   README with the sunset date, and open a tracking line in
   `known_discrepancies` with `action: watch`.
3. **Additive** — propose rather than implement. Ask before growing the tool
   surface; context budget is the binding constraint, and most new endpoints
   don't earn a tool.
4. **Always** update `api-surface.yaml`: new hashes, new `verified` dates,
   promote or demote evidence levels, record the version signal.

Bump the version (minor for additive, major if the tool surface changed
incompatibly) and write a CHANGELOG entry that names the upstream change, not
just the code change — "Acme moved `created` to `created_at` in the v2 widget
response" is what a future reader needs.

## 6. Report

Whether or not anything changed, report:

- Signals checked and what each said.
- Changes found, by class, each with its evidence and whether it was confirmed
  live or only in docs.
- What was changed in the server, and what was deliberately left alone.
- Anything that needs a decision — new endpoints worth exposing, deprecations
  with a deadline, a discrepancy the vendor should be told about.
- The next date this should run.

Commit the surface map update and the code change together; the surface map is
the evidence for the diff.

## Running unattended

For a scheduled run, default to **report-only**: do steps 1–4, write the report,
and stop before step 5 unless the user has said to auto-apply. Nobody wants to
discover a scheduled agent rewrote their tool surface at 3am. Breaking changes
found unattended are worth a notification rather than a silent commit.
