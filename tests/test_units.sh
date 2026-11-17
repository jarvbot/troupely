#!/usr/bin/env bash
# shellcheck disable=SC2034  # check() takes its condition as a string, so uses are invisible
# W7: the small writers every install depends on — envfile.py, group-access.py,
# `troupely.sh pair`, payload_sync.py. Sandbox only; nothing touches a real vault.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
T="$(mktemp -d)"
perm(){ stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
jq_(){ python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$@"; }

echo "envfile.py"
E="$T/.env"; printf 'KEEP=1\n# comment\nTOK=old\n' > "$E"; chmod 644 "$E"
python3 "$REPO/lib/envfile.py" "$E" TOK=new 'URL=a$b`c`' NEWK=x
check "updates in place, keeps other lines" 'grep -qx "KEEP=1" "$E" && grep -qx "# comment" "$E" && grep -qx "TOK='"'"'new'"'"'" "$E"'
check "values literal under bash sourcing" '[ "$(bash -c "set -a; . $E; printf %s \"\$URL\"")" = "a\$b\`c\`" ]'
check "mode 600" '[ "$(perm "$E")" = 600 ]'
python3 "$REPO/lib/envfile.py" "$E" -TOK; check "-KEY deletes" '! grep -q "^TOK=" "$E"'
python3 "$REPO/lib/envfile.py" "$E" "BAD=it's" 2>/dev/null; check "single quote refused" '[ $? -ne 0 ] && ! grep -q "^BAD=" "$E"'
python3 "$REPO/lib/envfile.py" "$E" "$(printf 'NL=a\nB=1')" 2>/dev/null; check "control char refused" '[ $? -ne 0 ] && ! grep -q "^B=" "$E"'
python3 "$REPO/lib/envfile.py" "$E" "1X=y" 2>/dev/null; check "bad key refused" '[ $? -ne 0 ]'

echo "group-access.py"
SD="$T/tg"; mkdir -p "$SD"; GA="$REPO/lib/group-access.py"
python3 "$GA" "$SD" -100 >/dev/null
check "nobody paired: no group entry" '[ "$(jq_ "$SD/access.json" "d[\"groups\"].get(\"-100\")")" = None ]'
python3 - "$SD/access.json" <<'PY'
import json,sys; p=sys.argv[1]; a=json.load(open(p)); a["allowFrom"]=["42"]; a["groups"]["-100"]={"note":"keep","allowFrom":[]}; json.dump(a,open(p,"w"))
PY
python3 "$GA" "$SD" -100 >/dev/null
check "paired: group allowFrom = paired" '[ "$(jq_ "$SD/access.json" "d[\"groups\"][\"-100\"][\"allowFrom\"]")" = "['"'"'42'"'"']" ]'
check "other group keys kept" '[ "$(jq_ "$SD/access.json" "d[\"groups\"][\"-100\"][\"note\"]")" = keep ]'
python3 "$GA" "$SD" -100 --close >/dev/null
check "--close removes the entry" '[ "$(jq_ "$SD/access.json" "d[\"groups\"].get(\"-100\")")" = None ]'
echo '{broken' > "$T/bad.json"; mkdir -p "$T/bad"; mv "$T/bad.json" "$T/bad/access.json"
python3 "$GA" "$T/bad" -100 >/dev/null 2>&1; check "unreadable access.json exits 1" '[ $? -eq 1 ]'

echo "troupely.sh pair"
S="$T/S"; mkdir -p "$S"; (cd "$REPO" && git ls-files -z | grep -zv '^vault/' | xargs -0 tar cf -) | (cd "$S" && tar xf -)
printf "TROUPELY_MODE='native'\nTROUPELY_PERSONAS='bob'\nTROUPELY_TG_GROUP='-100'\nTROUPELY_TG_TOPIC_BOB='7'\n" > "$S/.env"
PS="$S/vault/.claude/homes/bob/.claude/channels/telegram"; mkdir -p "$PS"
now=$(python3 -c 'import time;print(int(time.time()*1000))')
cat > "$PS/access.json" <<J
{"dmPolicy":"pairing","allowFrom":[],"groups":{},"pending":{
 "good1":{"senderId":"501","chatId":"501","createdAt":$now,"expiresAt":$((now+600000))},
 "old22":{"senderId":"502","chatId":"502","createdAt":$now,"expiresAt":$((now-1000))}}}
J
(cd "$S" && ./troupely.sh pair bob >"$T/list.out" 2>&1)
check "no code lists, approves nobody" 'grep -q "code good1" "$T/list.out" && grep -q "(expired)" "$T/list.out" && [ "$(jq_ "$PS/access.json" "d[\"allowFrom\"]")" = "[]" ]'
(cd "$S" && ./troupely.sh pair bob nope >/dev/null 2>&1); check "unknown code fails" '[ $? -ne 0 ]'
(cd "$S" && ./troupely.sh pair bob old22 >/dev/null 2>&1); check "expired code fails" '[ $? -ne 0 ] && [ "$(jq_ "$PS/access.json" "d[\"allowFrom\"]")" = "[]" ]'
(cd "$S" && ./troupely.sh pair bob good1 >/dev/null 2>&1)
check "good code: sender allowed" '[ "$(jq_ "$PS/access.json" "d[\"allowFrom\"]")" = "['"'"'501'"'"']" ]'
check "good code: approved/ marker written" '[ "$(cat "$PS/approved/501")" = 501 ]'
check "good code: pending entry removed" '[ "$(jq_ "$PS/access.json" "\"good1\" in d[\"pending\"]")" = False ]'
check "topic-routed: group opened to the paired sender" '[ "$(jq_ "$PS/access.json" "d[\"groups\"][\"-100\"][\"allowFrom\"]")" = "['"'"'501'"'"']" ]'

echo "payload_sync.py"
P="$T/payload"; V="$T/vault"; mkdir -p "$P/framework" "$P/memory" "$P/skills/x" "$P/templates" "$V"
echo 1.1.0 > "$P/VERSION"; echo rules-v1 > "$P/RULES.md"; echo ms-v1 > "$P/MEMORY-SYSTEM.md"
echo fw > "$P/framework/a.md"; echo lint > "$P/memory/memory_lint.py"; echo cfg > "$P/memory/memory-lint.config.json"
echo sk > "$P/skills/x/SKILL.md"; echo seed > "$P/templates/vault-CLAUDE.md"
sync(){ python3 "$REPO/lib/payload_sync.py" "$P" "$V" 2>&1; }
sync >/dev/null
check "first sync copies owned + seeds" '[ -f "$V/RULES.md" ] && [ -f "$V/.claude/skills/x/SKILL.md" ] && [ "$(cat "$V/CLAUDE.md")" = seed ]'
echo mine > "$V/CLAUDE.md"; echo edited > "$V/MEMORY-SYSTEM.md"; echo local-rules > "$V/RULES.md"; rm "$V/framework/a.md"
echo rules-v2 > "$P/RULES.md"; echo ms-v2 > "$P/MEMORY-SYSTEM.md"; echo 1.2.0 > "$P/VERSION"
out="$(sync)"
check "RULES.md always overwritten" '[ "$(cat "$V/RULES.md")" = rules-v2 ]'
check "edited owned file kept, new one offered" '[ "$(cat "$V/MEMORY-SYSTEM.md")" = edited ] && [ "$(cat "$V/MEMORY-SYSTEM.md.troupely-new")" = ms-v2 ]'
check "seed-once file never touched" '[ "$(cat "$V/CLAUDE.md")" = mine ]'
check "deleted owned file stays deleted" '[ ! -e "$V/framework/a.md" ]'
rm "$V/MEMORY-SYSTEM.md.troupely-new"; out2="$(sync)"
check "offered once, not re-warned" '! printf %s "$out2" | grep -q "edited locally" && [ ! -e "$V/MEMORY-SYSTEM.md.troupely-new" ]'
echo 1.0.0 > "$P/VERSION"; echo rules-old > "$P/RULES.md"; out3="$(sync)"
check "downgrade refused" 'printf %s "$out3" | grep -q "no downgrades" && [ "$(cat "$V/RULES.md")" = rules-v2 ]'

rm -rf "$T"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
