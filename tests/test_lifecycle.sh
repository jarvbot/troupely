#!/usr/bin/env bash
# shellcheck disable=SC2034  # check() takes its condition as a string, so uses are invisible
# W5/W6: restart <name>, update, remove, uninstall, in native mode, in a throwaway copy.
# A fake HOME carries a fake `claude` (troupely.sh puts $HOME/.local/bin first on PATH),
# and tmux runs on a private server, so nothing touches the real stack.
#   bash tests/test_lifecycle.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"
export TMUX_TMPDIR="$T/tmux"; mkdir -p "$TMUX_TMPDIR"; unset TMUX
export HOME="$T/home"; mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/claude" <<'EOF'
#!/bin/sh
case "$1" in --version) echo "fake 0.0";; plugin) echo "telegram@claude-plugins-official";;
  *) env > "$TROUPELY_VAULT/env-$(basename "$PWD").out"
     # Parse like Claude Code: --channels takes values until the next option or `--`, and
     # every value must be tagged; the first positional after `--` is the initial prompt.
     prompt=""; in_ch=0; past=0
     for a in "$@"; do
       if [ "$past" = 1 ]; then [ -z "$prompt" ] && prompt="$a"; continue; fi
       case "$a" in
         --) past=1; in_ch=0 ;;
         --channels) in_ch=1 ;;
         -*) in_ch=0 ;;
         *) if [ "$in_ch" = 1 ]; then case "$a" in plugin:*|server:*) ;; *)
              echo "--channels entries must be tagged: $a" > "$TROUPELY_VAULT/err-$(basename "$PWD").out"; exit 1;; esac
            else [ -z "$prompt" ] && prompt="$a"; fi ;;
       esac
     done
     printf '%s\n' "$prompt" > "$TROUPELY_VAULT/args-$(basename "$PWD").out"; exec sleep 3600;; esac
EOF
chmod +x "$HOME/.local/bin/claude"

# origin = a bare repo seeded from this checkout's tracked files; S = the install
git init -q --bare -b main "$T/origin.git"
mkdir "$T/seed"; (cd "$REPO" && git ls-files -co --exclude-standard -z | grep -zv '^vault/' | xargs -0 tar cf -) | (cd "$T/seed" && tar xf -)
(cd "$T/seed" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm seed && git push -q "$T/origin.git" main)
git clone -q "$T/origin.git" "$T/S"; S="$T/S"
cat > "$S/.env" <<'EOF'
TROUPELY_MODE='native'
TROUPELY_PERSONAS='alpha,beta'
TROUPELY_TG_TOKEN_ALPHA='111:AAAfake'
TROUPELY_TG_TOKEN_BETA='222:BBBfake'
TROUPELY_TG_TOPIC_BETA='7'
CLAUDE_CODE_OAUTH_TOKEN='sk-ant-oat01-fake'
EOF
mkdir -p "$S/vault/personas/alpha" "$S/vault/personas/beta"
ts(){ tmux ls -F '#{session_name} #{session_created}' 2>/dev/null | awk -v s="troupely-$1" '$1==s{print $2}'; }

(cd "$S" && ./troupely.sh start >/dev/null 2>&1)
check "start launches both" '[ -n "$(ts alpha)" ] && [ -n "$(ts beta)" ]'

echo "native restart (all) comes back up"
a0="$(ts alpha)"; sleep 1.1
(cd "$S" && ./troupely.sh restart >/dev/null 2>&1); check "restart exits 0" '[ $? -eq 0 ]'
check "both back after restart" '[ -n "$(ts alpha)" ] && [ -n "$(ts beta)" ] && [ "$(ts alpha)" != "$a0" ]'
(cd "$S" && ./troupely.sh stop >/dev/null 2>&1); check "stop exits 0 after stopping sessions" '[ $? -eq 0 ] && [ -z "$(ts alpha)" ]'
(cd "$S" && ./troupely.sh start >/dev/null 2>&1)

echo "W5: restart <name> restarts only that persona"
a0="$(ts alpha)"; b0="$(tmux list-panes -t troupely-beta -F '#{pane_pid}')"; sleep 1.1
(cd "$S" && ./troupely.sh restart alpha >/dev/null 2>&1)
check "alpha is back" '[ -n "$(ts alpha)" ]'
check "alpha is a new session" '[ "$(ts alpha)" != "$a0" ]'
check "beta untouched" '[ "$(tmux list-panes -t troupely-beta -F "#{pane_pid}")" = "$b0" ]'
(cd "$S" && ./troupely.sh restart 'x;y' >/dev/null 2>&1); check "bad name refused" '[ $? -ne 0 ]'

echo "review fixes: exact targets, self-restart, fresh .env, module keys"
mkdir -p "$S/vault/personas/alpha-long"
(cd "$S" && python3 lib/envfile.py .env "TROUPELY_PERSONAS=alpha,beta,alpha-long" "TROUPELY_TG_TOKEN_ALPHA_LONG=333:CCCfake" && ./troupely.sh start >/dev/null 2>&1)
tmux kill-session -t "=troupely-alpha"
check "only alpha-long left of the alphas" '[ -z "$(ts alpha)" ] && [ -n "$(ts alpha-long)" ]'
l0="$(ts alpha-long)"
(cd "$S" && ./troupely.sh restart alpha >/dev/null 2>&1)
check "restart alpha starts alpha, not a prefix match" '[ -n "$(ts alpha)" ]'
check "alpha-long untouched by restart alpha" '[ "$(ts alpha-long)" = "$l0" ]'
(cd "$S" && ./troupely.sh remove alpha-long >/dev/null 2>&1)
check "alpha survives remove alpha-long" '[ -n "$(ts alpha)" ]'

(cd "$S" && python3 lib/envfile.py .env "CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-ROTATED" "COINGECKO_API_KEY=cg-key" "ANTHROPIC_BASE_URL=https://x.invalid")
(cd "$S" && ./troupely.sh restart alpha >/dev/null 2>&1); sleep 0.5
check "restarted persona gets the rotated model token" 'grep -qx "CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-ROTATED" "$S/vault/env-alpha.out"'
check "module-declared key passes the scrub" 'grep -qx "COINGECKO_API_KEY=cg-key" "$S/vault/env-alpha.out"'
check "still no bot tokens in the persona env" '! grep -q "TROUPELY_TG_TOKEN" "$S/vault/env-alpha.out"'
check "TMUX_PANE kept for self-restart" 'grep -q "^TMUX_PANE=" "$S/vault/env-alpha.out"'
(cd "$S" && python3 lib/envfile.py .env "-ANTHROPIC_BASE_URL" && ./troupely.sh restart alpha >/dev/null 2>&1); sleep 0.5
check "a key deleted from .env is gone after restart" '! grep -q "^ANTHROPIC_BASE_URL=" "$S/vault/env-alpha.out"'

pane="$(tmux list-panes -t "=troupely-alpha:" -F '#{pane_id}')"; a1="$(ts alpha)"; sleep 1.1
(cd "$S" && TMUX="$(tmux display-message -p "#{socket_path}"),1,0" TMUX_PANE="$pane" ./troupely.sh restart alpha >"$T/self.out" 2>&1)
check "self-restart is handed to the tmux server" 'grep -q "in the background" "$T/self.out"'
for _ in $(seq 40); do [ -n "$(ts alpha)" ] && [ "$(ts alpha)" != "$a1" ] && break; sleep 0.25; done
check "self-restarted persona comes back" '[ -n "$(ts alpha)" ] && [ "$(ts alpha)" != "$a1" ]'

echo "W6: remove <name>"
(cd "$S" && ./troupely.sh remove beta >"$T/rm.out" 2>&1)
check "beta session stopped" '[ -z "$(ts beta)" ]'
check "roster drops beta" 'grep -qx "TROUPELY_PERSONAS='"'"'alpha'"'"'" "$S/.env"'
check "beta token + topic gone" '! grep -q "_BETA=" "$S/.env"'
check "alpha token kept" 'grep -q "TROUPELY_TG_TOKEN_ALPHA=" "$S/.env"'
check ".env still 600" '[ "$(stat -c %a "$S/.env" 2>/dev/null || stat -f %Lp "$S/.env")" = 600 ]'
check "persona dir archived" 'ls -d "$S"/vault/.archive/beta-*/persona >/dev/null 2>&1 && [ ! -d "$S/vault/personas/beta" ]'
check "revoke reminder" 'grep -q "/revoke" "$T/rm.out"'
(cd "$S" && ./troupely.sh remove alpha >/dev/null 2>&1); check "removing the last persona works" '[ $? -eq 0 ] && grep -qx "TROUPELY_PERSONAS='"''"'" "$S/.env"'

echo "W6: update"
(cd "$S" && ./troupely.sh update >"$T/up.out" 2>&1); check "no-op update says up to date" 'grep -q "Already up to date" "$T/up.out"'
(cd "$T/seed" && echo "9.9.9" > VERSION && git -c user.email=t@t -c user.name=t commit -qam bump && git push -q "$T/origin.git" main)
(cd "$S" && ./troupely.sh update >"$T/up.out" 2>&1); check "update fast-forwards" '[ "$(cat "$S/VERSION")" = 9.9.9 ]'
echo "local" >> "$S/README.md"
(cd "$S" && ./troupely.sh update >"$T/up.out" 2>&1); check "update refuses with local edits" '[ $? -ne 0 ] && grep -q "local edits" "$T/up.out"'
git -C "$S" checkout -q README.md

echo "W9: heartbeat armed at launch"
(cd "$S" && ./troupely.sh stop >/dev/null 2>&1 || true)
cp "$S/.env" "$T/env.bak"
hbrun(){ cp "$T/env.bak" "$S/.env"; printf "TROUPELY_PERSONAS='alpha'\nTROUPELY_TG_TOKEN_ALPHA='111:AAAfake'\n%s\n" "$1" >> "$S/.env"
  mkdir -p "$S/vault/personas/alpha"; rm -f "$S/vault/args-alpha.out" "$S/vault/.claude/homes/alpha/.troupely-heartbeat-armed"
  (cd "$S" && ./troupely.sh start >"$T/hb.out" 2>&1); for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$S/vault/args-alpha.out" ] && break; sleep 0.2; done; }
hbstop(){ (cd "$S" && ./troupely.sh stop >/dev/null 2>&1 || true); }
hbrun ""
check "default arms /loop 30m as the initial prompt" 'grep -q "^/loop 30m Heartbeat tick" "$S/vault/args-alpha.out" && [ -n "$(ts alpha)" ]'
check "marker written for renewal" '[ -f "$S/vault/.claude/homes/alpha/.troupely-heartbeat-armed" ]'
hbstop; hbrun "TROUPELY_HEARTBEAT='2h'"
check "interval read from .env" 'grep -q "^/loop 2h " "$S/vault/args-alpha.out"'
hbstop; hbrun "TROUPELY_HEARTBEAT=off"
check "off passes no /loop, session still starts" '[ -f "$S/vault/args-alpha.out" ] && ! grep -q "/loop" "$S/vault/args-alpha.out" && [ -n "$(ts alpha)" ]'
hbstop; hbrun "TROUPELY_HEARTBEAT=off # quiet for now"
check "inline comment allowed, as when sourced" '[ -f "$S/vault/args-alpha.out" ] && ! grep -q "/loop" "$S/vault/args-alpha.out"'
hbstop; cp "$T/env.bak" "$S/.env"; printf "TROUPELY_PERSONAS='alpha'\nTROUPELY_TG_TOKEN_ALPHA='111:AAAfake'\n" >> "$S/.env"
mkdir -p "$S/vault/personas/alpha"; rm -f "$S/vault/args-alpha.out"
(cd "$S" && TROUPELY_HEARTBEAT=off ./troupely.sh start >/dev/null 2>&1); for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$S/vault/args-alpha.out" ] && break; sleep 0.2; done
check "line deleted from .env: default even with a stale inherited off" 'grep -q "^/loop 30m " "$S/vault/args-alpha.out"'
hbstop; hbrun "TROUPELY_HEARTBEAT='30 minutes'"
check "bad interval refused, named" 'grep -q "TROUPELY_HEARTBEAT must look like" "$T/hb.out" && [ -z "$(ts alpha)" ]'
hbstop; cp "$T/env.bak" "$S/.env"

echo "stale lock"
mkdir -p "$S/vault/.claude/troupely.lock"; touch -t 202001010000 "$S/vault/.claude/troupely.lock"
(cd "$S" && ./troupely.sh stop >"$T/lock.out" 2>&1); rc=$?
check "a lock older than 5 min is reclaimed" '[ $rc -eq 0 ] && ! grep -q "another troupely command" "$T/lock.out"'
rmdir "$S/vault/.claude/troupely.lock" 2>/dev/null || true

echo "W6: uninstall"
(cd "$S" && ./troupely.sh start >/dev/null 2>&1 || true)
printf 'TROUPELY_PERSONAS='"'"'alpha'"'"'\nTROUPELY_TG_TOKEN_ALPHA='"'"'111:AAAfake'"'"'\n' >> "$S/.env"
(cd "$S" && ./troupely.sh start >/dev/null 2>&1)
mkdir -p "$S/vault/.claude/homes/alpha/Library" && ln -sfn "$T/fake-keychains" "$S/vault/.claude/homes/alpha/Library/Keychains"
(cd "$S" && echo no | ./troupely.sh uninstall >/dev/null 2>&1); check "uninstall needs the confirm word" '[ $? -ne 0 ] && [ -n "$(ts alpha)" ]'
(cd "$S" && ./troupely.sh uninstall --yes >"$T/un.out" 2>&1)
check "uninstall stops sessions" '[ -z "$(ts alpha)" ]'
check "keychain link removed" '[ ! -L "$S/vault/.claude/homes/alpha/Library/Keychains" ]'
check "vault + .env left on disk" '[ -d "$S/vault" ] && [ -f "$S/.env" ]'

tmux kill-server 2>/dev/null || true
rm -rf "$T"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
