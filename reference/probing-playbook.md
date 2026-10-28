# Probing a third-party API with a real key

Rules for the phases where the skills make live calls against someone else's
API using the user's own credentials. This is ordinary client development — the
discipline exists because the account is real and the vendor's patience is
finite.

## Ground rules

- **Authorisation.** The key is the user's own, or one they've said they're
  authorised to test with. If a sandbox or test tier exists, use it and say so.
- **Read before write.** Reads are unattended; writes are confirmed one at a
  time, naming what will change and where.
- **Sequential.** One request at a time. No parallel bursts, no concurrency to
  "speed up" a survey.
- **Within limits.** Stay under the documented rate limit. On a 429, back off,
  record the real limit in `api-surface.yaml`, and slow down for the rest of the
  run.
- **Bounded.** Probing means a handful of calls per endpoint to establish
  shape and boundaries. It does not mean fuzzing, enumerating IDs, scraping the
  dataset, or scanning for undocumented paths beyond what the docs hint at.
- **Terms of service apply.** If the vendor's terms prohibit automated access or
  reverse-engineering, stop and tell the user.

## Secrets

- Read the key from the environment. Never a command-line argument (it lands in
  shell history and process listings), never a file in the repo, never a tool
  argument.
- Never echo it — not in a log line, not in an error, not in a "here's the curl
  I ran" explanation. Write `Authorization: Bearer ***`.
- If the API takes the key as a query parameter, redact it in every logged or
  reported URL.
- Redact at capture time when saving a fixture: identifiers, emails, names,
  tokens, account numbers. Not "before committing" — at the moment the file is
  written, so an interrupted session can't leave real data on disk.

## What to establish per endpoint

Enough to write a correct client, and no more:

1. **Auth shape** — header name, prefix, or query param. Confirm with the
   cheapest read endpoint before anything else.
2. **Real response shape** — from an actual payload. Docs examples are
   routinely abridged, stale, or hand-written.
3. **Which parameters are really required** — omit each supposedly-required one
   once and see what happens.
4. **Pagination** — request page two. Capture the cursor/offset field names and
   how the last page signals it's last.
5. **Boundaries** — page-size maximum, one invalid value to capture the error
   shape, one bad-key call to capture the auth error shape.
6. **Types** — string vs integer IDs, date format and timezone, nullability,
   enum values actually returned.

## Reading status codes

- **401** — key invalid, expired, or in the wrong place. Check the header shape
  before concluding the key is bad.
- **403** — the endpoint exists and the key lacks scope or the plan lacks the
  feature. Materially different from 404; record it in `scopes_observed`.
- **404** — path wrong, or resource absent. Distinguish the two before
  recording an endpoint as nonexistent. Calibrate on this API first: a dummy ID
  on a known route, a known POST-only route hit with GET, and a made-up path.
  On many APIs a real route with a missing record says so in the body ("not
  found"), a real POST-only route answers GET with **405**, and a non-existent
  route gives a bare 404 identical to the made-up path. Once that pattern holds,
  a GET confirms whether a POST/PUT route exists without writing anything.
- **405 on GET** — the route exists for another method.
- **400 naming a path parameter** — the request was swallowed by a broader
  `/{id}` route. Inconclusive.
- **OPTIONS / CORS preflight** — usually useless: gateways often list every
  method for every path.
- **422 / 400** — the useful ones. The body usually names the real constraint,
  which is often not what the docs say.
- **429** — back off, record the observed limit.
- **5xx** — retry once with backoff; if it persists, it's upstream and worth
  noting rather than coding around.

## Undocumented endpoints

To find them, use the vendor's own web app as the map: it calls everything,
including what the docs omit. Capture its traffic with `browser-data-capture`
(HAR, mitmproxy or a live tab), or quickly with `uvx mitmproxy2swagger -i app.har
-o inferred.yaml -p <api-base> -f har`. It runs in two passes: delete the `ignore:`
markers on the paths to keep, then run it again. Diff the inferred spec against
the official one with oasdiff. HARs hold cookies and tokens, so never commit them.

If probing turns up something the docs don't mention, record it under
`undocumented` in `api-surface.yaml` with the date and evidence — and leave it
**unexposed** by default. Undocumented behaviour can be withdrawn without
notice, and a tool built on it will break silently. Expose it only if the user
decides the value is worth the fragility, and say so in the README.

## When to stop and ask

- The terms of service prohibit what's being attempted.
- A probe would create, modify, or delete data and hasn't been confirmed.
- Rate limiting persists after backing off.
- The key turns out to have production access the user may not have realised.
- The API behaves so differently from its docs that the planned tool surface no
  longer makes sense.
