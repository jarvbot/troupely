# troupely — Docker substrate

One container runs all your personas, each as its own tmux session. This is the default way
to run troupely. `./setup.sh` drives everything below; this page is the reference.

## Quickstart

From the repo root:

```bash
./setup.sh                 # asks about auth + bots, writes .env, builds, starts, logs you in
./troupely.sh status       # which personas are live
./troupely.sh attach <name>    # watch one (Ctrl-b d to leave)
```

By hand, if you'd rather not use the wizard:

```bash
cp .env.example .env       # fill in TROUPELY_PERSONAS, one TROUPELY_TG_TOKEN_<NAME> per persona, auth
mkdir -p vault/personas && cp -R personas/orchestrator vault/personas/<name>
ln -sfn ../.env docker/.env    # so compose's ${VAR} interpolation sees your .env too
./troupely.sh start        # = docker compose -f docker/compose.yaml --env-file .env up -d --build
./troupely.sh login        # subscription only: OAuth, then the container restarts and personas start
```

Plain `docker compose -f docker/compose.yaml up -d` also works. Settings come from the
repo-root `.env` via `env_file`.

## What's in the container

- Each persona gets its **own HOME** at `vault/.claude/homes/<name>/`. That keeps each bot's
  Telegram state (`.claude/channels/telegram/`), pairing list and memory store separate. Auth,
  installed plugins, settings and skills are shared through symlinks.
- One tmux session per persona: `troupely-<name>`. One persona crashing doesn't take the
  others down.
- On every start the entrypoint syncs the shared payload (`RULES.md`, `MEMORY-SYSTEM.md`,
  `framework/`, skills, the memory linter) from the image into the vault. `RULES.md` is always
  refreshed. The vault's `CLAUDE.md` is created once and then belongs to you.
- Everything persists in `vault/` across rebuilds: auth, personas, memory, Telegram state.

## Auth

Telegram personas run on Claude Code channels, which need a **claude.ai subscription login or an
Anthropic Console login**.

- **Subscription (recommended):** a long-lived token. Run `claude setup-token` on any computer
  with Claude Code and paste the token when `./setup.sh` asks (it lands in `.env` as
  `CLAUDE_CODE_OAUTH_TOKEN`). Safe with any number of personas.
- **Subscription, one persona only:** `./troupely.sh login` runs `claude auth login --claudeai`
  in the container and saves one shared credentials file. Two or more personas sharing it
  lose auth after the first refresh.
- **API key / OpenRouter:** set `ANTHROPIC_API_KEY`, or for OpenRouter
  `ANTHROPIC_BASE_URL=https://openrouter.ai/api` + `ANTHROPIC_AUTH_TOKEN=sk-or-...` +
  `ANTHROPIC_API_KEY=""`. Whether channels run on these is not yet verified for this release.
  See `../docs/AUTH-AND-COST.md`.
- **Bedrock / Vertex:** cannot run Telegram personas (no channels).

## Topology

- **One container, N sessions (default).** What `compose.yaml` ships.
- **One container per persona** (planned). The image already supports it, because the
  entrypoint runs whatever roster it's given (`TROUPELY_PERSONAS=<one>`). There's no
  ready-made compose override yet.

## Troubleshooting

- `docker logs --tail 40 troupely` shows why no persona started (no auth, no token, perms).
- Linux "vault is not writable": an earlier `sudo docker …` created root-owned files. Run
  `sudo chown -R $(id -u):$(id -g) vault` and start again.
