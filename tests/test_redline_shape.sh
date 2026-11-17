#!/usr/bin/env bash
# The planning skill's redline mode: the shipped example must have the template's shape.
# Usage: tests/test_redline_shape.sh [redline.md]   (default: the shipped example)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

TEMPLATE=skills/planning/templates/redline.md

# shape_errors <file>: prints one line per missing piece, nothing if the shape is right.
shape_errors(){
  python3 - "$1" "$TEMPLATE" <<'EOF'
import re, sys, os
doc, tpl = open(sys.argv[1]).read(), open(sys.argv[2]).read()
errs = []
# frontmatter: mode + supersedes, and the superseded file is kept next to it
fm = re.match(r'^---\n(.*?)\n---\n', doc, re.S)
fm = fm.group(1) if fm else ''
if not re.search(r'^mode:\s*redline\b', fm, re.M): errs.append('frontmatter: mode: redline')
m = re.search(r'^supersedes:\s*(\S+)', fm, re.M)
if not m: errs.append('frontmatter: supersedes')
elif not os.path.exists(os.path.join(os.path.dirname(sys.argv[1]), m.group(1))):
    errs.append(f'superseded original not found: {m.group(1)}')
# every fixed section heading in the template appears in the doc (placeholder headings skipped)
for h in re.findall(r'^(#{2,3}) (.+?)\s*$', tpl, re.M):
    title = re.split(r'[:(<]', h[1])[0].strip()   # "Revised spec (what <builder> builds)" -> "Revised spec"
    if title and not re.search(r'^#{2,3} ' + re.escape(title), doc, re.M):
        errs.append(f'section missing: {title}')
if not re.search(r'^## TL;DR', doc, re.M): errs.append('section missing: TL;DR')
if not re.search(r'\*\*Everything else in v0 stands:\*\*', doc): errs.append('TL;DR lacks "Everything else in v0 stands"')
# findings tables: | ID | finding | verdict | resolution |, verdict is Accept / Change / Reject
rows = re.findall(r'^\| ([A-Z]{1,2}\d+) \| (.*?) \| \*\*(.+?)\*\* \|', doc, re.M)
findings = [r for r in rows if not r[0].startswith('RT')]
if len(findings) < 3: errs.append(f'fewer than 3 verdict rows ({len(findings)})')
for fid, _, verdict in findings:
    if not re.match(r'(Accept|Change|Reject)\b', verdict): errs.append(f'{fid}: verdict "{verdict}" is not Accept/Change/Reject')
# red-team round: severity + resolution that is Changed or an accepted risk
rt = re.findall(r'^\| (RT\d+) \| (High|Med|Low) \| .*? \| (.*?) \|\s*$', doc, re.M)
if not rt: errs.append('red-team round has no RT rows')
for rid, _, res in rt:
    if not re.match(r'\*\*(Changed|Accepted risk)', res): errs.append(f'{rid}: resolution must start Changed / Accepted risk')
# acceptance list exists and is numbered
acc = re.search(r'^### Acceptance.*?\n(.*?)(?=^## |\Z)', doc, re.M | re.S)
if not acc or not re.search(r'^\d+\. ', acc.group(1), re.M): errs.append('no numbered acceptance list')
print('\n'.join(errs))
EOF
}

EX="${1:-examples/design-docs/trailpulse-multi-trail-redline.md}"
echo "redline shape: $EX"
errs="$(shape_errors "$EX")"
[ -z "$errs" ] && ok "matches templates/redline.md" || { bad "matches templates/redline.md"; printf '       %s\n' "$errs"; }

# The check must fail on what it exists to catch: a plan that is not a redline.
echo "redline shape: founding case (a v0 plan is rejected)"
[ -n "$(shape_errors examples/design-docs/trailpulse-multi-trail-plan-v0.md)" ] && ok "v0 plan fails the shape check" || bad "v0 plan fails the shape check"

# Every file the skill points at exists.
echo "planning skill wiring"
for f in references/redline.md templates/redline.md; do
  grep -q "$f" skills/planning/SKILL.md && [ -f "skills/planning/$f" ] && ok "SKILL.md → $f" || bad "SKILL.md → $f"
done

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
