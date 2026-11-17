# Quickstart

From zero to a persona that answers you on Telegram. The only thing the host needs is Docker
(Linux or Mac). Without Docker (Linux or Mac), see "Native install" in the README; problems: docs/TROUBLESHOOTING.md.

## Before you start

- **Docker** with Compose v2 (`docker compose version` works). On Linux, your user should be
  in the `docker` group.
- **A Claude Pro or Max subscription** (recommended). Telegram personas run on Claude Code
  channels, which need a claude.ai or Anthropic Console login. An Anthropic API key or OpenRouter
  may work too; see `docs/AUTH-AND-COST.md`.
- **Telegram**, on your phone or desktop.

## 1. Clone and run setup

```bash
git clone https://github.com/jarvbot/troupely.git && cd troupely
./setup.sh
```

## 2. Make a bot when setup asks

1. In Telegram, open **@BotFather** and send `/newbot`.
2. Give it a display name, then a username ending in `bot`.
3. Copy the token it sends (`123456789:AAH…`) and paste it into setup.

Setup checks the token with Telegram. Use a **new** bot: if the token is still attached to
another bot runner (OpenClaw, Hermes, a webhook), setup warns you, and only one program can
receive that bot's messages.

**DMs or a group?** Pick DMs to start. You can move to a group later; see
"Group with a topic per persona" below.

## 3. Build, start, log in

Setup offers to build and start. The first build downloads the base image and Claude Code, so
it takes a few minutes. With a subscription, it then runs the login:

1. It prints a long URL. Open it in any browser, on any machine, and approve.
2. Paste the code it shows back into the terminal.

The container restarts by itself and your personas start. Check with `./troupely.sh status`.

## 4. Pair and say hi

1. DM your bot. It replies with a pairing code. That's access control: nobody can talk to
   your persona until you approve them.
2. Run `./troupely.sh pair <name> <code>` with the code it sent you. Don't approve a code
   you didn't get yourself: anyone can DM a bot.
3. DM it again. It answers.

## Group with a topic per persona (optional)

One Telegram group, one topic per persona: each bot answers only in its own topic, so you can
see every agent in one place without them talking over each other.

1. **Pair each persona in DM first** (step 4). A group admits only the people paired with that
   persona. Until someone has paired, the persona ignores the group.
2. **Turn privacy off before the bot joins.** @BotFather → `/setprivacy` → pick the bot →
   Disable. Otherwise the bot only sees messages that @mention it. The setting applies when
   the bot joins a group, so for a bot that's already in, remove it and add it back.
3. **Make the group.** Create it, then turn on Topics in its settings (it becomes a
   "supergroup"). Create one topic per persona. Don't use General, which can't be routed.
   Add every bot.
4. **Tell troupely the IDs.** Either rerun `./setup.sh` and pick the group option (after you
   @mention each bot once in its topic, it reads the IDs for you), or set them per persona:

   ```bash
   ./troupely.sh topic <name> <group_id> <topic_id>   # group id starts with -100
   ./troupely.sh restart
   ```

   To find the IDs by hand, forward a message from the topic to @RawDataBot. `chat.id` is the
   group ID and `message_thread_id` is the topic ID.
5. **Check it.** Post in each topic. Its persona answers there; the others stay quiet.

Pair someone new later and they're let into the group straight away, no restart needed.

## Day to day

```bash
./troupely.sh                      # every command
./troupely.sh status               # who's live
./troupely.sh attach <name>        # watch a persona's session (Ctrl-b d to leave)
./troupely.sh add builder <name>   # another persona: make its bot first, it asks for the token
./troupely.sh restart [name]       # after editing .env; with a name, only that persona
./troupely.sh update               # pull the latest version (Docker rebuilds; native: restart after)
./troupely.sh remove <name>        # stop one persona, drop it from .env, archive its files
./troupely.sh uninstall            # stop everything, remove the container/image or autostart
```

Each persona runs its heartbeat (the Heartbeat section of its `CLAUDE.md`) every 30 minutes,
armed at launch. Change it with `TROUPELY_HEARTBEAT=1h` (or `off`) in `.env`, then restart.
Docker relaunches a crashed persona by itself; native mode does after `./troupely.sh autostart on`.

Leaving for good: `uninstall`, then `/revoke` each bot in @BotFather. Your `vault/` and `.env`
stay on disk until you delete them (they hold your logins and Telegram state).

Your personas live in `vault/personas/<name>/CLAUDE.md`. Edit them freely. Stack-wide rules of
your own go in `vault/CLAUDE.md`. Don't edit `vault/RULES.md`: troupely refreshes it on
every start so new rules reach you.

## What `--dangerously-skip-permissions` means here

Each persona runs Claude Code with permission prompts off, because nobody is at the terminal
to click "allow." Inside the container a persona can read and write anything in `vault/` and
run commands in the container, but it can't reach the rest of your machine. That's the reason
Docker is the recommended path. In native mode the same flag applies directly on your host.

## Troubleshooting

| Symptom | Check |
|---|---|
| Bot never answers | `./troupely.sh status`. No sessions? `docker logs --tail 40 troupely` says why (no auth, no token). |
| "No Claude auth found" in the logs | `./troupely.sh login` |
| Bot replies with a pairing code every time | `./troupely.sh pair <name> <code>`, then DM again |
| Group messages ignored | Not paired in DM yet (`./troupely.sh pair <name> <code>`), or privacy mode still on: @BotFather → `/setprivacy` → Disable, then remove and re-add the bot to the group |
| Persona silent in its topic | Wrong topic ID (it only hears its own): `./troupely.sh topic <name> <group> <id>`, then `./troupely.sh restart <name>` |
| Linux: "vault is not writable" | `sudo chown -R $(id -u):$(id -g) vault`, then `./troupely.sh start` |
| Token rejected by setup | Copy it again from @BotFather; `/token` there re-shows it |

## Where things live

`vault/` is everything that's yours: personas, memory, auth, Telegram state. It's gitignored and
survives rebuilds. In the repo: `personas/` archetypes · `skills/planning/` the design workflow
· `framework/` heartbeat + inbox drain · `memory/` the linter · `providers/` other model
backends · `adapters/` connectors · `docker/` the container (details in `docker/README.md`).
