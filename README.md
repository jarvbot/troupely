# troupely

A portable, **bring-your-own-model** multi-persona [Claude Code](https://claude.com/claude-code)
stack. `docker run` it and you have a small team of long-running agent personas — an
orchestrator, a planning agent and a builder — each on its own Telegram channel, planning
with rigor and remembering across sessions. MIT licensed.

The bet: **the discipline travels with the personas.** A freshly-stripped persona
plans, researches, red-teams, files, and *remembers* like a senior one — because
the planning skill, the file-convention memory system, and the heartbeat ship with
it. Proven live: a persona's memory survived a context wipe **and a model swap**
(Claude → DeepSeek) and it recalled its own design cold.

<!-- DEMO: hero-demo asciinema/GIF goes here -->

## Quick start

You need: Docker (Linux or Mac), a Telegram account, and ideally a **Claude Pro or Max
subscription**. Telegram personas run on Claude Code channels, which need a claude.ai or
Anthropic Console login.

```sh
git clone https://github.com/jarvbot/troupely.git && cd troupely
./setup.sh
```

`setup.sh` asks a few questions with arrow-key menus:

1. **Claude access.** Your subscription (recommended), an Anthropic API key, or OpenRouter.
2. **Your orchestrator's Telegram bot.** It shows the @BotFather steps, checks the token
   against Telegram, and warns if the token is still attached to another bot runner.
3. **Your core team.** Start with just the orchestrator, or add the planning agent and the
   builder now (each needs its own bot). That's the whole default install; add-ons are below.
4. **DMs or a group with topics.** DMs are simplest. For a group it walks you through topics,
   privacy mode, and finding the IDs.

It writes `.env`, builds and starts the container, and runs the subscription login. The login
prints a URL: open it in any browser, approve, and paste the code back. Then:

1. DM your bot in Telegram. It replies with a pairing code.
2. Run `./troupely.sh pair <name> <code>` with the code it sent you.
3. DM it again. Your orchestrator answers.

Re-running `./setup.sh` is safe: it updates `.env` instead of overwriting it. `./troupely.sh`
with no arguments lists every command. Full walkthrough:
[`docs/QUICKSTART.md`](docs/QUICKSTART.md).

### The core three, and add-ons

The default install is three personas, and it's all a working stack needs:

| Persona | Does |
|---|---|
| **orchestrator** | routes work, holds canonical state, keeps you in the loop |
| **planning** | turns rough ideas into build-ready designs, and redlines plans other people wrote |
| **builder** | takes a scoped design to a working, tested prototype |

Everything else is opt-in. Add-on personas (`specialist`, `executive-assistant`) live in
`addons/personas/`: pick "Add-on archetypes…" in `setup.sh`, or run
`./troupely.sh add specialist <name>`. Capability modules (`modules/`) attach MCP servers and
skills to one persona: `./troupely.sh module add <module> <name>`. See
[`modules/README.md`](modules/README.md).

### No Docker? Native install (Linux or Mac)

You can run troupely directly on the host, without Docker or compose:

```sh
git clone https://github.com/jarvbot/troupely.git && cd troupely
./install.sh      # installs Claude CLI + bun + tmux, runs onboarding, launches your personas
```

`install.sh` installs the runtime (apt on Debian/Ubuntu, Homebrew on a Mac), reuses the same
onboarding as above, then runs each persona as a host **tmux** session. Plugin and Telegram
state lives under `./vault`, so it never touches your own `~/.claude`. Run
`./troupely.sh login` once to set up the subscription login:

- **Mac:** personas use **your Mac's normal Claude Code login**, shared through the login
  Keychain. If you're already logged in to Claude Code, `login` just confirms it. Every persona
  then runs on that subscription, with no separate token to manage. Logging out of Claude Code
  logs them out too.
- **Linux:** `login` runs the OAuth flow and saves the login in `./vault`. With 2+ personas,
  prefer `claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN` in `.env` (see
  [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)).

Once one persona answers, it can help with the rest. Each ships with a `troupely-ops` skill,
so from Telegram you can ask "bob isn't answering, check it" or "how do I add a researcher?"
and get the exact command. In native mode a persona can run the CLI itself (route a topic,
restart one persona); in Docker it can't reach the host CLI, so it hands you the command.
Three things always stay with you: minting bot tokens in @BotFather, pasting them at the
`./troupely.sh add` prompt (never in chat), and pairing approvals (`./troupely.sh pair`).
Manage the stack by hand with:

```sh
./troupely.sh status              # who's live
./troupely.sh add <arch> <name>   # add + launch a new agent from an archetype
./troupely.sh module add <m> <n>  # give a persona a capability module (MCP + skills)
./troupely.sh topic <n> <grp> <id># route a persona to a supergroup topic
./troupely.sh pair <name> <code>  # approve the pairing code the bot sent you
./troupely.sh attach <name>       # attach to a persona (Ctrl-b d to detach)
./troupely.sh restart [name]      # all, or just one persona
./troupely.sh stop                # stop everything
./troupely.sh update              # pull the latest (Docker rebuilds; native: restart after)
./troupely.sh remove <name>       # stop one persona, drop it from .env, archive its files
./troupely.sh uninstall           # stop everything, remove container/image or autostart
./troupely.sh autostart on        # native: start at login, relaunch crashed personas
```

**Pairing:** when someone first DMs a persona's bot, it replies with a pairing
code and holds the message. Approve that one code with `./troupely.sh pair <name> <code>`.
Bot usernames are public, so anyone can DM your bot and get a code too; approving by code
means only the person you meant gets in. `pair <name>` with no code just lists who's waiting. This edits the persona's
`access.json` directly, so it works for **both** the native and Docker installs
(the container mounts this same `vault/`) — no `docker exec`, no hand-edited JSON.

**Security model, read this:** every persona runs Claude Code with
`--dangerously-skip-permissions` so it can work unattended. Anyone you pair with a bot can make
it run any command, with no confirmation. Pair only yourself (or people you'd hand a shell
to). In the **Docker** install that shell is boxed into the container and `./vault`. In the
**native** install it is your user account on that machine: files, SSH keys, browser
sessions, everything. Use Docker unless the machine is dedicated to troupely. When something breaks:
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

New to the moving parts — personas, **/loop** & heartbeats, pairing, topic routing,
adding agents, extending with skills/MCP? See the walkthrough:
[`docs/CONCEPTS.md`](docs/CONCEPTS.md).

## Why troupely

- **It is Claude Code.** Each persona is a real Claude Code session on your own subscription,
  not a wrapper around an API. Other backends (Bedrock, Vertex, OpenAI-compatible models via
  LiteLLM) are available through `providers/`, but they can't run Telegram personas.
- **Stripped personas aren't inert.** Each archetype is a thin `CLAUDE.md`, but it
  ships *with the capabilities* — the planning skill, the memory system, the
  heartbeat — so it does real work from message one.
- **Memory you can read.** Files + git + a heartbeat linter, not a black-box vector
  store. You can grep it; the linter catches drift.
- **Adapters, not keys.** Connect Telegram, Linear, any MCP server, or your own
  tools via documented patterns — secrets stay in your env, never the repo.
- **Ships the architecture, never the instance.** Conventions, skeletons, templated
  configs, one sanitized example each. A `.gitignore` + a pre-commit secret-scan
  hook enforce it.

## The hero demo

DM the `planning` persona *"worth building a trail-status notifier?"* and it
pressure-tests the idea → invokes the **planning skill** → fans out research
sub-agents → writes a design doc with a defended recommendation → spawns a
**red-team** that attacks it → folds the fixes in → files the locked design → logs
a memory pointer. Next heartbeat, it **recalls the decision from memory**.

Every step runs on the base toolset — model + Telegram + filesystem + sub-agents +
memory, no external connectors. Full narrative + the real artifact:
[`docs/SHOWCASE.md`](docs/SHOWCASE.md) · [`examples/design-docs/trailpulse-notifier.md`](examples/design-docs/trailpulse-notifier.md).

## What's inside

| | |
|---|---|
| `personas/` | the core three archetypes: orchestrator, planning, builder |
| `skills/planning/` | the design-doc / research / red-team workflow, plus a redline mode for reviewing someone else's plan |
| `addons/personas/` | optional archetypes: specialist, executive-assistant |
| `modules/` | optional capability bundles (MCP servers + skills): crypto-signals, crypto-research, linear |
| `memory/` · `MEMORY-SYSTEM.md` | file-convention memory + the drift linter |
| `framework/` | heartbeat + three-state inbox-drain bones |
| `providers/` | model profiles + `providers/troupely-provider` quick-switch |
| `adapters/` | Linear / MCP / mint-bot integration notes (READMEs, no code); Telegram is the built-in channel plugin |
| `docker/` | the container substrate (one image, N personas) |
| `docs/` · `examples/` | quickstart, showcase, auth/cost, sanitized samples |

## Bring your own model & connectors

Model auth and cost levers: [`docs/AUTH-AND-COST.md`](docs/AUTH-AND-COST.md). Wire a
new integration via the [`adapters/`](adapters/) patterns — drop any MCP server into
a persona's config, or add a local CLI tool as a skill.

## License

MIT — see [`LICENSE`](LICENSE).
