#!/usr/bin/env bash
# shellcheck disable=SC2034  # check() takes its condition as a string, so uses are invisible
# W7 (CI): the image builds, and a container with no Claude auth holds with a hint
# instead of crash-looping. Uses its own image tag and container name; never touches a
# running troupely install.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
IMG=troupely-ci:test; NAME="troupely-ci-$$"; T="$(mktemp -d)"
cleanup(){ docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$T" 2>/dev/null || true; }
trap cleanup EXIT

docker build -q -f "$REPO/docker/Dockerfile" --build-arg HOST_UID="$(id -u)" --build-arg HOST_GID="$(id -g)" \
  -t "$IMG" "$REPO" >"$T/build.log" 2>&1
check "image builds" '[ $? -eq 0 ] || { tail -20 "$T/build.log"; false; }'

mkdir -p "$T/vault/personas/alpha"
docker run -d --name "$NAME" --init -t -e HOME=/vault -e TROUPELY_PERSONAS=alpha \
  -e TROUPELY_TG_TOKEN_ALPHA=111:AAAfake -v "$T/vault:/vault" "$IMG" >/dev/null
# Logs go to a file before grep: with pipefail, `docker logs | grep -q` fails when grep
# exits on the first match and docker logs takes SIGPIPE.
logs(){ docker logs "$NAME" >"$T/run.log" 2>&1 || true; }
for _ in $(seq 1 30); do logs; grep -q "No Claude auth found" "$T/run.log" && break; sleep 1; done
check "no auth: hint printed" 'grep -q "No Claude auth found" "$T/run.log"'
sleep 3
check "no auth: container still running" '[ "$(docker inspect -f "{{.State.Running}}" "$NAME")" = true ]'
check "no auth: not restarted" '[ "$(docker inspect -f "{{.RestartCount}}" "$NAME")" = 0 ]'
check "no auth: no persona session started" '! docker exec "$NAME" tmux ls 2>/dev/null | grep -q troupely-'

docker rm -f "$NAME" >/dev/null 2>&1

# With auth (a fake key is enough to get past the guard) the persona's session must start
# AND stay up: a bad claude argv exits at once, after "✓ launched" was already printed.
mkdir -p "$T/vault2/personas/alpha"
docker run -d --name "$NAME" --init -t -e HOME=/vault -e TROUPELY_PERSONAS=alpha \
  -e TROUPELY_TG_TOKEN_ALPHA=111:AAAfake -e ANTHROPIC_API_KEY=sk-ant-fake -v "$T/vault2:/vault" "$IMG" >/dev/null
for _ in $(seq 1 60); do logs; grep -q "troupely-alpha" "$T/run.log" && break; sleep 1; done
sleep 12
check "with auth: no auth hint" '! grep -q "No Claude auth found" "$T/run.log"'
check "with auth: persona session alive 12s after launch" 'docker exec "$NAME" tmux has-session -t =troupely-alpha 2>/dev/null'
docker exec "$NAME" tmux capture-pane -p -t =troupely-alpha: >"$T/pane.txt" 2>&1 || true
check "with auth: heartbeat /loop reached the session" 'grep -q "/loop 30m" "$T/pane.txt"'

docker rm -f "$NAME" >/dev/null 2>&1

# Core install: the three core archetypes, copied the way setup.sh does, all launch and stay up.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$T/vault3/personas"
cp -R "$REPO/personas/orchestrator" "$T/vault3/personas/boss"
cp -R "$REPO/personas/planning" "$T/vault3/personas/plan"
cp -R "$REPO/personas/builder" "$T/vault3/personas/build"
docker run -d --name "$NAME" --init -t -e HOME=/vault -e TROUPELY_PERSONAS=boss,plan,build \
  -e TROUPELY_TG_TOKEN_BOSS=111:AAAfake -e TROUPELY_TG_TOKEN_PLAN=222:AAAfake -e TROUPELY_TG_TOKEN_BUILD=333:AAAfake \
  -e ANTHROPIC_API_KEY=sk-ant-fake -v "$T/vault3:/vault" "$IMG" >/dev/null
for _ in $(seq 1 90); do logs; grep -q "troupely-build" "$T/run.log" && break; sleep 1; done
sleep 12
for p in boss plan build; do
  check "core install: '$p' session alive 12s after launch" "docker exec \"\$NAME\" tmux has-session -t =troupely-$p 2>/dev/null"
done

[ "$FAIL" -eq 0 ] || { echo "--- container log"; logs; tail -40 "$T/run.log"; echo "--- pane"; tail -20 "$T/pane.txt" 2>/dev/null; }
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
