---
name: add-agent
description: Add a new agent (persona) to this troupely stack — explains the archetypes, walks the operator through minting a Telegram bot token, and bootstraps the new session. Use when the operator asks to add an agent, add a persona, grow the team/troupe, or spin up a new bot.
---

# Add an agent to the troupe

You are the orchestrator. When the operator wants another agent, guide them through
it conversationally — one step at a time, confirming as you go. A new agent =
a new persona archetype + its own Telegram bot + its own session.

## 1. Pick an archetype

Ask what the new agent is for, then suggest an archetype:

The core team is you plus a planning agent and a builder. Suggest those first:

| Archetype | Good for |
|---|---|
| `planning` | brainstorming, design docs, reviewing (redlining) someone else's plan |
| `builder` | writing code, prototypes, scripts, fixes |

Add-ons, only when a lane clearly needs one (`addons/personas/`):

| Archetype | Good for |
|---|---|
| `specialist` | a focused domain expert (research, analysis, a single capability) |
| `executive-assistant` | scheduling, inbox triage, reminders, errands |
| `orchestrator` | another coordinator (rare — usually you only need one) |

Then pick a short lowercase **name** (e.g. `atlas`, `scout`, `friday`).

## 2. Mint a Telegram bot token

Each agent needs its own bot. Walk the operator through it:

1. Open Telegram, message **@BotFather**.
2. Send `/newbot`, follow the prompts (display name + a username ending in `bot`).
3. BotFather replies with a **token** like `123456789:AAE...`. They keep it: it goes into
   the terminal in step 3, never into this chat.

(If the agent will live in a supergroup topic, also send `/setprivacy` → pick the
bot → **Disable** *before* adding it to the group, so it sees all messages in its topic,
not just @mentions. The operator must pair with it in DM first: the group admits only
paired senders.)

## 3. Add + launch

Have the operator run, from the troupely repo root on the host:

```sh
./troupely.sh add <archetype> <name>    # prompts for the token, input hidden
```

This creates the persona from the archetype, registers it in `.env`, and launches
its session. (Docker installs: run the same command on the host — the container
shares the vault — or rebuild after editing `.env`.)

## 4. Pair the bot

After it's up, have the operator DM the new bot once (it replies asking to pair),
then:

```sh
./troupely.sh pair <name> <code>   # the code the bot sent them
```

Now their DMs reach the agent. Done — confirm the new agent is live and tell them
how to reach it (`./troupely.sh attach <name>` to watch it, or just DM the bot).

## Notes

- One bot per agent. Tokens are secrets — they go in `.env` (gitignored), never in chat.
- Every agent starts with its heartbeat armed (`TROUPELY_HEARTBEAT` in `.env`, 30m default):
  each tick runs the Heartbeat section of its `CLAUDE.md`. For other recurring work, add a
  **/loop** in its session — see `docs/CONCEPTS.md`.
- Remove an agent: the operator runs `./troupely.sh remove <name>` in their own terminal. It
  stops only that agent, drops it from `.env` (roster + token) and archives its files. Its
  Telegram bot still exists: revoke the token in @BotFather (`/revoke`) if it is not coming back.
