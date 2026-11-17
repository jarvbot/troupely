#!/usr/bin/env bash
# troupely interactive setup — model auth, personas, Telegram bots, then launch.
# Safe to re-run: it merges into .env (keys it doesn't manage are kept) and reuses
# persona folders that already exist. Pure bash + curl + python3.
set -euo pipefail
cd "$(dirname "$0")"

c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_grn=$'\033[32m'; c_red=$'\033[31m'; c_ylw=$'\033[33m'; c_cyn=$'\033[36m'; c_rst=$'\033[0m'
say(){ printf '%s\n' "$*" >&2; }
hdr(){ say ""; say "${c_bold}${c_cyn}$*${c_rst}"; }
warn(){ say "${c_ylw}⚠ $*${c_rst}"; }

# ---- arrow-key single-select menu (↑/↓/Enter, number shortcuts; number-on-pipe for non-TTY) ----
CHOICE=0
choose(){
  local prompt="$1"; shift; local opts=("$@"); local n=${#opts[@]} i=0 key k2
  if [ ! -t 0 ]; then
    say "$prompt"; for i in "${!opts[@]}"; do say "  $((i+1))) ${opts[$i]}"; done
    read -r num || num=1; CHOICE=$(( ${num:-1} - 1 )); return
  fi
  say "$prompt ${c_dim}(↑/↓ + Enter, or press a number)${c_rst}"
  printf '\033[?25l' >&2  # hide cursor
  while true; do
    local j
    for j in "${!opts[@]}"; do
      if [ "$j" -eq "$i" ]; then printf "  ${c_grn}❯ %s${c_rst}\n" "${opts[$j]}" >&2
      else printf "    ${c_dim}%s${c_rst}\n" "${opts[$j]}" >&2; fi
    done
    IFS= read -rsn1 key
    if [ "$key" = $'\033' ]; then read -rsn2 -t 0.01 k2 || k2=""; key="$key$k2"; fi
    case "$key" in
      $'\033[A') i=$(( (i-1+n) % n ));;
      $'\033[B') i=$(( (i+1) % n ));;
      ''|$'\n') break;;
      [1-9]) if [ "$key" -le "$n" ]; then i=$(( key-1 )); break; fi;;
    esac
    printf '\033[%dA' "$n" >&2  # cursor back up to redraw
  done
  printf '\033[?25h' >&2  # show cursor
  CHOICE=$i
}
ask(){ local p="$1" def="${2:-}" v; if [ -n "$def" ]; then printf '%s [%s]: ' "$p" "$def" >&2; else printf '%s: ' "$p" >&2; fi; read -r v || v=""; printf '%s' "${v:-$def}"; }
# secrets: no echo, and an existing value is never printed back (Enter keeps it)
ask_secret(){
  local p="$1" def="${2:-}" v
  if [ -n "$def" ]; then printf '%s (Enter keeps the current one): ' "$p" >&2; else printf '%s: ' "$p" >&2; fi
  read -rs v || v=""; printf '\n' >&2
  v="$(printf '%s' "$v" | tr -d '[:space:]')"; printf '%s' "${v:-$def}"
}
upper(){ printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'; }

# ---- .env merge: keys we set go in ENV_SET; everything else already in .env is kept ----
ENV_KEYS=(); ENV_VALS=()
env_set(){ ENV_KEYS+=("$1"); ENV_VALS+=("$2"); }
env_get(){ [ -f .env ] && sed -n "s/^$1=//p" .env | tail -1 | sed -e "s/^'\(.*\)'\$/\1/" -e 's/^"\(.*\)"$/\1/' || true; }

# ---- Telegram checks: the token is real, and nothing else is consuming its updates ----
TG_USER=""
check_token(){
  local tok="$1" me hook
  me="$(curl -fsS --max-time 10 "https://api.telegram.org/bot$tok/getMe" 2>/dev/null || true)"
  TG_USER="$(printf '%s' "$me" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["username"])
except Exception: pass' 2>/dev/null || true)"
  if [ -z "$TG_USER" ]; then
    say "  ${c_red}✗ Telegram doesn't recognise that token.${c_rst} Copy it again from @BotFather (looks like 123456789:AA…)."
    return 1
  fi
  hook="$(curl -fsS --max-time 10 "https://api.telegram.org/bot$tok/getWebhookInfo" 2>/dev/null \
    | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"].get("url",""))
except Exception: pass' 2>/dev/null || true)"
  say "  ${c_grn}✓ token OK — @$TG_USER${c_rst}"
  if [ -n "$hook" ]; then
    warn "@$TG_USER has a webhook set ($hook). Another bot runner (OpenClaw, Hermes…) may still"
    say  "    be attached to this token. Only one program can receive a bot's messages. Stop the"
    say  "    other one, or mint a fresh bot for troupely."
  fi
}
ask_token(){
  local label="$1" existing="$2" tok tries=0
  while true; do
    tries=$((tries + 1))
    [ "$tries" -gt 5 ] && { say "  ${c_red}✗ no valid token after 5 tries — re-run ./setup.sh when you have one.${c_rst}"; exit 1; }
    tok="$(ask_secret "  Bot token for '$label'" "$existing")"
    [ -z "$tok" ] && { say "  (a token is required — see the @BotFather steps above)"; continue; }
    if check_token "$tok"; then printf '%s' "$tok"; return; fi
  done
}

hdr "troupely setup"
say "${c_dim}A few questions. This writes .env, creates your personas under vault/, and starts them.${c_rst}"
[ -f .env ] && say "${c_dim}Found an existing .env — your answers update it; anything else in it is kept.${c_rst}"

# ---- 1. model auth (decides everything downstream) ----
hdr "1) Claude access"
say "${c_dim}Talking to your personas over Telegram uses Claude Code \"channels\", which need a claude.ai"
say "or Anthropic Console login. A Claude Pro or Max subscription is the simplest way in.${c_rst}"
choose "Do you have a Claude Pro or Max subscription?" \
  "Yes — use my subscription (recommended)" \
  "No — I'll use an Anthropic API key (console.anthropic.com)" \
  "No — I'll use OpenRouter"
prov=$CHOICE
A_KEY=""; A_TOK=""; A_URL=""; A_MODEL=""; SUBSCRIPTION=0; OAUTH_TOK=""
case $prov in
  0) SUBSCRIPTION=1
     if [ "${TROUPELY_NATIVE:-0}" = "1" ] && [ "$(uname)" = "Darwin" ]; then
       say "${c_grn}✓ Subscription. Your personas share this Mac's own Claude login (the login Keychain).${c_rst}"
     else
       # Docker / Linux: a shared .credentials.json rotates its refresh token on every refresh and
       # logs the other personas out hours later (W2). A setup-token token never rotates.
       say "${c_dim}With Docker or Linux, use a long-lived token so several personas can share one login"
       say "without logging each other out.${c_rst}"
       choose "How should your personas sign in?" \
         "Long-lived token from 'claude setup-token' (recommended)" \
         "Log in after the container starts (works for ONE persona only)"
       if [ "$CHOICE" -eq 0 ]; then
         say "${c_dim}  On any computer with Claude Code, run: ${c_rst}${c_bold}claude setup-token${c_rst}"
         say "${c_dim}  It opens a browser, you approve, and it prints a token starting sk-ant-oat01-. Paste it below.${c_rst}"
         tries=0
         while :; do
           tries=$((tries + 1))
           OAUTH_TOK="$(ask_secret "  Token" "$(env_get CLAUDE_CODE_OAUTH_TOKEN)")"
           case "$OAUTH_TOK" in
             sk-ant-oat*) break;;
             "") say "  (a token is required, or re-run ./setup.sh and pick the login option)";;
             *) say "  ${c_red}that doesn't look like a setup-token token (sk-ant-oat01-…)${c_rst}";;
           esac
           [ "$tries" -ge 5 ] && { say "  ${c_red}✗ no valid token after 5 tries. Re-run ./setup.sh when you have one.${c_rst}"; exit 1; }
         done
         say "${c_grn}✓ token saved. No login step needed.${c_rst}"
       else
         warn "A shared login works for one persona. With two or more, the others lose auth after the"
         say  "    first token refresh. Switch any time: re-run ./setup.sh and pick the token option."
       fi
     fi;;
  1) A_KEY="$(ask_secret 'Anthropic API key (sk-ant-...)' "$(env_get ANTHROPIC_API_KEY)")"
     warn "API-key auth with Telegram channels is not yet verified for this release. If your bot never"
     say "    answers, see docs/AUTH-AND-COST.md.";;
  2) A_TOK="$(ask_secret 'OpenRouter key (sk-or-...)' "$(env_get ANTHROPIC_AUTH_TOKEN)")"; A_URL="https://openrouter.ai/api"
     warn "OpenRouter with Telegram channels is not yet verified for this release. If your bot never"
     say "    answers, see docs/AUTH-AND-COST.md.";;
esac
say "${c_dim}(Amazon Bedrock and Google Vertex can't run Telegram personas: channels need a claude.ai or"
say "Console login. Other providers: see providers/README.md, no channels.)${c_rst}"

# ---- 2. personas + bots ----
hdr "2) Your orchestrator and its Telegram bot"
say "${c_dim}Each persona is its own Telegram bot. To make one:"
say "  1. In Telegram, open a chat with ${c_rst}${c_bold}@BotFather${c_rst}${c_dim} and send ${c_rst}${c_bold}/newbot${c_rst}"
say "${c_dim}  2. Pick a display name, then a username ending in \"bot\""
say "  3. BotFather replies with a token like 123456789:AAH… — paste it below"
say "  Use a NEW bot. A token that another runner (OpenClaw, Hermes…) is still using won't work.${c_rst}"
# Core archetypes (personas/) are offered by default; add-ons (addons/personas/) only on request.
ARCH=(); ADDONS=()
while IFS= read -r line; do [ -n "$line" ] && ARCH+=("$line"); done < <(find personas -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)
while IFS= read -r line; do [ -n "$line" ] && ADDONS+=("$line"); done < <(find addons/personas -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)
[ "${#ARCH[@]}" -eq 0 ] && { say "✗ no persona archetypes found under personas/"; exit 1; }
arch_dir(){ if [ -d "personas/$1" ]; then printf 'personas/%s' "$1"; else printf 'addons/personas/%s' "$1"; fi; }
ROSTER=(); TOKENS_ARR=()   # parallel arrays (bash 3.2 has no associative arrays)
mkdir -p vault/personas

# copy an archetype into the vault; an existing folder is reused, never nested or overwritten
make_persona(){
  local arch="$1" name="$2"
  if [ -d "vault/personas/$name" ]; then say "  ${c_dim}vault/personas/$name already exists — keeping it${c_rst}"
  else cp -R "$(arch_dir "$arch")" "vault/personas/$name"; fi
}

orch_arch="orchestrator"; [ -d "personas/orchestrator" ] || orch_arch="${ARCH[0]}"
prev_roster="$(env_get TROUPELY_PERSONAS)"
oname="$(ask "Name for your orchestrator" "${prev_roster%%,*}")"; [ -z "$oname" ] && oname="$orch_arch"
oname="$(printf '%s' "$oname" | tr -cd 'A-Za-z0-9_-')"; [ -z "$oname" ] && oname="$orch_arch"
otok="$(ask_token "$oname" "$(env_get "TROUPELY_TG_TOKEN_$(upper "$oname")")")"
make_persona "$orch_arch" "$oname"
ROSTER+=("$oname"); TOKENS_ARR+=("$otok")
say "${c_grn}✓ orchestrator '$oname' ready${c_rst}"

in_roster(){ local x; for x in "${ROSTER[@]}"; do [ "$x" = "$1" ] && return 0; done; return 1; }
# Re-run: every persona already in .env stays, with its token, unless removed on purpose
# (W11: re-running setup used to rebuild the roster from scratch and silently drop them).
if [ -n "$prev_roster" ]; then
  IFS=',' read -r -a PREV <<< "$prev_roster"
  for name in "${PREV[@]}"; do
    name="$(printf '%s' "$name" | tr -cd 'A-Za-z0-9_-')"
    [ -z "$name" ] && continue; in_roster "$name" && continue
    tok="$(env_get "TROUPELY_TG_TOKEN_$(upper "$name")")"
    if [ -z "$tok" ]; then warn "'$name' is in the roster but has no bot token in .env. Skipping it; add it again with ./troupely.sh add."; continue; fi
    ROSTER+=("$name"); TOKENS_ARR+=("$tok")
    say "${c_grn}✓ keeping '$name'${c_rst} ${c_dim}(its token and folder are unchanged)${c_rst}"
  done
fi

choose "Add more agents now, or later?" \
  "Just the orchestrator for now — add more anytime with ./troupely.sh add (recommended)" \
  "Add more agents now (the core team: planning agent + builder; add-ons on request)"
if [ "$CHOICE" -eq 1 ]; then
  # The picker offers the core team only; the orchestrator is already added above.
  PICK=(); for a in "${ARCH[@]}"; do [ "$a" = "$orch_arch" ] || PICK+=("$a"); done
  while true; do
    if [ "${#ADDONS[@]}" -gt 0 ]; then
      choose "Add an agent (pick an archetype, or finish):" "${PICK[@]}" "Add-on archetypes…" "✓ Done"
      [ "$CHOICE" -eq $(( ${#PICK[@]} + 1 )) ] && break
      if [ "$CHOICE" -eq "${#PICK[@]}" ]; then
        choose "Add-on archetype (optional extras, not part of the core team):" "${ADDONS[@]}" "← back"
        [ "$CHOICE" -eq "${#ADDONS[@]}" ] && continue
        arch="${ADDONS[$CHOICE]}"
      else arch="${PICK[$CHOICE]}"; fi
    else
      choose "Add an agent (pick an archetype, or finish):" "${PICK[@]}" "✓ Done"
      [ "$CHOICE" -eq "${#PICK[@]}" ] && break
      arch="${PICK[$CHOICE]}"
    fi
    name="$(ask "  Name for this $arch agent" "$arch")"
    name="$(printf '%s' "$name" | tr -cd 'A-Za-z0-9_-')"
    [ -z "$name" ] && { say "  skipped (empty name)"; continue; }
    in_roster "$name" && { say "  '$name' is already in your roster"; continue; }
    tok="$(ask_token "$name" "$(env_get "TROUPELY_TG_TOKEN_$(upper "$name")")")"
    make_persona "$arch" "$name"
    ROSTER+=("$name"); TOKENS_ARR+=("$tok")
    say "${c_grn}  ✓ added '$name' (from $arch)${c_rst}"
  done
fi

# ---- 2b. Telegram routing (DM vs supergroup-topic) ----
hdr "2b) Telegram routing"
choose "How will you talk to your personas?" \
  "Direct messages — DM each bot (simplest; recommended to start)" \
  "One group with a topic per persona"
ROUTING=$CHOICE
TG_GROUP=""; TOPICS_ARR=()
if [ "$ROUTING" -eq 1 ]; then
  say "${c_dim}Setup for a group:"
  say "  1. For each bot, in @BotFather: ${c_rst}${c_bold}/setprivacy${c_rst}${c_dim} → pick the bot → ${c_rst}${c_bold}Disable${c_rst}${c_dim}."
  say "     Do this BEFORE adding the bot: the setting only applies to groups it joins afterwards."
  say "  2. Create a Telegram group, then in its settings turn on ${c_rst}${c_bold}Topics${c_rst}${c_dim} (it becomes a \"supergroup\")."
  say "  3. Create one topic per persona (not General) and add every bot to the group."
  say "  4. In each topic, send a message that @mentions that topic's bot.${c_rst}"
  ask "Press Enter once you've sent those messages" "" >/dev/null
  found="$(curl -fsS --max-time 10 "https://api.telegram.org/bot$otok/getUpdates" 2>/dev/null | python3 -c '
import json, sys
try: ups = json.load(sys.stdin).get("result", [])
except Exception: ups = []
seen = {}
for u in ups:
    m = u.get("message") or u.get("edited_message") or {}
    c = m.get("chat", {})
    if c.get("type") == "supergroup":
        tid = m.get("message_thread_id")
        name = (m.get("reply_to_message", {}).get("forum_topic_created") or {}).get("name", "")
        seen.setdefault(c["id"], [c.get("title", ""), {}])
        if tid: seen[c["id"]][1][tid] = name or seen[c["id"]][1].get(tid, "")
for gid, (title, topics) in seen.items():
    print(f"group {gid}  \"{title}\"")
    for tid, n in topics.items(): print(f"   topic {tid}  {n}")
' 2>/dev/null || true)"
  if [ -n "$found" ]; then say "${c_grn}Here's what your orchestrator's bot saw:${c_rst}"; say "$found"
  else say "${c_dim}Couldn't auto-detect (the orchestrator's bot saw no group messages). Forward a topic message to @RawDataBot to read the IDs.${c_rst}"; fi
  while :; do
    TG_GROUP="$(ask 'Group ID (starts with -100)' "$(env_get TROUPELY_TG_GROUP)")"
    [[ "$TG_GROUP" =~ ^-100[0-9]+$ ]] && break; say "${c_red}  that's not a supergroup id (-100…)${c_rst}"
  done
  for idx in "${!ROSTER[@]}"; do
    while :; do
      TOPICS_ARR[$idx]="$(ask "  Topic ID for '${ROSTER[$idx]}'" "$(env_get "TROUPELY_TG_TOPIC_$(upper "${ROSTER[$idx]}")")")"
      [[ "${TOPICS_ARR[$idx]}" =~ ^[0-9]+$ ]] && break; say "${c_red}  topic id must be a number${c_rst}"
    done
  done
  say "${c_grn}✓ topic routing set${c_rst}"
fi

# ---- 3. write .env (merge) ----
hdr "3) Writing .env"
MODE=docker; [ "${TROUPELY_NATIVE:-0}" = "1" ] && MODE=native
env_set TROUPELY_MODE "$MODE"
env_set HOST_UID "$(id -u)"
env_set HOST_GID "$(id -g)"
env_set TROUPELY_PERSONAS "$(IFS=,; echo "${ROSTER[*]}")"
env_set ANTHROPIC_API_KEY "$A_KEY"
env_set CLAUDE_CODE_OAUTH_TOKEN "$OAUTH_TOK"
env_set ANTHROPIC_AUTH_TOKEN "$A_TOK"
env_set ANTHROPIC_BASE_URL "$A_URL"
[ -n "$A_MODEL" ] && env_set ANTHROPIC_MODEL "$A_MODEL"
for idx in "${!ROSTER[@]}"; do env_set "TROUPELY_TG_TOKEN_$(upper "${ROSTER[$idx]}")" "${TOKENS_ARR[$idx]}"; done
if [ "$ROUTING" -eq 1 ]; then
  env_set TROUPELY_TG_GROUP "$TG_GROUP"
  for idx in "${!ROSTER[@]}"; do env_set "TROUPELY_TG_TOPIC_$(upper "${ROSTER[$idx]}")" "${TOPICS_ARR[$idx]}"; done
fi
args=(); for idx in "${!ENV_KEYS[@]}"; do args+=("${ENV_KEYS[$idx]}=${ENV_VALS[$idx]}"); done
python3 lib/envfile.py .env "${args[@]}" || { say "${c_red}✗ .env write failed${c_rst}"; exit 1; }
# docker compose reads ${VAR} interpolation from docker/.env; point it at the real one
ln -sfn ../.env docker/.env
say "${c_grn}✓ .env updated${c_rst} (personas: ${ROSTER[*]}, mode: $MODE)"

# ---- 4. launch ----
hdr "4) Launch"
next_steps(){
  say ""
  say "${c_bold}Last step — say hi:${c_rst}"
  say "  1. In Telegram, DM ${c_bold}@$1${c_rst}. It replies with a pairing code."
  say "  2. Here, run: ${c_bold}./troupely.sh pair ${ROSTER[0]}${c_rst}"
  say "  3. DM it again. Your orchestrator answers."
  say ""
  say "${c_dim}./troupely.sh with no arguments lists every command. Something off? ./troupely.sh status${c_rst}"
}
# remember the orchestrator's @username for the closing screen
check_token "${TOKENS_ARR[0]}" >/dev/null 2>&1 || true
ORCH_USER="${TG_USER:-your_orchestrator_bot}"

if [ "$MODE" = "native" ]; then
  say "${c_grn}✓ ready for native launch.${c_rst}"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  say "${c_red}✗ Docker isn't installed.${c_rst} Install Docker (docs.docker.com/get-docker), then: ${c_bold}./troupely.sh start${c_rst}"
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  say "${c_red}✗ Docker Compose v2 not found.${c_rst} Ubuntu/Debian: ${c_bold}sudo apt-get install -y docker-compose-plugin${c_rst}"
  say "  Then: ${c_bold}./troupely.sh start${c_rst}"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  say "${c_red}✗ Docker is installed but not running (or you lack permission).${c_rst}"
  say "  Start Docker (Linux: ${c_bold}sudo systemctl start docker${c_rst}; add yourself to the docker group), then: ${c_bold}./troupely.sh start${c_rst}"
  exit 1
fi

choose "Build and start troupely now? (the first build takes a few minutes)" "Yes" "No — I'll run ./troupely.sh start later"
[ "$CHOICE" -eq 0 ] || { say "When ready: ${c_bold}./troupely.sh start${c_rst}"; exit 0; }
./troupely.sh start
if [ "$SUBSCRIPTION" -eq 1 ] && [ -z "$OAUTH_TOK" ]; then
  hdr "5) Log in with your Claude subscription"
  say "${c_dim}This prints a URL. Open it in any browser, approve, and paste the code back here.${c_rst}"
  ./troupely.sh login || { say "Login didn't finish. Run ${c_bold}./troupely.sh login${c_rst} again."; exit 1; }
fi
next_steps "$ORCH_USER"
