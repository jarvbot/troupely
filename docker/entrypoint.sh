#!/usr/bin/env bash
# troupely container entrypoint — launches N personas as N tmux sessions.
#
# Topology A (lean default): one container, one tmux session per persona, each
# with its OWN Telegram bot token + its OWN HOME (vault/.claude/homes/<persona>),
# so bot state + the /telegram:access skill stay aligned per persona and don't
# collide. Generalized + extended from a single-persona substrate.
#
# Attach to a persona from the host:
#     docker exec -it troupely tmux attach -t troupely-<persona>   (Ctrl-b d to detach)
#
# Roster resolution (first that's set wins):
#   1. $TROUPELY_PERSONAS                 — comma list, e.g. "jarvis,atlas,friday"
#   2. /vault/troupely-roster.json        — JSON array of names OR objects {"name":...}
#   3. the persona dirs under /vault/personas/
# Per persona <p>, its bot token comes from env $TROUPELY_TG_TOKEN_<P>  (P uppercased).
set -euo pipefail

# ---- never crash-loop: any unexpected failure holds the container UP so the
# operator can `docker exec` in and read the logs, instead of Docker's
# `restart: unless-stopped` bouncing it (which makes `docker exec` impossible —
# "Container is restarting, wait until the container is running"). ----
on_err() {
  rc=$?
  echo "" >&2
  echo "✗ troupely entrypoint hit an error (exit $rc, near line ${BASH_LINENO[0]:-?})." >&2
  echo "  Holding the container UP so you can inspect instead of crash-looping:" >&2
  echo "    docker exec -it troupely bash      # then: ls -la /vault" >&2
  echo "    docker compose logs --tail=40      # the error is above this banner" >&2
  exec sleep infinity
}
trap on_err ERR

VAULT_DIR="${VAULT_DIR:-/vault}"
PERSONA_ROOT="$VAULT_DIR/personas"
unset TELEGRAM_STATE_DIR   # per-session below; never inherit a global override

mkdir -p "$VAULT_DIR/.claude" 2>/dev/null || true

# ---- vault writability preflight (the #1 Linux footgun) ----
# The bind-mounted ./vault must be writable by THIS container's uid. If a
# prior `sudo docker compose up` (or a root-owned checkout) created vault subdirs
# as root, an unprivileged container (HOST_UID:HOST_GID) can't write → every file
# op fails under `set -e`. Catch it here with an actionable message instead of a
# cryptic mid-script death. (macOS Docker Desktop virtualizes bind-mount perms so
# this only ever bites on Linux — which is exactly why it slips past Mac testing.)
if ! touch "$VAULT_DIR/.claude/.write-test" 2>/dev/null; then
  cat >&2 <<EOF

✗ /vault is not writable by this container (running as uid $(id -u), gid $(id -g)).
  The bind-mounted vault is owned by a different user — usually from an earlier
  \`sudo docker …\` run that created files as root. On the HOST, from the repo root:

      sudo chown -R \$(id -u):\$(id -g) vault
      docker compose up -d --build

  (Or set HOST_UID / HOST_GID in .env to match whoever owns ./vault.)
EOF
  exec sleep infinity   # hold, don't crash-loop
fi
rm -f "$VAULT_DIR/.claude/.write-test"

# ---- shared payload → vault (this entrypoint is the only writer) ----
# RULES.md, MEMORY-SYSTEM.md, framework/, skills/, the memory linter. RULES.md is always
# refreshed; CLAUDE.md is seeded once from a template and then belongs to the user.
python3 /usr/local/lib/troupely/lib/payload_sync.py /opt/troupely/payload "$VAULT_DIR" \
  || echo "  ⚠ payload sync failed — personas may be missing the shared rules (see above)." >&2

# ---- host .env (W4) ----
# PID 1 stays alive and, every TROUPELY_SUPERVISE_SECS, relaunches any roster persona whose
# session is gone (crash, /exit, OOM). It re-reads the host .env through the read-only repo
# mount each pass, so a persona added with `./troupely.sh add` survives a container restart
# (the env_file copy is frozen at container create). Directory mount, not a file mount:
# envfile.py rewrites .env by rename, which a single-file bind mount would never see.
HOST_ENV=/run/troupely/host/.env
reload_env() {
  [ -r "$HOST_ENV" ] || return 0
  # Replace, don't overlay: drop every value .env manages before re-reading it, so a line
  # deleted from .env (a token, a topic, a key) stops applying. Sourcing alone keeps the old.
  local v
  while IFS= read -r v; do
    case "$v" in TROUPELY_PERSONAS|TROUPELY_TG_*|TROUPELY_PASS_ENV|TROUPELY_HEARTBEAT|ANTHROPIC_*|CLAUDE_CODE_*) unset "$v";; esac
  done < <(compgen -e)
  set -a
  # shellcheck source=/dev/null
  . "$HOST_ENV" || echo "  ⚠ couldn't read $HOST_ENV — keeping the previous values." >&2; set +a
  unset TELEGRAM_STATE_DIR
}
reload_env

# ---- auth guard: subscription creds OR a provider key must be present ----
have_provider_key() { [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] || [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; }

if [ ! -f "$VAULT_DIR/.claude/.credentials.json" ] && ! have_provider_key; then
  cat >&2 <<'EOF'
✗ No Claude auth found. Pick ONE:
  • Subscription (recommended):  run `claude setup-token` anywhere, put the token in the
    host .env as CLAUDE_CODE_OAUTH_TOKEN='sk-ant-oat01-…', then: ./troupely.sh restart
  • Subscription, ONE persona only:  ./troupely.sh login
  • Provider key (headless):  set ANTHROPIC_API_KEY (or ANTHROPIC_AUTH_TOKEN +
    ANTHROPIC_BASE_URL for OpenRouter; remember ANTHROPIC_API_KEY="" empty-not-unset)
    in the host .env, then: docker compose up -d
EOF
  exec sleep infinity   # don't crash-loop; let the operator fix + restart
fi

# ---- resolve the roster ----
resolve_roster() {
  # Set-but-empty = no personas (after `remove` of the last one); only UNSET falls back.
  if [ -n "${TROUPELY_PERSONAS+x}" ]; then
    echo "$TROUPELY_PERSONAS" | tr ',' '\n' | sed 's/[[:space:]]//g'
  elif [ -f "$VAULT_DIR/troupely-roster.json" ]; then
    # names from a JSON array of strings OR objects with a "name" key (jq-free)
    grep -oE '"[A-Za-z0-9_-]+"' "$VAULT_DIR/troupely-roster.json" | tr -d '"' \
      | grep -vE '^(name)$'
  elif [ -d "$PERSONA_ROOT" ]; then
    find "$PERSONA_ROOT" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
  fi
}

mapfile -t ROSTER < <(resolve_roster | awk 'NF' | sort -u)
if [ "${#ROSTER[@]}" -eq 0 ]; then
  # Don't stop here: the supervisor below keeps re-reading .env, so a persona added later
  # (./troupely.sh add) is picked up and kept alive.
  echo "⚠ No personas yet (set TROUPELY_PERSONAS, or ./troupely.sh add). Supervising anyway." >&2
fi

# ---- first-boot prep: silence the claude self-path nag + install the channel plugin ----
# Claude Code (HOME=/vault) looks for itself at $HOME/.local/bin/claude; we put the
# binary at /usr/local/bin so a non-root user can run it. Symlink to quiet the warning.
mkdir -p "$VAULT_DIR/.local/bin"
ln -sf /usr/local/bin/claude "$VAULT_DIR/.local/bin/claude" 2>/dev/null || true

# The Telegram channel plugin isn't in the base image (anything baked into /vault at
# build time is masked by the runtime bind-mount), so install it on first boot into
# the persisted vault. Idempotent — a no-op once it's there. The official marketplace
# is normally auto-configured during claude's interactive startup, which we bypass —
# so on a fresh vault we must add it explicitly before the plugin resolves.
if ! claude plugin list 2>/dev/null | grep -q "telegram@claude-plugins-official"; then
  echo "▶ installing telegram channel plugin (first boot)…"
  if ! claude plugin marketplace list 2>/dev/null | grep -q "claude-plugins-official"; then
    claude plugin marketplace add anthropics/claude-plugins-official 2>&1 | tail -1 \
      || echo "  ⚠ couldn't add the official plugin marketplace (network?)." >&2
  fi
  claude plugin install telegram@claude-plugins-official 2>&1 | tail -1 \
    || echo "  ⚠ plugin install failed (network?) — the telegram channel won't load until it succeeds." >&2
fi

# teach the plugin TELEGRAM_TOPIC_FILTER (public plugin lacks it). Idempotent +
# safe: no-op if already supported or anchor missing. Required for topic routing.
TOPIC_PATCH="/usr/local/lib/troupely/plugin-patch/apply-topic-patch.py"
[ -f "$TOPIC_PATCH" ] && python3 "$TOPIC_PATCH" \
  "$VAULT_DIR/.claude/plugins/cache/claude-plugins-official/telegram" || true

# ---- seed Claude Code's first-run flags so a fresh container boots straight into the
# channel session instead of the interactive onboarding wizard (see lib/seed_onboarding.py).
python3 /usr/local/lib/troupely/lib/seed_onboarding.py "$VAULT_DIR" \
  || echo "  ⚠ onboarding-seed failed (python3 error)" >&2

echo "▶ troupely launching ${#ROSTER[@]} persona(s): ${ROSTER[*]}"
echo "  claude: $(claude --version 2>&1 | head -1)  |  bun: $(bun --version 2>&1 | head -1)"

# ---- supervise (W4): launch_all runs once at boot, then every TROUPELY_SUPERVISE_SECS ----
launch_all() {   # $1 = quiet → only report relaunches
  local p rc started=0 running=0
  mapfile -t ROSTER < <(resolve_roster | awk 'NF' | sort -u)
  for p in "${ROSTER[@]}"; do
    rc=0; out="$(VAULT_DIR="$VAULT_DIR" /usr/local/lib/troupely/lib/launch-persona.sh "$p" 2>&1)" || rc=$?
    case "$rc" in
      0) started=$((started + 1)); [ "${1:-}" = quiet ] && echo "▶ $(date -u +%FT%TZ) started $p (session was missing)";;
      3) running=$((running + 1));;
    esac
    [ "${1:-}" = quiet ] && [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ] && [ "$rc" -ne 4 ] && printf '%s\n' "$out" >&2
    [ "${1:-}" = quiet ] || { [ -n "$out" ] && printf '%s\n' "$out"; }
  done
  LIVE=$((started + running))
}

launch_all
if [ "$LIVE" -eq 0 ] && [ "${#ROSTER[@]}" -gt 0 ]; then
  echo "✗ No personas had a bot token — nothing launched. Set TROUPELY_TG_TOKEN_<PERSONA> vars." >&2
  echo "  The supervisor keeps checking: fix .env on the host and they start within ${TROUPELY_SUPERVISE_SECS:-60}s." >&2
elif [ "$LIVE" -gt 0 ]; then
  echo "▶ ${LIVE} persona session(s) live. Attach: docker exec -it troupely tmux attach -t troupely-<name>"
fi

# One persona failing must never stop supervision of the rest, so no errexit/ERR trap here.
trap - ERR; set +e
# Same lock as troupely.sh's lifecycle commands (shared through the vault mount), so a pass
# never races `remove`/`restart` on the host. Busy → skip this pass. Stale after 300s.
LOCK="$VAULT_DIR/.claude/troupely.lock"
lock_stale() { local m; m="$(stat -c %Y "$LOCK" 2>/dev/null)" || return 1; [ $(( $(date +%s) - m )) -gt 300 ]; }
reconcile_stop() {   # stop sessions dropped from an explicit roster
  [ -n "${TROUPELY_PERSONAS+x}" ] || return 0
  local s n
  while IFS= read -r s; do
    n="${s#troupely-}"
    case ",$(printf '%s' "$TROUPELY_PERSONAS" | tr -d '[:space:]')," in *",$n,"*) ;;
      *) tmux kill-session -t "=$s" 2>/dev/null && echo "▶ $(date -u +%FT%TZ) stopped $n (no longer in the roster)";;
    esac
  done < <(tmux ls -F '#{session_name}' 2>/dev/null | grep -E '^troupely-' || true)
}
while sleep "${TROUPELY_SUPERVISE_SECS:-60}"; do
  if ! mkdir "$LOCK" 2>/dev/null; then
    lock_stale && rmdir "$LOCK" 2>/dev/null
    continue
  fi
  reload_env
  reconcile_stop
  launch_all quiet
  rmdir "$LOCK" 2>/dev/null
done
