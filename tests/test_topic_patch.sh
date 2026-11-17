#!/usr/bin/env bash
# shellcheck disable=SC2034  # check() takes its condition as a string, so uses are invisible
# W10: the topic patch covers every installed version dir, says when it can't patch, and
# `status` warns when a topic-routed persona's plugin has no topic filter.
# Runs against the real upstream server.ts (tests/fixtures/telegram-0.0.7, unmodified).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$REPO/plugin-patch/apply-topic-patch.py"
FIX="$REPO/tests/fixtures/telegram-0.0.7"
PASS=0; FAIL=0
ok(){ PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
T="$(mktemp -d)"; C="$T/cache/telegram"

mkplug(){ mkdir -p "$C/$1"; cp -R "$FIX/." "$C/$1/"
  sed -i.bak "s/\"version\": \"0.0.7\"/\"version\": \"$1\"/" "$C/$1/.claude-plugin/plugin.json"; rm -f "$C/$1/.claude-plugin/plugin.json.bak"; }

echo "patch"
mkplug 0.0.7; mkplug 0.0.8
check "fixture starts unpatched" '! grep -q TELEGRAM_TOPIC_FILTER "$FIX/server.ts"'
python3 "$PATCH" --check "$C" >/dev/null 2>&1; check "--check fails on unpatched" '[ $? -eq 1 ]'
python3 "$PATCH" "$C" >"$T/p.out" 2>&1
check "both version dirs patched" '[ "$(grep -l TELEGRAM_TOPIC_FILTER "$C"/*/server.ts | wc -l | tr -d " ")" = 2 ]'
check "outbound threading added" '[ "$(grep -l "troupely topic-outbound patch" "$C"/*/server.ts | wc -l | tr -d " ")" = 2 ]'
check "version drift named" 'grep -q "0.0.8 installed" "$T/p.out"'
cp "$C/0.0.7/server.ts" "$T/once.ts"; python3 "$PATCH" "$C" >/dev/null 2>&1
check "idempotent" 'cmp -s "$C/0.0.7/server.ts" "$T/once.ts"'
python3 "$PATCH" --check "$C" >/dev/null 2>&1; check "--check passes when patched" '[ $? -eq 0 ]'
echo "gate behaviour (the injected code, run)"
if command -v bun >/dev/null 2>&1; then
  (cd "$C/0.0.7" && bun build --target=bun --no-bundle server.ts >/dev/null 2>"$T/bun.err")
  check "patched server.ts still parses (bun)" '[ $? -eq 0 ]'
  python3 - "$PATCH" "$T/gate.ts" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("p", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cases = [  # (filter, chat type, thread id, expected)
  ("7", "private", None, "deliver"), ("7", "supergroup", 7, "deliver"), ("7", "supergroup", 9, "drop"),
  ("7", "supergroup", None, "drop"), ("", "supergroup", 9, "deliver"), ("0", "supergroup", None, "deliver"),
]
out = ["type Context = any; type GateResult = { action: string }", "const results: string[] = []"]
for i, (f, t, tid, exp) in enumerate(cases):
    helpers = m.HELPERS.replace("process.env.TELEGRAM_TOPIC_FILTER", repr(f)).replace("__", f"__c{i}_")
    call = m.GATE_CALL.replace("__", f"__c{i}_")
    msg = "{}" if tid is None else "{ message_thread_id: %d }" % tid
    out += [helpers, f"function gate{i}(ctx: Context): GateResult {{ {call}; return {{ action: 'deliver' }} }}",
            f"results.push((gate{i}({{ chat: {{ type: '{t}' }}, message: {msg} }}).action === '{exp}') ? 'ok' : 'BAD case {i}')"]
out.append("console.log(results.join(' '))")
open(sys.argv[2], "w").write("\n".join(out))
PY
  bun run "$T/gate.ts" >"$T/gate.out" 2>&1
  check "DMs pass, own topic passes, other topics + General dropped, unset/0 pass all" '! grep -q BAD "$T/gate.out" && [ "$(grep -o ok "$T/gate.out" | wc -l | tr -d " ")" = 6 ]'
elif [ -n "${CI:-}" ]; then
  bad "bun is required in CI for the gate behaviour test"
else
  echo "  skip (no bun): gate behaviour"
fi

echo "migration + strict check"
mkplug 0.0.6; python3 "$PATCH" "$C/0.0.6" >/dev/null 2>&1
python3 - "$PATCH" "$C/0.0.6/server.ts" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("p", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
f = sys.argv[2]; s = open(f).read(); open(f, "w").write(s.replace(m.GATE_CALL, m.OLD_GATE_CALL))
PY
python3 "$PATCH" "$C/0.0.6" >/dev/null 2>&1
check "old DM-dropping gate line upgraded in place" 'grep -q "ctx.chat?.type !== .private." "$C/0.0.6/server.ts" && [ "$(grep -c "__topicFilterAllows(__TOPIC_FILTER" "$C/0.0.6/server.ts")" = 1 ]'
rm -rf "$C/0.0.6"
mkdir -p "$T/neg"; nc(){ rm -rf "$T/neg/x"; mkdir -p "$T/neg/x"; cp -R "$FIX/." "$T/neg/x/"; }
nc; echo "// TODO: TELEGRAM_TOPIC_FILTER" >> "$T/neg/x/server.ts"
python3 "$PATCH" --check "$T/neg/x" >/dev/null 2>&1; check "--check: a comment naming the variable is not a filter" '[ $? -eq 1 ]'
nc; python3 "$PATCH" "$T/neg/x" >/dev/null 2>&1; python3 - "$PATCH" "$T/neg/x/server.ts" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("p", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
f = sys.argv[2]; s = open(f).read(); open(f, "w").write(s.replace(m.GATE_FILTER, "\n"))
PY
python3 "$PATCH" --check "$T/neg/x" >/dev/null 2>&1; check "--check: helpers without the gate call fail" '[ $? -eq 1 ]'
python3 "$PATCH" "$T/neg/x" >"$T/neg.out" 2>&1; check "patch: partial patch reported, not certified" 'grep -q "left alone" "$T/neg.out"'
nc; python3 "$PATCH" "$T/neg/x" >/dev/null 2>&1; python3 - "$T/neg/x/server.ts" <<'PY'
import sys, re
f = sys.argv[1]; s = open(f).read()
a = s.index("// --- troupely topic-outbound patch"); b = s.index("// --- end troupely topic-outbound patch ---") + len("// --- end troupely topic-outbound patch ---")
open(f, "w").write(s[:a] + s[b:])
PY
python3 "$PATCH" --check "$T/neg/x" >"$T/neg2.out" 2>&1; check "--check: inbound-only fails, names the threading" '[ $? -eq 1 ] && grep -q "replies NOT threaded" "$T/neg2.out"'

echo "one bad version doesn't stop the rest"
U="$T/u"; mkdir -p "$U/0.0.1" "$U/0.0.9"; cp -R "$FIX/." "$U/0.0.1/"; cp -R "$FIX/." "$U/0.0.9/"
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$U/0.0.1/server.ts"
  python3 "$PATCH" "$U" >"$T/u.out" 2>&1; rc=$?
  check "unreadable older version named" 'grep -q "can.t read or write .*0.0.1" "$T/u.out"'
  check "newer version still patched" 'grep -q "__topicFilterAllows(__TOPIC_FILTER" "$U/0.0.9/server.ts"'
  chmod 644 "$U/0.0.1/server.ts"
fi

echo "anchor gone"
mkplug 0.1.0; sed -i.bak 's/function gate(ctx: Context): GateResult {/function gate(ctx: Context, x: number): GateResult {/' "$C/0.1.0/server.ts"
python3 "$PATCH" "$C" >"$T/a.out" 2>&1; rc=$?
check "unpatchable dir is named, not hidden" 'grep -q "gate() anchor not found in .*0.1.0" "$T/a.out"'
check "patch run still exits 0 (DMs keep working)" '[ $rc -eq 0 ]'
python3 "$PATCH" --check "$C" >"$T/c.out" 2>&1
check "--check fails and names it" '[ $? -eq 1 ] && grep -q "0.1.0: NO topic filter" "$T/c.out"'

echo "status"
S="$T/S"; mkdir -p "$S"; (cd "$REPO" && git ls-files -z | grep -zv '^vault/' | xargs -0 tar cf -) | (cd "$S" && tar xf -)
mkdir -p "$S/vault/.claude/plugins/cache/claude-plugins-official"
cp -R "$C" "$S/vault/.claude/plugins/cache/claude-plugins-official/telegram"
printf "TROUPELY_MODE='native'\nTROUPELY_PERSONAS='alpha,beta'\nTROUPELY_TG_TOPIC_BETA='7'\n" > "$S/.env"
export TMUX_TMPDIR="$T/tmux"; mkdir -p "$TMUX_TMPDIR"; unset TMUX
(cd "$S" && ./troupely.sh status >"$T/s.out" 2>&1)
check "status warns for the routed persona" 'grep -q "topic routing is NOT enforced.*beta" "$T/s.out"'
check "status names the unpatched version" 'grep -q "0.1.0: NO topic filter" "$T/s.out"'
rm -rf "$S/vault/.claude/plugins/cache/claude-plugins-official/telegram/0.1.0"
(cd "$S" && ./troupely.sh status >"$T/s2.out" 2>&1)
check "status quiet when every dir is patched" '! grep -q "NOT enforced" "$T/s2.out"'
printf "TROUPELY_MODE='native'\nTROUPELY_PERSONAS='alpha'\n" > "$S/.env"
rm -rf "$S/vault/.claude/plugins/cache"
(cd "$S" && ./troupely.sh status >"$T/s3.out" 2>&1)
check "no routed persona, no check" '! grep -q "topic" "$T/s3.out"'

rm -rf "$T"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
