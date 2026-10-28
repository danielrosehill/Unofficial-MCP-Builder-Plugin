#!/usr/bin/env python3
"""Compare an OpenAPI spec with the calls an MCP server (or plugin) makes.

Usage: python3 -I spec-diff.py <spec.json|yaml> <calls.txt> [--json]
calls.txt: one "METHOD /path" per line, path params in any form ({id}, ${id}, :id).
Path params are normalised to {} on both sides, query strings dropped.
Operations with their own `servers` (other hosts) are matched on path alone.

Prints three lists: in spec but not called (candidate gaps), called but not in spec
(undocumented: probe these, they may be dead), and matched. Machine output: --json.
"""
import json, re, sys

def load(p):
    t = open(p, encoding="utf-8").read()
    try:
        return json.loads(t)
    except Exception:
        import yaml
        return yaml.safe_load(t)

def norm(path):
    path = path.split("?")[0].rstrip("\\").rstrip("/") or "/"
    path = re.sub(r"\$\{[^}]+\}|\{[^}]+\}|:[A-Za-z_]\w*", "{}", path)
    path = re.sub(r"(?<=[^/])\{\}$", "", path)  # "/types${lang}": a query string glued on, not a path param
    return path

spec = load(sys.argv[1])
ops = {}
for p, item in spec.get("paths", {}).items():
    for m, op in item.items():
        if m.lower() in ("get", "post", "put", "patch", "delete"):
            ops[(m.upper(), norm(p))] = (op.get("summary") or "", (op.get("tags") or [""])[0])
calls = set()
for line in open(sys.argv[2], encoding="utf-8"):
    parts = line.split()
    if len(parts) >= 2 and parts[0].upper() in ("GET", "POST", "PUT", "PATCH", "DELETE"):
        calls.add((parts[0].upper(), norm(parts[1])))

matched = sorted(ops.keys() & calls)
gaps = sorted(ops.keys() - calls)
undoc = sorted(calls - ops.keys())
res = {
    "spec": {"title": spec.get("info", {}).get("title"), "version": spec.get("info", {}).get("version"), "operations": len(ops)},
    "matched": [" ".join(k) for k in matched],
    "in_spec_not_called": [{"op": " ".join(k), "tag": ops[k][1], "summary": ops[k][0]} for k in gaps],
    "called_not_in_spec": [" ".join(k) for k in undoc],
}
if "--json" in sys.argv:
    print(json.dumps(res, indent=2, ensure_ascii=False))
else:
    s = res["spec"]
    print(f'{s["title"]} v{s["version"]}: {s["operations"]} operations, {len(calls)} calls, {len(matched)} matched')
    print("\nIN SPEC, NOT CALLED (gaps, or covered on another host):")
    for g in res["in_spec_not_called"]:
        print(f'  {g["op"]:<50} [{g["tag"]}] {g["summary"]}')
    print("\nCALLED, NOT IN SPEC (undocumented: probe, may be dead):")
    for u in undoc:
        print("  " + " ".join(u))
