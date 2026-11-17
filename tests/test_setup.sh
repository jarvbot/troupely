#!/usr/bin/env bash
# shellcheck disable=SC2034  # check() takes its condition as a string, so uses are invisible
# Drives ./setup.sh end to end with scripted answers, in a throwaway copy of the repo.
# Fake `curl` answers Telegram's getMe; fake `docker` reports "not running", so setup writes
# .env and stops before any build. No network, no daemon, nothing touches the real repo.
#   bash tests/test_setup.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

sandbox(){
  local d; d="$(mktemp -d)"
  (cd "$REPO" && git ls-files -co --exclude-standard -z | grep -zv '^vault/' | xargs -0 tar cf -) | (cd "$d" && tar xf -)
  mkdir -p "$d/.fakebin"
  cat > "$d/.fakebin/curl" <<'EOF'
#!/bin/sh
case "$*" in
  *getMe*) echo '{"ok":true,"result":{"username":"test_bot"}}';;
  *getWebhookInfo*) echo '{"ok":true,"result":{"url":""}}';;
  *) echo '{"ok":true,"result":[]}';;
esac
EOF
  cat > "$d/.fakebin/docker" <<'EOF'
#!/bin/sh
case "$1" in info) exit 1;; *) exit 0;; esac
EOF
  chmod +x "$d/.fakebin/"*
  printf '%s' "$d"
}

# run_setup <dir> <answers...>: one answer per line on stdin (non-TTY: choose reads a number)
run_setup(){
  local d="$1"; shift
  (cd "$d" && printf '%s\n' "$@" | PATH="$d/.fakebin:$PATH" TROUPELY_NATIVE=0 ./setup.sh > "$d/.out" 2>&1)
}
envval(){ sed -n "s/^$2='\(.*\)'\$/\1/p" "$1/.env" | tail -1; }

TOK="sk-ant-oat01-TESTSECRET123"
BOT="123456:AAFAKEBOTTOKEN"

echo "W2: Docker + subscription defaults to a setup-token token"
d="$(sandbox)"
run_setup "$d" 1 1 "$TOK" boss "$BOT" 1 1
[ "$(envval "$d" CLAUDE_CODE_OAUTH_TOKEN)" = "$TOK" ] && ok "token written to .env" || bad "token written to .env ($(envval "$d" CLAUDE_CODE_OAUTH_TOKEN))"
grep -q "$TOK" "$d/.out" && bad "token never echoed to the terminal" || ok "token never echoed to the terminal"

echo "W2: re-run keeps the token on Enter, and still never prints it"
cp "$d/.out" "$d/.out1"
run_setup "$d" 1 1 "" boss "" 1 1
[ "$(envval "$d" CLAUDE_CODE_OAUTH_TOKEN)" = "$TOK" ] && ok "Enter keeps the existing token" || bad "Enter keeps the existing token"
grep -q "$TOK" "$d/.out" && bad "kept token not printed back" || ok "kept token not printed back"

echo "W2: a non-token paste is refused"
d2="$(sandbox)"
run_setup "$d2" 1 1 "sk-ant-api03-WRONGKIND" "$TOK" boss "$BOT" 1 1
grep -q "doesn't look like a setup-token token" "$d2/.out" && ok "wrong-kind key rejected" || bad "wrong-kind key rejected"
[ "$(envval "$d2" CLAUDE_CODE_OAUTH_TOKEN)" = "$TOK" ] && ok "second paste accepted" || bad "second paste accepted"

echo "W2: login option leaves no token and warns about 2+ personas"
d3="$(sandbox)"
run_setup "$d3" 1 2 boss "$BOT" 1 1
[ -z "$(envval "$d3" CLAUDE_CODE_OAUTH_TOKEN)" ] && ok "no token written" || bad "no token written"
grep -q "works for one persona" "$d3/.out" && ok "single-persona warning shown" || bad "single-persona warning shown"

echo "W2: switching to an API key clears a stale token"
run_setup "$d" 2 "sk-ant-api03-KEY" boss "" 1 1
[ -z "$(envval "$d" CLAUDE_CODE_OAUTH_TOKEN)" ] && ok "token cleared" || bad "token cleared"

echo "W11: re-running setup keeps every persona already in .env"
BOT2="654321:AAFAKESECONDTOKEN"
d4="$(sandbox)"
# add a builder agent named 'helper' (archetype menu: builder=1 planning=2 Add-ons=3 Done=4)
run_setup "$d4" 1 1 "$TOK" boss "$BOT" 2 1 helper "$BOT2" 4 1
[ "$(envval "$d4" TROUPELY_PERSONAS)" = "boss,helper" ] && ok "first run roster boss,helper" || bad "first run roster ($(envval "$d4" TROUPELY_PERSONAS))"
cat "$d4/.out" > "$d4/.out-first"
run_setup "$d4" 1 1 "" boss "" 1 1
[ "$(envval "$d4" TROUPELY_PERSONAS)" = "boss,helper" ] && ok "re-run with 'just the orchestrator' keeps helper" || bad "re-run keeps helper ($(envval "$d4" TROUPELY_PERSONAS))"
[ "$(envval "$d4" TROUPELY_TG_TOKEN_HELPER)" = "$BOT2" ] && ok "helper's token kept" || bad "helper's token kept"
grep -q "keeping 'helper'" "$d4/.out" && ok "says it kept helper" || bad "says it kept helper"
run_setup "$d4" 1 1 "" boss "" 2 1 helper 4 1
[ "$(envval "$d4" TROUPELY_PERSONAS)" = "boss,helper" ] && ok "re-adding an existing name doesn't duplicate it" || bad "no duplicate ($(envval "$d4" TROUPELY_PERSONAS))"

echo "Core install: the picker offers exactly the core team; add-ons only on request"
d7="$(sandbox)"
BOT3="777777:AAFAKETHIRDTOKEN"; BOT4="888888:AAFAKEFOURTHTOKEN"
# builder=1, planning=2, Add-ons=3, Done=4; add-on menu: executive-assistant=1, specialist=2, back=3
run_setup "$d7" 1 1 "$TOK" boss "$BOT" 2 2 plan "$BOT2" 1 build "$BOT3" 3 2 spec "$BOT4" 4 1
[ "$(envval "$d7" TROUPELY_PERSONAS)" = "boss,plan,build,spec" ] && ok "core three + one add-on in the roster" || bad "roster ($(envval "$d7" TROUPELY_PERSONAS))"
[ -f "$d7/vault/personas/plan/CLAUDE.md" ] && grep -q -- '— Planning' "$d7/vault/personas/plan/CLAUDE.md" && ok "planning persona copied from personas/planning" || bad "planning persona copied"
[ -f "$d7/vault/personas/spec/CLAUDE.md" ] && grep -qi 'specialist' "$d7/vault/personas/spec/CLAUDE.md" && ok "add-on copied from addons/personas/specialist" || bad "add-on copied"
ls "$d7/personas" | sort | tr '\n' ' ' | grep -qx 'README.md builder orchestrator planning ' && ok "personas/ holds exactly the core three" || bad "personas/ contents: $(ls "$d7/personas" | tr '\n' ' ')"
pick="$(sed -n '/^Add an agent/,/^  [0-9]*) ✓ Done/p' "$d7/.out" | head -5 | sed -n 's/^  [0-9]*) //p' | tr '\n' '|')"
[ "$pick" = "builder|planning|Add-on archetypes…|✓ Done|" ] && ok "default picker = builder, planning, Add-ons…, Done" || bad "default picker: $pick"

echo "W11: keys are kept on Enter"
d5="$(sandbox)"
run_setup "$d5" 2 "sk-ant-api03-SECRETKEY" boss "$BOT" 1 1
[ "$(envval "$d5" ANTHROPIC_API_KEY)" = "sk-ant-api03-SECRETKEY" ] && ok "API key written" || bad "API key written"
run_setup "$d5" 2 "" boss "" 1 1
[ "$(envval "$d5" ANTHROPIC_API_KEY)" = "sk-ant-api03-SECRETKEY" ] && ok "Enter keeps the API key" || bad "Enter keeps the API key"

# Echo is the TERMINAL's doing, so a pipe can't show it: drive setup through a real pty
# (`script`) and read the transcript. Number keys pick menu items without Enter on a TTY.
echo "W11: no secret is echoed on a real terminal (pty)"
d6="$(sandbox)"
pty_run(){ # BSD vs util-linux argument order
  if script --version >/dev/null 2>&1; then script -q -c ./setup.sh "$1/.typescript"; else script -q "$1/.typescript" ./setup.sh; fi
}
( sleep 1; printf 1; sleep .4; printf 1; sleep .4; printf '%s\n' "$TOK"; sleep .4; printf 'boss\n'
  sleep .4; printf '%s\n' "$BOT"; sleep 1; printf 1; sleep .4; printf 1; sleep 1 ) \
  | (cd "$d6" && PATH="$d6/.fakebin:$PATH" TROUPELY_NATIVE=0 pty_run "$d6" >/dev/null 2>&1)
[ "$(envval "$d6" CLAUDE_CODE_OAUTH_TOKEN)" = "$TOK" ] && ok "pty run reached .env" || bad "pty run reached .env (input misaligned?)"
grep -aqE "$TOK|$BOT" "$d6/.typescript" && bad "secrets on the terminal" || ok "no token or bot token on the terminal"

rm -rf "$d" "$d2" "$d3" "$d4" "$d5" "$d6"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
