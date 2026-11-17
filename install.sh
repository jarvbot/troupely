#!/usr/bin/env bash
# troupely native installer (Linux, no Docker).
#
# Installs the runtime (Claude CLI, bun, tmux + friends) directly on the host,
# walks you through onboarding (provider / personas / Telegram tokens), then
# launches your personas as tmux sessions. No container, no compose, no perms
# footguns. Re-runnable: skips anything already installed.
#
#   ./install.sh
#
# Afterwards manage the stack with ./troupely.sh {start|stop|status|attach <name>}.
set -euo pipefail
cd "$(dirname "$0")"

c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_grn=$'\033[32m'; c_red=$'\033[31m'; c_cyn=$'\033[36m'; c_rst=$'\033[0m'
say(){ printf '%s\n' "$*" >&2; }
hdr(){ say ""; say "${c_bold}${c_cyn}$*${c_rst}"; }

hdr "troupely native installer"

# ---- 0. sanity: this path targets Linux ----
case "$(uname -s)" in
  Linux) ;;
  Darwin) say "${c_dim}macOS: native mode runs on your Mac's own Claude Code login (shared via the login Keychain). Docker is still the isolated option.${c_rst}" ;;
  *) say "${c_dim}⚠ Unrecognized OS — proceeding best-effort.${c_rst}" ;;
esac

# ---- 1. system packages (Debian/Ubuntu via apt) ----
hdr "1) System packages"
PKGS="tmux git curl ca-certificates jq python3 python3-pip less procps unzip"
if command -v apt-get >/dev/null 2>&1; then
  missing=""
  for p in $PKGS; do dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"; done
  if [ -n "$missing" ]; then
    say "Installing:$missing"
    # A broken third-party apt source (e.g. a dead PPA) makes `update` exit non-zero;
    # don't let that abort the install — the packages we need live in the main repos
    # and their lists are already cached.
    sudo apt-get update -qq || say "${c_dim}⚠ apt update reported errors (often a stale third-party repo) — continuing with cached lists.${c_rst}"
    sudo apt-get install -y --no-install-recommends $missing || {
      say ""
      say "${c_red}✗ apt install failed.${c_rst} Most often a broken third-party repo. Find + remove it:"
      say "    grep -rl 'aaddrick\\|<the-failing-host>' /etc/apt/sources.list.d/ | xargs -r sudo rm"
      say "  (the error above names the repo URL). Then re-run ${c_bold}./install.sh${c_rst}"
      exit 1
    }
  else
    say "${c_grn}✓ all system packages present.${c_rst}"
  fi
elif [ "$(uname -s)" = "Darwin" ]; then
  missing=""
  for p in tmux jq python3 git curl; do command -v "$p" >/dev/null 2>&1 || missing="$missing $p"; done
  if [ -z "$missing" ]; then
    say "${c_grn}✓ all system packages present.${c_rst}"
  elif command -v brew >/dev/null 2>&1; then
    say "Installing (Homebrew):$missing"
    brew install $missing || { say "${c_red}✗ brew install failed${c_rst} — install$missing yourself, then re-run ./install.sh"; exit 1; }
  else
    say "${c_red}✗ missing:$missing${c_rst} — install Homebrew (https://brew.sh) or these tools, then re-run ./install.sh"
    exit 1
  fi
elif command -v dnf >/dev/null 2>&1; then
  say "${c_dim}dnf detected — installing equivalents (best-effort).${c_rst}"
  sudo dnf install -y tmux git curl ca-certificates jq python3 python3-pip less procps-ng unzip || true
else
  say "${c_dim}⚠ No apt/dnf — install these yourself if missing:${c_rst} $PKGS"
fi

# ---- 2. bun (the Telegram channel plugin's server runs under bun) ----
hdr "2) bun"
if command -v bun >/dev/null 2>&1; then
  say "${c_grn}✓ bun present ($(bun --version)).${c_rst}"
elif [ -x "$HOME/.bun/bin/bun" ]; then
  say "${c_grn}✓ bun present at ~/.bun/bin.${c_rst}"
else
  say "Installing bun…"
  curl -fsSL https://bun.sh/install | bash
fi
export PATH="$HOME/.bun/bin:$PATH"

# ---- 3. Claude Code CLI ----
hdr "3) Claude Code CLI"
if command -v claude >/dev/null 2>&1; then
  say "${c_grn}✓ claude present ($(claude --version 2>&1 | head -1)).${c_rst}"
elif [ -x "$HOME/.local/bin/claude" ]; then
  say "${c_grn}✓ claude present at ~/.local/bin.${c_rst}"
else
  say "Installing Claude Code…"
  curl -fsSL https://claude.ai/install.sh | bash
fi
export PATH="$HOME/.local/bin:$PATH"

if ! command -v claude >/dev/null 2>&1; then
  say "${c_red}✗ claude still not on PATH.${c_rst} Open a new shell (so ~/.local/bin is picked up) and re-run, or add it to PATH manually."
  exit 1
fi

# ---- 4. onboarding (reuse setup.sh; native mode skips its Docker launch) ----
hdr "4) Onboarding"
if [ -f .env ] && grep -q '^TROUPELY_PERSONAS=' .env; then
  say "${c_dim}An .env already exists.${c_rst}"
  printf 'Re-run onboarding? [y/N]: ' >&2; read -r ans || ans=""
  [ "${ans:-}" = "y" ] || [ "${ans:-}" = "Y" ] && TROUPELY_NATIVE=1 ./setup.sh
else
  TROUPELY_NATIVE=1 ./setup.sh
fi

# ---- 5. auth + launch ----
hdr "5) Launch"
set -a; [ -f .env ] && . .env; set +a
SUBSCRIPTION=1
{ [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; } && SUBSCRIPTION=0

if [ ! -f vault/.claude/.credentials.json ] && [ "$SUBSCRIPTION" -eq 1 ]; then
  # macOS: ./troupely.sh login reuses an existing Mac Claude login and only runs OAuth if there is none.
  say "${c_cyn}Subscription selected — log in once now.${c_rst}"
  printf 'Run Claude login now? [Y/n]: ' >&2; read -r ans || ans=""
  if [ "${ans:-Y}" != "n" ] && [ "${ans:-Y}" != "N" ]; then
    ./troupely.sh login || say "${c_dim}Login skipped/failed — run ./troupely.sh login when ready.${c_rst}"
  fi
fi

./troupely.sh start || true

hdr "Done"
say "Manage your stack:"
say "  ${c_bold}./troupely.sh status${c_rst}            who's live"
say "  ${c_bold}./troupely.sh attach <name>${c_rst}     attach to a persona (Ctrl-b d to detach)"
say "  ${c_bold}./troupely.sh stop${c_rst} / ${c_bold}restart${c_rst}     lifecycle"
say "  ${c_bold}./troupely.sh login${c_rst}             (re)auth a Claude subscription"
