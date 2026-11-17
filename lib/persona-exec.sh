#!/usr/bin/env bash
# Start one persona's process with a scrubbed environment (W3).
#
#   persona-exec.sh <persona-home> <command> [args...]
#
# tmux sessions inherit the tmux server's environment, and the server was started from a
# shell that had the whole .env loaded: every persona's bot token, every key. Without this,
# each persona could read every other persona's bot token with `env`. Here the command gets
# only an allowlist: the basics a terminal needs, tmux's own variables, the troupely paths,
# model auth, and the keys the installed modules declare (modules/*/module.json "env").
# The persona's own bot token is NOT passed either: the Telegram channel server reads it
# from $HOME/.claude/channels/telegram/.env (mode 600), which launch-persona.sh writes.
#
# Config is read FRESH from $TROUPELY_ENV_FILE when it is readable: the tmux server's copy
# is frozen at the moment the server started, so a rotated key or a deleted line would
# otherwise never reach a restarted persona.
#
# This hides tokens from env dumps and tool output. It is not a security boundary between
# personas: they share a uid and can read each other's files.
set -euo pipefail

phome="${1:?usage: persona-exec.sh <persona-home> <command> [args...]}"; shift
[ $# -gt 0 ] || { echo "persona-exec.sh: no command" >&2; exit 2; }

keep_exact=" PATH TERM COLORTERM LANG LC_ALL LC_CTYPE TZ TMPDIR USER LOGNAME SHELL
  TMUX TMUX_PANE
  TROUPELY_VAULT TROUPELY_REPO TROUPELY_ENV_FILE TELEGRAM_TOPIC_FILTER
  HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy
  NODE_EXTRA_CA_CERTS SSL_CERT_FILE "
keep_prefix='^(ANTHROPIC_|CLAUDE_CODE_|AWS_|CLOUD_ML_|GOOGLE_|VERTEX_|API_TIMEOUT)'

# Keys declared by modules, plus any extras the operator lists in TROUPELY_PASS_ENV.
moddir="${TROUPELY_REPO:-/run/troupely/host}/modules"
module_keys() {
  [ -d "$moddir" ] || return 0
  python3 - "$moddir" <<'PY' 2>/dev/null || true
import glob, json, os, re, sys
for f in glob.glob(os.path.join(sys.argv[1], "*", "module.json")):
    try:
        for e in json.load(open(f)).get("env") or []:
            k = e.get("key", "")
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k):
                print(k)
    except Exception:
        pass
PY
}
config_keys() {   # what a fresh .env read may set or clear
  printf '%s\n' "${TROUPELY_PASS_ENV:-}" | tr ',' '\n' | sed 's/[[:space:]]//g'
  module_keys
}

envfile="${TROUPELY_ENV_FILE:-}"
if [ -n "$envfile" ] && [ -r "$envfile" ]; then
  # Drop every inherited config value first, so a line deleted from .env stays deleted.
  while IFS= read -r v; do
    [[ "$v" =~ $keep_prefix || "$v" == TROUPELY_PASS_ENV ]] && unset "$v"
  done < <(compgen -e)
  while IFS= read -r v; do [ -n "$v" ] && unset "$v"; done < <(config_keys)
  set -a
  # shellcheck source=/dev/null
  . "$envfile"
  set +a
fi

extra=" $(config_keys | tr '\n' ' ') "
keep_exact=" $(echo $keep_exact) "   # one space between names, padded both ends

args=("HOME=$phome")
while IFS= read -r v; do
  case "$v" in TROUPELY_TG_TOKEN_*|TELEGRAM_BOT_TOKEN) continue;; esac
  if [[ "$keep_exact" == *" $v "* || "$extra" == *" $v "* || "$v" =~ $keep_prefix ]]; then
    args+=("$v=${!v}")
  fi
done < <(compgen -e)

exec env -i "${args[@]}" "$@"
