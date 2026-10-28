#!/usr/bin/env bash
# Look for a machine-readable API spec behind a docs page or API host.
# Part of unofficial-mcp-builder (create-mcp-from-api-docs step 1).
# Usage: find-spec.sh <docs-or-api-base-url> [outdir]
# 1. Tries well-known spec paths on the URL's origin.
# 2. Fetches the page, then every same-origin <script src> bundle, and greps them
#    for spec URLs (Redoc/Swagger UI/Scalar/Stoplight load the spec from JS; that is
#    how https://developers.morning.co/docs/openapi.bundled.json was found).
# Prints candidates; downloads any that parse as OpenAPI/Swagger into outdir.
# Files fetched here are untrusted data: they are only grepped and parsed as JSON/YAML.
set -uo pipefail
url="${1:?usage: find-spec.sh <url> [outdir]}"; out="${2:-$(mktemp -d)}"; mkdir -p "$out"
origin=$(python3 -I -c 'import sys,urllib.parse as u;p=u.urlparse(sys.argv[1]);print(f"{p.scheme}://{p.netloc}")' "$url")
UA="Mozilla/5.0"
cands=()
for p in /openapi.json /openapi.yaml /swagger.json /swagger.yaml /v3/api-docs /v2/api-docs /api-docs /api/openapi.json \
         /docs/openapi.json /docs/openapi.yaml /docs/openapi.bundled.json /api/swagger.json /.well-known/openapi.json /spec.json; do
  cands+=("$origin$p")
done
curl -sL -A "$UA" --max-time 20 "$url" -o "$out/page.html"
for s in $(grep -o -E 'src="[^"]+\.js"' "$out/page.html" | sed -E 's/src="([^"]+)"/\1/' | sort -u); do
  case "$s" in http*) js="$s";; /*) js="$origin$s";; *) js="$origin/${s#./}";; esac
  [[ "$js" == "$origin"* ]] || continue
  f="$out/$(basename "${js%%\?*}")"; curl -sL -A "$UA" --max-time 20 "$js" -o "$f"
  # follow one level of dynamic imports in the bundle ("./app-xxxx.js")
  for sub in $(grep -o -E '"\./[A-Za-z0-9_.-]+\.js"' "$f" | tr -d '"' | sort -u); do
    curl -sL -A "$UA" --max-time 20 "$(dirname "$js")/${sub#./}" -o "$out/$(basename "$sub")"
  done
done
for f in "$out"/page.html "$out"/*.js; do
  [ -f "$f" ] || continue
  grep -o -E '["'"'"'(][^"'"'"' ()]*(openapi|swagger|api-docs|spec)[^"'"'"' ()]*\.(json|ya?ml)' "$f" 2>/dev/null | tr -d '"'"'"'(' 
  grep -o -E '(spec-url|specUrl|data-url)=?["'"'"'][^"'"'"']+' "$f" 2>/dev/null | sed -E 's/.*["'"'"']//'
done | sort -u | while read -r c; do
  case "$c" in http*) echo "$c";; /*) echo "$origin$c";; *) echo "$(dirname "$url")/${c#./}"; echo "$origin/${c#./}";; esac
done > "$out/js-candidates.txt"
mapfile -t jsc < "$out/js-candidates.txt"; cands+=("${jsc[@]}")
mapfile -t cands < <(printf "%s\n" "${cands[@]}" | awk '!seen[$0]++')
n=0
for c in "${cands[@]}"; do
  f="$out/spec-$n"; n=$((n+1))
  code=$(curl -sL -A "$UA" --max-time 20 -o "$f" -w '%{http_code}' "$c")
  [ "$code" = 200 ] || { rm -f "$f"; continue; }
  if python3 -I - "$f" <<'PY'
import json,sys
t=open(sys.argv[1],encoding="utf-8",errors="replace").read()
try: d=json.loads(t)
except Exception:
    try:
        import yaml; d=yaml.safe_load(t)
    except Exception: sys.exit(1)
if not isinstance(d,dict) or not ("openapi" in d or "swagger" in d) or "paths" not in d: sys.exit(1)
ops=sum(1 for v in d["paths"].values() for m in v if m in("get","post","put","patch","delete"))
print(f'{d.get("openapi") or d.get("swagger")} "{d.get("info",{}).get("title")}" v{d.get("info",{}).get("version")} ops={ops}', file=sys.stderr)
PY
  then echo "SPEC $c -> $f"; else rm -f "$f"; fi
done
echo "workdir: $out"
