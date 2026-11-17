#!/usr/bin/env bash
# shellcheck disable=SC2034  # check() takes its condition as a string, so uses are invisible
# W3: a persona's process must not see other personas' bot tokens (or its own, which lives
# in its 600 channel .env), and must still get model auth and the troupely paths.
# Runs launch-persona.sh for real against a private tmux server and a fake `claude` that
# dumps its environment. No network, no real claude.
#   bash tests/test_secret_isolation.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

d="$(mktemp -d)"
export TMUX_TMPDIR="$d/tmux"; mkdir -p "$TMUX_TMPDIR"; unset TMUX
mkdir -p "$d/bin" "$d/vault/personas/alpha"
cat > "$d/bin/claude" <<EOF
#!/bin/sh
env > "$d/env.out"
printf '%s\n' "\$@" > "$d/args.out"
EOF
chmod +x "$d/bin/claude"

echo "W3: launch-persona.sh scrubs the persona environment"
(
  export PATH="$d/bin:$PATH" VAULT_DIR="$d/vault" TROUPELY_REPO="$REPO"
  export TROUPELY_TG_TOKEN_ALPHA="111:ALPHASECRET" TROUPELY_TG_TOKEN_BETA="222:BETASECRET"
  export TELEGRAM_BOT_TOKEN="333:STRAY" UNRELATED_SECRET="hunter2"
  export CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-MODELAUTH" ANTHROPIC_BASE_URL="https://example.invalid"
  tmux start-server \; set-option -g exit-empty off >/dev/null 2>&1 || true
  "$REPO/lib/launch-persona.sh" alpha >/dev/null
)
for _ in $(seq 50); do [ -s "$d/env.out" ] && break; sleep 0.1; done
if [ ! -s "$d/env.out" ]; then
  bad "fake claude ran (no env dump)"
else
  ok "fake claude ran"
  for s in BETASECRET ALPHASECRET STRAY hunter2; do
    grep -q "$s" "$d/env.out" && bad "env hides $s" || ok "env hides $s"
  done
  grep -q '^CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-MODELAUTH$' "$d/env.out" && ok "model auth kept" || bad "model auth kept"
  grep -q '^ANTHROPIC_BASE_URL=https://example.invalid$' "$d/env.out" && ok "ANTHROPIC_* kept" || bad "ANTHROPIC_* kept"
  grep -q "^HOME=$d/vault/.claude/homes/alpha$" "$d/env.out" && ok "per-persona HOME" || bad "per-persona HOME"
  grep -q "^TROUPELY_VAULT=$d/vault$" "$d/env.out" && ok "TROUPELY_VAULT kept" || bad "TROUPELY_VAULT kept"
  grep -q '^PATH=' "$d/env.out" && ok "PATH kept" || bad "PATH kept"
  grep -q -- '--channels' "$d/args.out" && ok "claude args passed through" || bad "claude args passed through"
fi
envf="$d/vault/.claude/homes/alpha/.claude/channels/telegram/.env"
grep -q '^TELEGRAM_BOT_TOKEN=111:ALPHASECRET$' "$envf" && ok "own token in channel .env" || bad "own token in channel .env"
[ "$(stat -c %a "$envf" 2>/dev/null || stat -f %Lp "$envf")" = 600 ] && ok "channel .env is 600" || bad "channel .env is 600"

echo "W3: topic filter still reaches the persona"
rm -f "$d/env.out"
(
  export PATH="$d/bin:$PATH" VAULT_DIR="$d/vault" TROUPELY_TG_TOKEN_ALPHA="111:ALPHASECRET" TROUPELY_TG_TOPIC_ALPHA=42
  tmux kill-session -t troupely-alpha 2>/dev/null || true
  "$REPO/lib/launch-persona.sh" alpha >/dev/null
)
for _ in $(seq 50); do [ -s "$d/env.out" ] && break; sleep 0.1; done
grep -q '^TELEGRAM_TOPIC_FILTER=42$' "$d/env.out" 2>/dev/null && ok "TELEGRAM_TOPIC_FILTER kept" || bad "TELEGRAM_TOPIC_FILTER kept"

tmux kill-server 2>/dev/null || true
rm -rf "$d"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
