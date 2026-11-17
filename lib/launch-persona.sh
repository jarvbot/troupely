#!/usr/bin/env bash
# Launch ONE persona as a detached tmux session `troupely-<name>`.
#
# Shared by the Docker entrypoint, native ./troupely.sh start, and `add` (via docker exec),
# so a persona starts the same way everywhere.
#
#   VAULT_DIR=/vault launch-persona.sh <name>
#
# Reads from the environment:
#   TROUPELY_TG_TOKEN_<NAME>   the persona's bot token (NAME uppercased, - → _). Required.
#   TROUPELY_TG_TOPIC_<NAME>   optional forum-topic id; with TROUPELY_TG_GROUP, routes the
#                              bot to that topic only.
#   TROUPELY_HEARTBEAT         heartbeat interval (e.g. 30m, 2h; default 30m) or "off".
# Exit: 0 launched · 3 already running · 4 no token · 1 other error.
set -euo pipefail

p="${1:?usage: launch-persona.sh <persona>}"
# Everything below is pasted into a tmux shell command, so the inputs are checked here,
# at the sink, not just where they were typed in.
[[ "$p" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "  ✗ invalid persona name: $p" >&2; exit 1; }
VAULT_DIR="${VAULT_DIR:?VAULT_DIR must be set}"
PERSONA_ROOT="$VAULT_DIR/personas"
HERE="$(cd "$(dirname "$0")" && pwd)"
unset TELEGRAM_STATE_DIR   # per-persona HOME below; never inherit a global override

# `=` makes tmux match the name exactly; a bare -t also matches prefixes, so a running
# troupely-alpha-long would read as troupely-alpha.
if tmux has-session -t "=troupely-$p" 2>/dev/null; then
  echo "  • $p already running (troupely-$p)"; exit 3
fi

up="$(printf '%s' "$p" | tr '[:lower:]-' '[:upper:]_')"
tok_var="TROUPELY_TG_TOKEN_$up"
token="${!tok_var:-}"
if [ -z "$token" ]; then
  echo "  ⚠ $p: no $tok_var set — skipping (mint a bot with @BotFather and set its token)." >&2
  exit 4
fi

pdir="$PERSONA_ROOT/$p"
[ -d "$pdir" ] || pdir="$VAULT_DIR"   # no persona dir yet → run from the vault root
python3 "$HERE/seed_onboarding.py" "$VAULT_DIR" "$pdir" >/dev/null

# Per-persona HOME, not a per-persona TELEGRAM_STATE_DIR. The /telegram:access skill
# hardcodes ~/.claude/channels/telegram/access.json and IGNORES TELEGRAM_STATE_DIR (only
# the channel server honours it), so with a shared HOME the skill writes one path, the
# server reads another, and pairing approvals never land. A HOME per persona makes both
# resolve to the same path. Auth, plugins, settings and skills stay shared via symlinks.
phome="$VAULT_DIR/.claude/homes/$p"
state_dir="$phome/.claude/channels/telegram"
mkdir -p "$state_dir" "$VAULT_DIR/.claude/skills"
ln -sfn "$VAULT_DIR/.claude/plugins"           "$phome/.claude/plugins"
# Auth. Preferred: CLAUDE_CODE_OAUTH_TOKEN (long-lived, from `claude setup-token`), shared by
# every persona through the environment, with no credentials file to fight over. The fallback
# symlinks one shared .credentials.json, which only holds for a single persona: Claude Code
# refreshes OAuth by writing a new file over the symlink, which rotates the refresh token and
# leaves every other persona holding a dead one (verified 2026-10-11).
# macOS native: the login Keychain is found via $HOME/Library/Keychains, so link the
# operator's real one in. All personas then share one Keychain item (no copy to go stale).
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  [ -L "$phome/.claude/.credentials.json" ] && rm -f "$phome/.claude/.credentials.json"
elif [ "$(uname)" = "Darwin" ] && [ -d "${TROUPELY_USER_HOME:-/nonexistent}/Library/Keychains" ]; then
  mkdir -p "$phome/Library"
  ln -sfn "$TROUPELY_USER_HOME/Library/Keychains" "$phome/Library/Keychains"
  [ -L "$phome/.claude/.credentials.json" ] && rm -f "$phome/.claude/.credentials.json"
elif [ -f "$VAULT_DIR/.claude/.credentials.json" ]; then
  ln -sf "$VAULT_DIR/.claude/.credentials.json" "$phome/.claude/.credentials.json"
fi
ln -sf  "$VAULT_DIR/.claude.json"              "$phome/.claude.json"
ln -sf  "$VAULT_DIR/.claude/settings.json"     "$phome/.claude/settings.json"
if [ -L "$phome/.claude/skills" ] || [ ! -e "$phome/.claude/skills" ]; then
  ln -sfn "$VAULT_DIR/.claude/skills" "$phome/.claude/skills"
fi
printf 'TELEGRAM_BOT_TOKEN=%s\n' "$token" > "$state_dir/.env"
chmod 600 "$state_dir/.env"

topic_var="TROUPELY_TG_TOPIC_$up"
topic="${!topic_var:-}"
if [ -n "$topic" ] && ! [[ "$topic" =~ ^[0-9]+$ ]]; then
  echo "  ✗ $p: $topic_var must be a number, got '$topic'. Fix .env (./troupely.sh topic)." >&2
  exit 1
fi
if [ -n "$topic" ]; then
  # Groups are off by default in access.json. Opt the supergroup in for the people
  # paired in DMs only: an empty group allowFrom means "anyone in the group".
  if [ -n "${TROUPELY_TG_GROUP:-}" ]; then
    python3 "$HERE/group-access.py" "$state_dir" "$TROUPELY_TG_GROUP" || true
  fi
elif [ -n "${TROUPELY_TG_GROUP:-}" ] && [ -f "$state_dir/access.json" ]; then
  # No topic: drop any entry left from an earlier topic route, or the bot would
  # answer every topic in the group with no filter.
  python3 "$HERE/group-access.py" "$state_dir" "$TROUPELY_TG_GROUP" --close >/dev/null || true
fi

# The .env the persona re-reads at start (persona-exec.sh): the checkout's in native mode,
# the read-only host mount in Docker.
envf="${TROUPELY_ENV_FILE:-}"
if [ -z "$envf" ]; then
  if [ -n "${TROUPELY_REPO:-}" ] && [ -f "$TROUPELY_REPO/.env" ]; then envf="$TROUPELY_REPO/.env"
  elif [ -r /run/troupely/host/.env ]; then envf=/run/troupely/host/.env; fi
fi

# Heartbeat (W9). A session's /loop dies with its process, so every launch arms it again:
# the persona starts with "/loop <interval> <tick prompt>" as its first message, which runs
# one tick now (the re-orient) and schedules the rest. Claude Code expires recurring jobs
# after 7 days, so the tick renews the job once the marker below is 6 days old.
# The current .env wins over the inherited environment (which can be the container's
# create-time copy), read the way every other path reads it: sourced. A deleted line means
# the default again.
if [ -n "$envf" ] && [ -r "$envf" ]; then
  # shellcheck source=/dev/null
  hb="$(unset TROUPELY_HEARTBEAT; set -a; . "$envf" >/dev/null 2>&1; printf '%s' "${TROUPELY_HEARTBEAT:-}")"
else
  hb="${TROUPELY_HEARTBEAT:-}"
fi
hb="${hb:-30m}"
if ! [[ "$hb" =~ ^([1-9][0-9]*[mh]|off)$ ]]; then
  echo "  ✗ $p: TROUPELY_HEARTBEAT must look like 30m or 2h, or be off; got '$hb'." >&2
  exit 1
fi
first=()
if [ "$hb" != off ]; then
  marker="$phome/.troupely-heartbeat-armed"
  : > "$marker"
  first=("/loop $hb Heartbeat tick: run the Heartbeat section of your CLAUDE.md. Then, because Claude Code expires recurring jobs after 7 days: if $marker is more than 6 days old, delete this heartbeat job, create it again with the same interval and this same prompt, and touch that file.")
fi

# Command as separate arguments, not a shell string: tmux then execs it directly, so no
# path, name or value is ever parsed by a shell. persona-exec.sh scrubs the environment:
# the tmux server holds every persona's token (W3).
targs=(-c "$pdir" -e "TROUPELY_VAULT=$VAULT_DIR" -e "TROUPELY_REPO=${TROUPELY_REPO:-}" -e "TROUPELY_ENV_FILE=$envf")
[ -n "$topic" ] && targs+=(-e "TELEGRAM_TOPIC_FILTER=$topic")
tmux new-session -d -s "troupely-$p" "${targs[@]}" \
  "$HERE/persona-exec.sh" "$phome" claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official \
  -- ${first[@]+"${first[@]}"}
# `--` is required: --channels takes a variable number of values, so without it the prompt
# is read as one more channel and Claude Code exits ("--channels entries must be tagged").
echo "  ✓ $p → tmux session troupely-$p (cwd $pdir)${topic:+ (topic $topic)}, heartbeat $hb"
