#!/usr/bin/env bash
# troupely output-health watcher — asserts that "should-be-live" producers are actually
# producing. Catches the silent-degradation failure: a process that's alive (exit 0, no error)
# but whose OUTPUT went stale or empty — a feed that 200s with a cached body, a pipeline that
# runs but writes nothing. Status codes lie; freshness doesn't.
#
# Config-driven, stdlib-only (jq-free). Exits nonzero + prints findings if any producer is
# down, so a heartbeat hook can surface it. Run it each heartbeat:
#
#   health/output-health.sh                         # uses health/output-health.config.json
#   health/output-health.sh /path/to/config.json
#
# Config shape (see output-health.config.example.json):
#   { "producers": [
#       { "name": "x", "path": "~/data/x.json", "max_age_hours": 24, "min_bytes": 100,
#         "must_match": "optional regex the output must contain" } ] }
set -euo pipefail

CONFIG="${1:-$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/output-health.config.json}"
[ -f "$CONFIG" ] || { echo "✗ config not found: $CONFIG (copy output-health.config.example.json)" >&2; exit 2; }

now=$(date +%s)
findings=0
emit() { echo "  • $*" >&2; findings=$((findings+1)); }

# Parse the producers array with python3 (stdlib) → one tab-separated line per producer.
producers=$(python3 - "$CONFIG" <<'PY'
import json, os, sys
cfg = json.load(open(sys.argv[1]))
for p in cfg.get("producers", []):
    path = os.path.expanduser(p.get("path", ""))
    print("\t".join([
        p.get("name", "?"), path,
        str(p.get("max_age_hours", "")), str(p.get("min_bytes", "")),
        p.get("must_match", ""),
    ]))
PY
)

[ -n "$producers" ] || { echo "output-health: no producers configured in $CONFIG"; exit 0; }

while IFS=$'\t' read -r name path max_age_h min_bytes must_match; do
  [ -n "$name" ] || continue
  if [ ! -f "$path" ]; then emit "$name: MISSING ($path)"; continue; fi
  # freshness
  if [ -n "$max_age_h" ]; then
    # GNU first: on Linux `stat -f` is --file-system and succeeds with unrelated text.
    mtime=$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || echo 0)
    age_h=$(( (now - mtime) / 3600 ))
    [ "$age_h" -gt "$max_age_h" ] && emit "$name: STALE (${age_h}h old > ${max_age_h}h) $path"
  fi
  # non-empty
  if [ -n "$min_bytes" ]; then
    bytes=$(wc -c < "$path" | tr -d ' ')
    [ "$bytes" -lt "$min_bytes" ] && emit "$name: TOO SMALL (${bytes}B < ${min_bytes}B) $path"
  fi
  # content assertion (catches "output present but sub-source silently empty")
  if [ -n "$must_match" ] && ! grep -qE "$must_match" "$path" 2>/dev/null; then
    emit "$name: MISSING PATTERN /$must_match/ in $path"
  fi
done <<< "$producers"

if [ "$findings" -gt 0 ]; then
  echo "⚠️  output-health: $findings producer(s) down" >&2
  exit 1
fi
exit 0
