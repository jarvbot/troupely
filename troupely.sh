#!/usr/bin/env bash
# troupely — lifecycle control for both install modes.
#
# Docker mode (default when Docker is installed): one container, one tmux session per
# persona inside it. Native mode: the same sessions directly on the host. The mode comes
# from TROUPELY_MODE in .env (written by setup.sh); without it, an existing `troupely`
# container means Docker mode.
#
# In both modes Claude Code's auth + plugin state lives under ./vault, never the
# operator's own ~/.claude.
#
# Usage: ./troupely.sh <command>   (run with no command, or --help, for the list)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VAULT_DIR="$HERE/vault"
PERSONA_ROOT="$VAULT_DIR/personas"

c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_grn=$'\033[32m'; c_red=$'\033[31m'; c_cyn=$'\033[36m'; c_rst=$'\033[0m'
say(){ printf '%s\n' "$*" >&2; }

# Binaries live in the operator's real home; STATE isolates into ./vault.
USER_HOME="$HOME"
export TROUPELY_USER_HOME="$USER_HOME"
export TROUPELY_REPO="$HERE"             # personas read this to find ./troupely.sh (skill: troupely-ops)   # launch-persona.sh links the macOS login Keychain from here
export PATH="$USER_HOME/.local/bin:$USER_HOME/.bun/bin:/usr/local/bin:$PATH"
export HOME="$VAULT_DIR"
unset TELEGRAM_STATE_DIR   # per-session below; never inherit a global override

mkdir -p "$VAULT_DIR/.claude"

# Load the generated .env (provider creds + per-persona tokens). set -a exports all.
if [ -f "$HERE/.env" ]; then chmod 600 "$HERE/.env" 2>/dev/null || true; set -a; . "$HERE/.env"; set +a; fi

# Docker runs under the operator's REAL home. Its CLI plugins (compose in
# ~/.docker/cli-plugins) and its context (OrbStack, Docker Desktop) live there; under the
# vault HOME, `docker compose` is "unknown command" and docker talks to the wrong socket (W1).
docker(){ HOME="$USER_HOME" command docker "$@"; }

CONTAINER=troupely
if [ -z "${TROUPELY_MODE:-}" ]; then
  if command -v docker >/dev/null 2>&1 && docker inspect "$CONTAINER" >/dev/null 2>&1; then
    TROUPELY_MODE=docker
  else
    TROUPELY_MODE=native
  fi
fi
is_docker(){ [ "$TROUPELY_MODE" = "docker" ]; }
export HOST_UID="${HOST_UID:-$(id -u)}" HOST_GID="${HOST_GID:-$(id -g)}"
dc(){ docker compose -f "$HERE/docker/compose.yaml" --env-file "$HERE/.env" "$@"; }
container_up(){ [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]; }
need_container(){
  container_up || { say "${c_red}✗ the troupely container isn't running.${c_rst} Start it: ${c_bold}./troupely.sh start${c_rst}"; exit 1; }
}

need_claude(){
  if ! command -v claude >/dev/null 2>&1; then
    say "${c_red}✗ 'claude' not found on PATH.${c_rst} Run ./install.sh first (or: curl -fsSL https://claude.ai/install.sh | bash)."
    exit 1
  fi
}

have_provider_key(){ [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] || [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; }

# macOS native: subscription auth is the operator's own `claude` login, held in the login
# Keychain. The Keychain search list comes from $HOME/Library/Keychains, so a persona's own
# HOME sees no Keychain at all; launch-persona.sh links the real one in. Every persona then
# reads and refreshes the SAME Keychain item, so there is no per-persona copy to go stale
# (the creds-file symlink bug). Verified 2026-10-11: two HOMEs, concurrent calls, no new item.
mac_keychain_login(){
  [ "$(uname)" = "Darwin" ] || return 1
  HOME="$USER_HOME" claude auth status 2>/dev/null | grep -q '"authMethod": "claude.ai"'
}

resolve_roster(){
  # Set-but-empty means "no personas" (e.g. after `remove` of the last one). Only an UNSET
  # roster falls back to the JSON file or the persona dirs.
  if [ -n "${TROUPELY_PERSONAS+x}" ]; then
    echo "$TROUPELY_PERSONAS" | tr ',' '\n' | sed 's/[[:space:]]//g'
  elif [ -f "$VAULT_DIR/troupely-roster.json" ]; then
    grep -oE '"[A-Za-z0-9_-]+"' "$VAULT_DIR/troupely-roster.json" | tr -d '"' | grep -vE '^(name)$'
  elif [ -d "$PERSONA_ROOT" ]; then
    find "$PERSONA_ROOT" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
  fi
}

# Install the Telegram channel plugin into the persisted vault on first boot (idempotent).
install_plugin(){
  if ! claude plugin list 2>/dev/null | grep -q "telegram@claude-plugins-official"; then
    say "▶ installing telegram channel plugin (first boot)…"
    if ! claude plugin marketplace list 2>/dev/null | grep -q "claude-plugins-official"; then
      claude plugin marketplace add anthropics/claude-plugins-official 2>&1 | tail -1 \
        || say "  ${c_dim}⚠ couldn't add the official plugin marketplace (network?).${c_rst}"
    fi
    claude plugin install telegram@claude-plugins-official 2>&1 | tail -1 \
      || say "  ${c_dim}⚠ plugin install failed (network?) — the telegram channel won't load until it succeeds.${c_rst}"
  fi
  # teach the plugin TELEGRAM_TOPIC_FILTER (public plugin lacks it). Idempotent +
  # safe: no-op if already supported or anchor missing. Required for topic routing.
  if [ -f "$HERE/plugin-patch/apply-topic-patch.py" ]; then
    python3 "$HERE/plugin-patch/apply-topic-patch.py" \
      "$VAULT_DIR/.claude/plugins/cache/claude-plugins-official/telegram" || true
  fi
}

cmd_add(){
  local arch="${1:-}" name="${2:-}" tok="${3:-}"
  if [ -z "$arch" ] || [ -z "$name" ]; then
    say "usage: ./troupely.sh add <archetype> <name> [bot-token]"
    local a list="" addl=""
    for a in "$HERE"/personas/*/; do [ -d "$a" ] && list="$list$(basename "$a") "; done
    for a in "$HERE"/addons/personas/*/; do [ -d "$a" ] && addl="$addl$(basename "$a") "; done
    say "  core archetypes: $list"
    [ -n "$addl" ] && say "  add-on archetypes: $addl"
    exit 1
  fi
  [ "$arch" = ideation ] && arch=planning   # renamed in v1.1; old docs and habits still say ideation
  local adir="$HERE/personas/$arch"
  [ -d "$adir" ] || adir="$HERE/addons/personas/$arch"
  [ -d "$adir" ] || { say "${c_red}✗ no archetype '$arch'${c_rst} (see: ls personas/ addons/personas/)"; exit 1; }
  name="$(printf '%s' "$name" | tr -cd 'A-Za-z0-9_-')"
  [ -z "$name" ] && { say "${c_red}✗ invalid name${c_rst}"; exit 1; }
  if [ -d "$PERSONA_ROOT/$name" ]; then
    say "${c_dim}persona '$name' dir already exists — reusing it${c_rst}"
  else
    mkdir -p "$PERSONA_ROOT"; cp -R "$adir" "$PERSONA_ROOT/$name"
    say "${c_grn}✓ created persona '$name' from $arch${c_rst}"
  fi
  if [ -z "$tok" ]; then printf "  Telegram bot token for '%s' (from @BotFather, input hidden): " "$name" >&2; read -rs tok || tok=""; printf '\n' >&2; fi
  [ -z "$tok" ] && { say "${c_red}✗ no bot token — mint one with @BotFather, then run this again: ./troupely.sh add $arch $name${c_rst}"; exit 1; }
  case "$tok" in *[!0-9A-Za-z:_-]*|"") say "${c_red}✗ that doesn't look like a bot token${c_rst} (expected 123456789:AAE…)"; exit 1 ;; esac
  take_lock   # so a supervisor pass can't launch it at the same moment we do
  # register in .env: add to TROUPELY_PERSONAS + set the token line, idempotently
  local roster="${TROUPELY_PERSONAS:-}"
  case ",$roster," in *",$name,"*) ;; *) roster="${roster:+$roster,}$name" ;; esac
  python3 "$HERE/lib/envfile.py" "$HERE/.env" "TROUPELY_PERSONAS=$roster" \
    "TROUPELY_TG_TOKEN_$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')=$tok" \
    || { say "${c_red}✗ failed to update .env${c_rst}"; exit 1; }
  say "  ✓ registered in .env"
  say "${c_grn}✓ '$name' added.${c_rst} Launching…"
  local up; up="$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')"
  if is_docker; then
    # Start ONLY the new session inside the running container. A container restart would
    # kill every sibling mid-tick. The container's env predates this token, so pass it in.
    need_container
    local tv="TROUPELY_TG_TOPIC_$up"
    docker exec -e VAULT_DIR=/vault -e "TROUPELY_TG_TOKEN_$up=$tok" \
      -e "$tv=${!tv:-}" -e "TROUPELY_TG_GROUP=${TROUPELY_TG_GROUP:-}" \
      "$CONTAINER" /usr/local/lib/troupely/lib/launch-persona.sh "$name"
  else
    export "TROUPELY_TG_TOKEN_$up=$tok"
    VAULT_DIR="$VAULT_DIR" "$HERE/lib/launch-persona.sh" "$name"
  fi
  say "  Next: DM the bot, then ${c_bold}./troupely.sh pair $name <code-it-sends-you>${c_rst}"
}

cmd_topic(){
  local name="${1:-}" group="${2:-}" topic="${3:-}"
  if [ -z "$name" ] || [ -z "$group" ] || [ -z "$topic" ]; then
    say "usage: ./troupely.sh topic <persona> <supergroup_id> <topic_id>"
    say "  e.g.  ./troupely.sh topic researcher -1001234567890 42"
    exit 1
  fi
  [ -d "$PERSONA_ROOT/$name" ] || { say "${c_red}✗ no persona '$name'${c_rst} (see: ./troupely.sh status)"; exit 1; }
  [[ "$group" =~ ^-100[0-9]+$ ]] || { say "${c_red}✗ group id must look like -1001234567890${c_rst}"; exit 1; }
  [[ "$topic" =~ ^[0-9]+$ ]] || { say "${c_red}✗ topic id must be a number${c_rst}"; exit 1; }
  local up; up="$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')"
  python3 "$HERE/lib/envfile.py" "$HERE/.env" "TROUPELY_TG_GROUP=$group" "TROUPELY_TG_TOPIC_$up=$topic" \
    || { say "${c_red}✗ .env update failed${c_rst}"; exit 1; }
  say "${c_grn}✓ topic routing set for $name${c_rst} (group $group, topic $topic)."
  say "  • apply:  ${c_bold}./troupely.sh restart${c_rst}"
  say "  • @BotFather: /setprivacy → $name's bot → Disable (so it sees topic chatter, not just @mentions)."
  say "    Already in the group? Remove and re-add the bot after changing it: privacy applies on join."
}

cmd_module(){
  local sub="${1:-list}"; [ "$#" -gt 0 ] && shift || true
  case "$sub" in
    list)
      say "${c_bold}Available modules${c_rst} ${c_dim}(./troupely.sh module add <module> <persona>)${c_rst}"
      local found=0 mj
      for mj in "$HERE"/modules/*/module.json; do
        [ -f "$mj" ] || continue; found=1
        python3 - "$mj" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print(f"  {m.get('name',''):14} {m.get('description','')}")
PY
      done
      [ "$found" -eq 0 ] && say "  ${c_dim}(none yet — add one under modules/<name>/module.json)${c_rst}"
      ;;
    add)
      local mod="${1:-}" persona="${2:-}"
      if [ -z "$mod" ] || [ -z "$persona" ]; then say "usage: ./troupely.sh module add <module> <persona>"; exit 1; fi
      local mdir="$HERE/modules/$mod"
      [ -f "$mdir/module.json" ] || { say "${c_red}✗ no module '$mod'${c_rst} (see: ./troupely.sh module list)"; exit 1; }
      [ -d "$PERSONA_ROOT/$persona" ] || { say "${c_red}✗ no persona '$persona'${c_rst} (see: ./troupely.sh status)"; exit 1; }
      # merge MCP servers + copy skills + enable project MCP; emit env list + notes
      local out
      out="$(python3 - "$mdir" "$PERSONA_ROOT/$persona" "$VAULT_DIR" <<'PY'
import json, os, sys, shutil
mdir, pdir, vault = sys.argv[1], sys.argv[2], sys.argv[3]
m = json.load(open(os.path.join(mdir, "module.json")))
# 1) merge mcpServers into the persona's project .mcp.json
mcpp = os.path.join(pdir, ".mcp.json")
try: mcp = json.load(open(mcpp))
except Exception: mcp = {}
srv = mcp.setdefault("mcpServers", {})
for k, v in (m.get("mcpServers") or {}).items(): srv[k] = v
with open(mcpp, "w") as f: json.dump(mcp, f, indent=2)
# 2) copy skills
for sk in (m.get("skills") or []):
    src = os.path.join(mdir, sk)
    if os.path.isdir(src):
        dst = os.path.join(pdir, ".claude", "skills", os.path.basename(sk))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.exists(dst): shutil.rmtree(dst)
        shutil.copytree(src, dst)
# 3) auto-enable project MCP servers (troupely already runs skip-permissions)
stp = os.path.join(vault, ".claude", "settings.json")
try: st = json.load(open(stp))
except Exception: st = {}
st["enableAllProjectMcpServers"] = True
os.makedirs(os.path.dirname(stp), exist_ok=True)
with open(stp, "w") as f: json.dump(st, f, indent=2)
print("SERVERS=" + ",".join((m.get("mcpServers") or {}).keys()))
print("NOTES=" + (m.get("notes") or ""))
for e in (m.get("env") or []):
    print("ENV=%s\t%s\t%s" % (e.get("key",""), e.get("prompt",""), "1" if e.get("required") else "0"))
PY
)" || { say "${c_red}✗ module add failed${c_rst}"; exit 1; }
      # prompt for each env key, write to .env (grep-empty must not trip set -e)
      local envlines; envlines="$(printf '%s\n' "$out" | grep '^ENV=' || true)"
      if [ -n "$envlines" ]; then
        printf '%s\n' "$envlines" | while IFS=$'\t' read -r k prompt _req; do
          key="${k#ENV=}"; [ -z "$key" ] && continue
          printf '  %s: ' "${prompt:-$key}" >&2; read -r val </dev/tty 2>/dev/null || val=""
          if [ -n "$val" ]; then
            python3 "$HERE/lib/envfile.py" "$HERE/.env" "$key=$val" || say "${c_red}✗ couldn't save $key${c_rst}"
          fi
        done
      fi
      local servers notes
      servers="$(printf '%s\n' "$out" | sed -n 's/^SERVERS=//p')"
      notes="$(printf '%s\n' "$out" | sed -n 's/^NOTES=//p')"
      say "${c_grn}✓ module '$mod' added to $persona${c_rst}${servers:+ (MCP: $servers)}"
      [ -n "$notes" ] && say "  ${c_dim}$notes${c_rst}"
      say "  restart to load:  ${c_bold}./troupely.sh restart${c_rst}"
      ;;
    *) say "usage: ./troupely.sh module {list|add <module> <persona>}"; exit 1 ;;
  esac
}

cmd_pair(){
  local name="${1:-}"; [ -z "$name" ] && { say "usage: ./troupely.sh pair <persona> <code>   (no code = list pending requests)"; exit 1; }
  local code="${2:-}"
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || { say "${c_red}✗ invalid persona name${c_rst}"; exit 1; }
  # Approve a Telegram pairing by editing the persona's access.json directly — no
  # claude session needed. Works for BOTH native and Docker installs: the Docker
  # compose mounts this same repo-root vault/, so the path below is the exact file
  # the containerized server reads. The server re-reads access.json per message and
  # polls approved/, so the approval takes effect with no restart.
  local sd="$VAULT_DIR/.claude/homes/$name/.claude/channels/telegram"
  if [ ! -f "$sd/access.json" ]; then
    say "${c_red}✗ no access.json for '$name' yet.${c_rst}"
    say "  Have them DM the bot once first (that creates the pending pairing). Looked in:"
    say "    $sd"
    exit 1
  fi
  local rc=0
  python3 - "$sd" "$code" <<'PY' || rc=$?
import json, os, sys
sd, code = sys.argv[1], sys.argv[2]
ajp = os.path.join(sd, "access.json")
with open(ajp) as f: a = json.load(f)
pend = a.get("pending", {})
if not pend:
    print("  No pending pairings. Already-allowed senders:", a.get("allowFrom", []))
    sys.exit(2)
if not code:
    # Never approve without a code. Bot usernames are public: a stranger who DMs the bot
    # gets a pending entry exactly like yours, and approving them hands over a shell.
    import time
    now = time.time() * 1000
    print("  Pending pairing requests (approve ONE by its code):")
    for c, e in pend.items():
        age = int((now - e.get("createdAt", now)) / 60000)
        gone = " (expired)" if e.get("expiresAt", now + 1) < now else ""
        print(f"    code {c}   sender {e.get('senderId')}   {age} min ago{gone}")
    print("  The code is the one the bot sent YOU. Then: ./troupely.sh pair <persona> <code>")
    sys.exit(2)
approved = []
e = pend.get(code)
if not e:
    print("  ⚠ code not found:", code); sys.exit(1)
import time
if e.get("expiresAt", float("inf")) < time.time() * 1000:
    print("  ⚠ code expired; DM the bot again for a new one:", code); sys.exit(1)
sid, cid = str(e.get("senderId")), str(e.get("chatId"))
af = a.setdefault("allowFrom", [])
if sid not in af: af.append(sid)
del pend[code]
apdir = os.path.join(sd, "approved"); os.makedirs(apdir, exist_ok=True)
with open(os.path.join(apdir, sid), "w") as f: f.write(cid)
approved.append(sid)
a["pending"] = pend
tmp = ajp + ".tmp"
with open(tmp, "w") as f: json.dump(a, f, indent=2)
os.replace(tmp, ajp)
print("  ✓ approved sender(s):", ", ".join(approved) if approved else "(none)")
print("  allowFrom now:", a.get("allowFrom", []))
PY
  [ "$rc" -eq 2 ] && exit 0
  [ "$rc" -ne 0 ] && { say "${c_red}✗ pair failed${c_rst}"; exit 1; }
  # Topic-routed persona: the group admits only paired senders, so widen it now (no restart).
  local up; up="$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')"
  local tv="TROUPELY_TG_TOPIC_$up"
  if [ -n "${TROUPELY_TG_GROUP:-}" ] && [ -n "${!tv:-}" ]; then
    python3 "$HERE/lib/group-access.py" "$sd" "$TROUPELY_TG_GROUP" || true
  fi
  say "${c_grn}✓ pairing updated for $name.${c_rst} They can DM the bot now."
}

cmd_login(){
  if is_docker; then
    need_container
    say "${c_cyn}Claude subscription login (OAuth).${c_rst} It prints a URL: open it in any browser,"
    say "approve, then paste the code back here."
    docker exec -it "$CONTAINER" claude auth login --claudeai
    if docker exec "$CONTAINER" test -s /vault/.claude/.credentials.json; then
      say "${c_grn}✓ logged in.${c_rst} Restarting the container so your personas start…"
      docker restart "$CONTAINER" >/dev/null
      say "${c_grn}✓ restarted.${c_rst} Check: ${c_bold}./troupely.sh status${c_rst}"
    else
      say "${c_red}✗ no credentials were saved${c_rst} — the login didn't finish. Run ./troupely.sh login again."
      exit 1
    fi
    return
  fi
  need_claude
  if [ "$(uname)" = "Darwin" ]; then
    if mac_keychain_login; then
      say "${c_grn}✓ using this Mac's Claude login${c_rst} (the one your own Claude Code uses). Every persona"
      say "  shares it through the login Keychain, so they all run on that subscription."
      say "  Now: ${c_bold}./troupely.sh start${c_rst}"
      return
    fi
    say "${c_cyn}Claude subscription login (OAuth).${c_rst} This is the standard Claude Code login for this Mac:"
    say "your own Claude Code and every persona will share it."
    HOME="$USER_HOME" claude auth login --claudeai
    mac_keychain_login || { say "${c_red}✗ not logged in${c_rst} — the login didn't finish. Run ./troupely.sh login again."; exit 1; }
    say "${c_grn}✓ logged in.${c_rst} Now: ${c_bold}./troupely.sh start${c_rst}"
    return
  fi
  say "${c_cyn}Opening Claude subscription login (OAuth). Follow the browser/URL prompt.${c_rst}"
  claude auth login --claudeai
  say "${c_grn}✓ logged in — creds persisted at vault/.claude. Now: ./troupely.sh start${c_rst}"
}

cmd_start(){
  take_lock
  if is_docker; then
    command -v docker >/dev/null 2>&1 || { say "${c_red}✗ Docker isn't installed.${c_rst}"; exit 1; }
    dc up -d --build
    say "${c_grn}✓ container up.${c_rst} Personas start once Claude auth exists (./troupely.sh login)."
    say "  Check: ${c_bold}./troupely.sh status${c_rst}"
    return
  fi
  need_claude
  # auth guard
  if [ ! -f "$VAULT_DIR/.claude/.credentials.json" ] && ! have_provider_key && ! mac_keychain_login; then
    say ""
    say "${c_red}✗ No Claude auth found.${c_rst} Pick ONE:"
    say "  • Subscription:  ${c_bold}./troupely.sh login${c_rst}   (then ./troupely.sh start)"
    say "  • Provider key:  set ANTHROPIC_API_KEY (or ANTHROPIC_AUTH_TOKEN + ANTHROPIC_BASE_URL)"
    say "                   in ${c_bold}$HERE/.env${c_rst}, then re-run start"
    exit 1
  fi

  local ROSTER=()
  while IFS= read -r line; do [ -n "$line" ] && ROSTER+=("$line"); done < <(resolve_roster | awk 'NF' | sort -u)
  if [ "${#ROSTER[@]}" -eq 0 ]; then
    say "${c_red}✗ No personas resolved.${c_rst} Run ./setup.sh (sets TROUPELY_PERSONAS in .env)."
    exit 1
  fi

  python3 "$HERE/lib/payload_sync.py" "$HERE" "$VAULT_DIR" \
    || say "  ${c_dim}⚠ payload sync failed — personas may be missing the shared rules.${c_rst}"
  python3 "$HERE/lib/seed_onboarding.py" "$VAULT_DIR" >/dev/null
  install_plugin

  say "▶ troupely launching ${#ROSTER[@]} persona(s): ${ROSTER[*]}"
  say "  claude: $(claude --version 2>&1 | head -1)"
  local started=0 p rc
  for p in "${ROSTER[@]}"; do
    rc=0; VAULT_DIR="$VAULT_DIR" "$HERE/lib/launch-persona.sh" "$p" || rc=$?
    [ "$rc" -eq 0 ] && started=$((started + 1))
  done
  if [ "$started" -eq 0 ]; then
    say "${c_dim}Nothing newly started (already running, or no tokens set).${c_rst}"
  else
    say "${c_grn}▶ $started persona session(s) live.${c_rst} Attach: ${c_bold}./troupely.sh attach <name>${c_rst}"
  fi
}

# ---- lifecycle lock ----
# start, restart, remove, uninstall and the Docker supervisor's passes all change which
# sessions run. Serialize them, or e.g. a supervisor pass that read the old roster relaunches
# a persona `remove` just stopped. mkdir is atomic on every filesystem we run on, including
# the Docker bind mount, so host and container share it. PIDs don't cross the container
# boundary, so a lock is judged stale by age.
LOCK="$VAULT_DIR/.claude/troupely.lock"
# GNU stat first: on Linux `stat -f` means --file-system, succeeds, and prints a block of
# filesystem text, so a BSD-first chain never reaches its fallback.
mtime_of(){ stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
lock_age(){ local m; m="$(mtime_of "$LOCK")" || return 1; [[ "$m" =~ ^[0-9]+$ ]] || return 1; echo $(( $(date +%s) - m )); }
take_lock(){
  # Not exported: nested calls (restart → stop + start) are functions in this same shell,
  # and an exported flag would leak into the tmux server and from there into run-shell.
  [ "${LOCK_HELD:-}" = 1 ] && return 0
  for _ in $(seq 60); do
    if mkdir "$LOCK" 2>/dev/null; then
      LOCK_HELD=1; trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT; return 0
    fi
    if [ "$(lock_age || echo 0)" -gt 300 ]; then rmdir "$LOCK" 2>/dev/null || true; continue; fi
    sleep 0.5
  done
  say "${c_red}✗ another troupely command is running${c_rst} (lock $LOCK). If none is, remove that directory."; exit 1
}

# Run tmux where the sessions live: inside the container in Docker mode, else on the host.
tm(){ if is_docker; then need_container; docker exec "$CONTAINER" tmux "$@"; else tmux "$@"; fi; }

cmd_stop(){
  take_lock
  if is_docker; then dc stop; return; fi
  local found=0 s
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    tmux kill-session -t "=$s" 2>/dev/null && { say "  ${c_grn}✓ stopped $s${c_rst}"; found=1; }
  done < <(tmux ls 2>/dev/null | grep -oE '^troupely-[A-Za-z0-9_-]+' || true)
  # An if, not `[ ] && say`: as a function's last command that returns 1 whenever a session
  # WAS stopped, and under set -e `restart` then died before starting anything again.
  if [ "$found" -eq 0 ]; then say "${c_dim}No troupely sessions running.${c_rst}"; fi
}

cmd_restart(){
  # --force-recreate so a changed .env (new token, topic) actually reaches the container.
  if is_docker; then dc up -d --build --force-recreate; return; fi
  cmd_stop; cmd_start
}

cmd_status(){
  say "${c_bold}mode:${c_rst} $TROUPELY_MODE"
  topic_check
  if is_docker && ! container_up; then say "${c_dim}container not running.${c_rst}"; return; fi
  local rows; rows="$(tm ls 2>/dev/null | grep -E '^troupely-' || true)"
  if [ -z "$rows" ]; then
    say "${c_dim}No troupely sessions running.${c_rst}"
    is_docker && say "  Last container output: ${c_bold}docker logs --tail 20 $CONTAINER${c_rst}"
    return
  fi
  say "${c_bold}Live persona sessions:${c_rst}"
  printf '%s\n' "$rows" | sed 's/^/  /' >&2
}

# W10: a topic-routed persona on an unpatched plugin answers every topic in the group, and
# nothing else would say so. Check the plugin files the personas actually load.
topic_check(){
  local routed="" p up tv
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    up="$(printf '%s' "$p" | tr '[:lower:]-' '[:upper:]_')"; tv="TROUPELY_TG_TOPIC_$up"
    [ -n "${!tv:-}" ] && routed="$routed $p"
  done < <(resolve_roster)
  [ -n "$routed" ] || return 0
  local out rc=0
  out="$(python3 "$HERE/plugin-patch/apply-topic-patch.py" --check \
    "$VAULT_DIR/.claude/plugins/cache/claude-plugins-official/telegram" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    say "${c_red}✗ topic routing is NOT enforced${c_rst} for${routed}: these bots will answer every topic."
    printf '%s\n' "$out" >&2
    say "  Fix: ${c_bold}./troupely.sh restart${c_rst} (re-applies the patch). If it still fails, the plugin changed: see docs/TROUBLESHOOTING.md."
  elif printf '%s' "$out" | grep -q "⚠"; then
    printf '%s\n' "$out" | grep "⚠" >&2
  fi
}

cmd_attach(){
  local name="${1:-}"; [ -z "$name" ] && { say "usage: ./troupely.sh attach <persona>"; exit 1; }
  if is_docker; then need_container; HOME="$USER_HOME" exec docker exec -it "$CONTAINER" tmux attach -t "=troupely-$name"; fi
  exec tmux attach -t "=troupely-$name"
}

cmd_logs(){
  local name="${1:-}"; [ -z "$name" ] && { say "usage: ./troupely.sh logs <persona>"; exit 1; }
  tm capture-pane -pt "=troupely-$name:" -S -40 2>/dev/null \
    || { say "${c_red}✗ no session troupely-$name${c_rst}"; exit 1; }
}

# ---- autostart (W4, native) ----
# Docker mode needs none: the container has restart: unless-stopped and its PID 1 relaunches
# dead sessions. Native has no supervisor, so install one per-user job that runs
# `troupely.sh start` at login and every TROUPELY_AUTOSTART_SECS (300). start is idempotent:
# it skips live sessions and relaunches missing ones.
autostart_label(){ printf 'net.troupely.%s' "$(printf '%s' "$HERE" | cksum | cut -d' ' -f1)"; }
cmd_autostart(){
  local what="${1:-status}" label secs="${TROUPELY_AUTOSTART_SECS:-300}" log="$VAULT_DIR/.claude/autostart.log"
  label="$(autostart_label)"
  if is_docker; then
    say "Docker mode: nothing to install. The container restarts with Docker and relaunches dead"
    say "personas itself. Make sure Docker (Desktop/OrbStack) starts at login."
    return
  fi
  [[ "$secs" =~ ^[0-9]+$ ]] || { say "${c_red}✗ TROUPELY_AUTOSTART_SECS must be a number${c_rst}"; exit 1; }
  case "$(uname)" in
    Darwin)
      local plist="$USER_HOME/Library/LaunchAgents/$label.plist" dom; dom="gui/$(id -u)"
      case "$what" in
        on)
          mkdir -p "$(dirname "$plist")"
          # AbandonProcessGroup: without it launchd kills the tmux server (and every persona)
          # the moment `start` exits. PATH is captured now: launchd's default has no
          # Homebrew, bun or ~/.local/bin, so tmux and claude would not be found.
          # plistlib, not a heredoc: a path with & or < would otherwise be invalid XML.
          python3 - "$plist" "$label" "$HERE/troupely.sh" "$PATH" "$secs" "$log" <<'PY' \
            || { say "${c_red}✗ couldn't write $plist${c_rst}"; exit 1; }
import plistlib, sys
plist, label, script, path, secs, log = sys.argv[1:]
with open(plist, "wb") as f:
    plistlib.dump({"Label": label, "ProgramArguments": ["/bin/bash", script, "start"],
                   "EnvironmentVariables": {"PATH": path}, "RunAtLoad": True,
                   "StartInterval": int(secs), "AbandonProcessGroup": True,
                   "StandardOutPath": log, "StandardErrorPath": log}, f)
PY
          launchctl bootout "$dom/$label" 2>/dev/null || true
          launchctl bootstrap "$dom" "$plist" || { say "${c_red}✗ launchctl bootstrap failed${c_rst}"; exit 1; }
          say "${c_grn}✓ autostart on${c_rst} ($label): starts at login, checks every ${secs}s. Log: $log" ;;
        off)
          launchctl bootout "$dom/$label" 2>/dev/null || true
          rm -f "$plist"; say "${c_grn}✓ autostart off${c_rst} (running personas left as they are)" ;;
        status)
          if launchctl print "$dom/$label" >/dev/null 2>&1; then say "autostart: ${c_grn}on${c_rst} ($label)"; else say "autostart: off  (./troupely.sh autostart on)"; fi ;;
        *) say "usage: ./troupely.sh autostart on|off|status"; exit 1 ;;
      esac ;;
    Linux)
      local udir="${XDG_CONFIG_HOME:-$USER_HOME/.config}/systemd/user" unit
      unit="troupely-$(printf '%s' "$HERE" | cksum | cut -d' ' -f1)"
      sc(){ HOME="$USER_HOME" systemctl --user "$@"; }
      # systemd unit syntax: double-quote, escape \ and ", and double % (specifier char).
      sdq(){ local v="${1//\\/\\\\}"; v="${v//\"/\\\"}"; v="${v//%/%%}"; printf '"%s"' "$v"; }
      sdp(){ printf '%s' "${1//%/%%}"; }
      case "$what" in
        on)
          command -v systemctl >/dev/null || { say "${c_red}✗ no systemd here.${c_rst} Add \`$HERE/troupely.sh start\` to cron (@reboot and */5)."; exit 1; }
          mkdir -p "$udir"
          # KillMode=process: a oneshot's leftover processes are killed when it finishes,
          # which here is the tmux server holding every persona.
          cat > "$udir/$unit.service" <<UNIT
[Unit]
Description=troupely personas ($(sdp "$HERE"))
[Service]
Type=oneshot
KillMode=process
Environment=$(sdq "PATH=$PATH")
ExecStart=/bin/bash $(sdq "$HERE/troupely.sh") start
StandardOutput=append:$(sdp "$log")
StandardError=append:$(sdp "$log")
UNIT
          cat > "$udir/$unit.timer" <<UNIT
[Unit]
Description=troupely supervisor ($(sdp "$HERE"))
[Timer]
OnBootSec=30
OnUnitActiveSec=$secs
[Install]
WantedBy=timers.target
UNIT
          sc daemon-reload && sc enable --now "$unit.timer" && sc start "$unit.service" \
            || { say "${c_red}✗ systemctl --user failed${c_rst}"; exit 1; }
          say "${c_grn}✓ autostart on${c_rst} ($unit.timer): checks every ${secs}s. Log: $log"
          if [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" != yes ]; then
            say "  To start at boot without logging in: ${c_bold}sudo loginctl enable-linger $(id -un)${c_rst}"
          fi ;;
        off)
          sc disable --now "$unit.timer" 2>/dev/null || true
          sc stop "$unit.service" 2>/dev/null || true   # a start already in flight
          rm -f "$udir/$unit.service" "$udir/$unit.timer"; sc daemon-reload 2>/dev/null || true
          say "${c_grn}✓ autostart off${c_rst} (running personas left as they are)" ;;
        status)
          if sc is-enabled "$unit.timer" >/dev/null 2>&1; then say "autostart: ${c_grn}on${c_rst} ($unit.timer)"; else say "autostart: off  (./troupely.sh autostart on)"; fi ;;
        *) say "usage: ./troupely.sh autostart on|off|status"; exit 1 ;;
      esac ;;
    *) say "${c_red}✗ autostart supports macOS and Linux only${c_rst}"; exit 1 ;;
  esac
}

# ---- one-persona + lifecycle commands (W5, W6) ----
valid_name(){ [[ "${1:-}" =~ ^[A-Za-z0-9_-]+$ ]]; }
upname(){ printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'; }

# Launch one persona now, with the CURRENT .env. In Docker the container's env predates any
# .env edit, so the token/topic/group are passed in (the supervisor would also catch it
# within TROUPELY_SUPERVISE_SECS).
launch_one(){
  local name="$1" up tv pv; up="$(upname "$name")"; tv="TROUPELY_TG_TOKEN_$up"; pv="TROUPELY_TG_TOPIC_$up"
  if is_docker; then
    need_container
    # The values passed in are the fallback for a container created before the read-only
    # repo mount existed; with the mount, the current host .env wins.
    docker exec -e VAULT_DIR=/vault -e "$tv=${!tv:-}" -e "$pv=${!pv:-}" \
      -e "TROUPELY_TG_GROUP=${TROUPELY_TG_GROUP:-}" "$CONTAINER" bash -c \
      'if [ -r /run/troupely/host/.env ]; then set -a; . /run/troupely/host/.env; set +a; fi
       exec /usr/local/lib/troupely/lib/launch-persona.sh "$1"' _ "$name"
  else
    VAULT_DIR="$VAULT_DIR" "$HERE/lib/launch-persona.sh" "$name"
  fi
}

cmd_restart_one(){
  local name="$1"
  valid_name "$name" || { say "${c_red}✗ invalid persona name${c_rst}"; exit 1; }
  # Called from inside the very session being restarted (a persona restarting itself via the
  # troupely-ops skill): killing the session kills this script before it can relaunch. Hand
  # the relaunch to the tmux server, which outlives the session. persona-exec.sh keeps TMUX
  # and TMUX_PANE for exactly this check.
  if ! is_docker && [ -n "${TMUX_PANE:-}" ] && [ "${TROUPELY_RESTART_DETACHED:-}" != 1 ] \
     && [ "$(tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null)" = "troupely-$name" ]; then
    local cmd; cmd="$(printf 'TROUPELY_RESTART_DETACHED=1 %q restart %q >>%q 2>&1' \
      "$HERE/troupely.sh" "$name" "$VAULT_DIR/.claude/autostart.log")"
    tmux run-shell -b "$cmd"
    say "  restarting $name in the background (this session goes dark for a moment)"; return
  fi
  take_lock
  if tm has-session -t "=troupely-$name" 2>/dev/null; then
    tm kill-session -t "=troupely-$name"; say "  ${c_grn}✓ stopped troupely-$name${c_rst}"
  else
    say "  ${c_dim}troupely-$name wasn't running${c_rst}"
  fi
  launch_one "$name"
}

cmd_update(){
  git -C "$HERE" diff --quiet && git -C "$HERE" diff --cached --quiet \
    || { say "${c_red}✗ local edits in $HERE${c_rst} (git status). Commit or stash them, then update."; exit 1; }
  local before after; before="$(git -C "$HERE" rev-parse HEAD)"
  git -C "$HERE" pull --ff-only || { say "${c_red}✗ can't fast-forward.${c_rst} Your checkout has diverged; see git status."; exit 1; }
  after="$(git -C "$HERE" rev-parse HEAD)"
  if [ "$before" = "$after" ]; then say "${c_dim}Source already up to date ($(cat "$HERE/VERSION" 2>/dev/null)).${c_rst}"
  else say "${c_grn}✓ updated${c_rst} ${before:0:7} → ${after:0:7} ($(cat "$HERE/VERSION" 2>/dev/null))"; fi
  # Deploy every time, not only when HEAD moved: if the last build or sync failed, running
  # update again must retry it. Both are no-ops when nothing changed.
  if is_docker; then
    dc up -d --build || { say "${c_red}✗ rebuild failed.${c_rst} Fix the error above and run update again."; exit 1; }
    say "  ✓ container on the current version"
  else
    python3 "$HERE/lib/payload_sync.py" "$HERE" "$VAULT_DIR" \
      || { say "${c_red}✗ payload sync failed.${c_rst} Fix the error above and run update again."; exit 1; }
    [ "$before" = "$after" ] || say "  Shared rules synced. Restart to load the new code: ${c_bold}./troupely.sh restart${c_rst}"
  fi
}

cmd_remove(){
  local name="${1:-}" up ts arch
  valid_name "$name" || { say "usage: ./troupely.sh remove <name>"; exit 1; }
  up="$(upname "$name")"; ts="$(date +%Y%m%d-%H%M%S)"
  take_lock
  # .env first: a supervisor pass that starts after this sees the new roster and won't
  # relaunch it; the lock keeps one from being mid-pass.
  local roster; roster="$(printf '%s' "${TROUPELY_PERSONAS:-}" | tr ',' '\n' | sed 's/[[:space:]]//g' | { grep -vx -- "$name" || true; } | awk 'NF' | paste -sd, -)"
  python3 "$HERE/lib/envfile.py" "$HERE/.env" "TROUPELY_PERSONAS=$roster" "-TROUPELY_TG_TOKEN_$up" "-TROUPELY_TG_TOPIC_$up" \
    || { say "${c_red}✗ failed to update .env${c_rst}"; exit 1; }
  say "  ✓ removed from .env (roster + token)"
  if tm has-session -t "=troupely-$name" 2>/dev/null; then tm kill-session -t "=troupely-$name"; say "  ✓ stopped troupely-$name"; fi
  arch="$VAULT_DIR/.archive/$name-$ts"; mkdir -p "$arch"
  [ -d "$PERSONA_ROOT/$name" ] && mv "$PERSONA_ROOT/$name" "$arch/persona"
  [ -d "$VAULT_DIR/.claude/homes/$name" ] && mv "$VAULT_DIR/.claude/homes/$name" "$arch/home"
  rmdir "$arch" 2>/dev/null && say "  ${c_dim}nothing on disk to archive${c_rst}" || say "  ✓ archived to ${arch#$HERE/}"
  say "${c_grn}✓ '$name' removed.${c_rst} Its bot still exists: in @BotFather send ${c_bold}/revoke${c_rst} (or /deletebot) for it."
}

cmd_uninstall(){
  if [ "${1:-}" != "--yes" ]; then
    say "This stops every persona, removes autostart and (Docker) the container and image."
    say "Your vault/ and .env stay on disk until you delete them."
    printf "Type 'uninstall' to go on: " >&2; local a; read -r a || a=""
    [ "$a" = "uninstall" ] || { say "Cancelled."; exit 1; }
  fi
  take_lock
  local left=()
  cmd_autostart off >/dev/null 2>&1 || true
  is_docker || cmd_autostart status 2>&1 | grep -q 'autostart: off' || left+=("autostart is still installed (./troupely.sh autostart off)")
  if is_docker; then
    dc down --remove-orphans || true
    docker inspect "$CONTAINER" >/dev/null 2>&1 && left+=("container '$CONTAINER' still exists (docker rm -f $CONTAINER)")
    docker image rm troupely:latest >/dev/null 2>&1 && say "  ✓ removed image troupely:latest" || true
  else
    cmd_stop
    tmux ls 2>/dev/null | grep -q '^troupely-' && left+=("troupely tmux sessions still running (tmux ls)")
  fi
  # Personas' HOMEs link the operator's real login Keychain on macOS. Drop the links so
  # deleting vault/ later can never reach through them.
  local l n=0
  for l in "$VAULT_DIR"/.claude/homes/*/Library/Keychains; do [ -L "$l" ] && rm -f "$l" && n=$((n + 1)); done
  [ "$n" -gt 0 ] && say "  ✓ unlinked the login Keychain from $n persona home(s) (the Keychain itself is untouched)"
  if [ "${#left[@]}" -gt 0 ]; then
    say "${c_red}✗ uninstall incomplete:${c_rst}"; printf '  • %s\n' "${left[@]}" >&2
    say "  Fix those and run uninstall again. Don't delete vault/ while anything is still running."
    exit 1
  fi
  say "${c_grn}✓ troupely uninstalled.${c_rst} Left on disk, delete when you're sure:"
  say "  $HERE/.env          bot tokens and keys"
  say "  $HERE/vault/        personas, memory, Claude auth"
  say "  $HERE               this checkout"
  say "  Bots still exist on Telegram: /revoke each in @BotFather."
}

usage(){
  cat >&2 <<EOF
${c_bold}troupely${c_rst} — run a team of Claude Code personas on Telegram   (mode: $TROUPELY_MODE)

  ./troupely.sh start                      start everything
  ./troupely.sh stop                       stop everything
  ./troupely.sh restart [name]             restart all (picks up .env changes), or just one
  ./troupely.sh update                     pull the latest version (rebuilds in Docker mode)
  ./troupely.sh remove <name>              stop a persona, drop it from .env, archive its files
  ./troupely.sh uninstall                  stop everything, remove autostart/container/image
  ./troupely.sh status                     which personas are live
  ./troupely.sh login                      Claude subscription login (OAuth); Docker also starts personas
  ./troupely.sh add <archetype> <name> [token]   add + start one persona
  ./troupely.sh pair <name> <code>         approve the pairing code the bot sent you (no code = list pending)
  ./troupely.sh topic <name> <group> <id>  route a persona to a supergroup topic
  ./troupely.sh module list | add <mod> <name>   capability modules (MCP servers + skills)
  ./troupely.sh attach <name>              open a persona's terminal (Ctrl-b d to leave)
  ./troupely.sh logs <name>                a persona's recent terminal output
  ./troupely.sh autostart on|off|status    native: start at login + relaunch crashed personas

First time? Run ./setup.sh.
EOF
}

case "${1:-}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) if [ -n "${2:-}" ]; then cmd_restart_one "$2"; else cmd_restart; fi ;;
  update)  cmd_update ;;
  remove)  shift; cmd_remove "${1:-}" ;;
  uninstall) shift; cmd_uninstall "${1:-}" ;;
  status)  cmd_status ;;
  login)   cmd_login ;;
  add)     shift; cmd_add "${1:-}" "${2:-}" "${3:-}" ;;
  topic)   shift; cmd_topic "${1:-}" "${2:-}" "${3:-}" ;;
  module)  shift; cmd_module "$@" ;;
  pair)    shift; cmd_pair "${1:-}" "${2:-}" ;;
  attach)  shift; cmd_attach "${1:-}" ;;
  logs)    shift; cmd_logs "${1:-}" ;;
  autostart) shift; cmd_autostart "${1:-status}" ;;
  ""|-h|--help|help) usage ;;
  *) say "${c_red}✗ unknown command: $1${c_rst}"; usage; exit 1 ;;
esac
