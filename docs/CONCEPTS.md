# troupely concepts — a walkthrough

The mental model + the day-to-day moves. Read top to bottom once; after that it's
a reference.

## Personas & sessions

A **persona** is one agent: a name, a `CLAUDE.md` (its identity + rules), its own
Telegram bot, and its own long-running **session** (a `claude` process in a tmux
session). troupely runs N personas as N sessions side by side. They're independent
— one crashing doesn't take the others down.

You start with one **orchestrator** (your front door) and grow the troupe with
`./troupely.sh add` (or just ask the orchestrator — it has an `add-agent` skill).

```sh
./troupely.sh status            # who's live
./troupely.sh attach <name>     # watch/drive a session (Ctrl-b d to detach)
./troupely.sh add <arch> <name> # add + launch a new agent
./troupely.sh stop | restart    # lifecycle
```

## Pairing — who can talk to a bot

A Telegram bot is publicly addressable, so troupely gates it. The first time
someone DMs a persona's bot, it replies with a pairing code and holds the message.
Approve the code it sent you:

```sh
./troupely.sh pair <name> <code>   # approve exactly that request
./troupely.sh pair <name>          # list pending requests, approves nothing
```

Always approve by code. The bot's username is public, so a stranger can DM it
and sit in the pending list next to you, and a paired sender can run commands on
the persona's machine.

After that their messages flow through. Same command works for native and Docker.

## /loop — making a persona proactive

By default a persona is **reactive**: it answers when you message it, then waits.
A **/loop** makes it **proactive** — it runs a prompt on a recurring interval, so
it can act without you poking it.

**What it is.** `/loop` is a Claude Code command that re-runs a prompt (or another
slash command) on a schedule. The classic use is a **heartbeat**: every N minutes
the persona wakes, runs its standing playbook (check an inbox, poll a source,
advance a task), and goes back to sleep.

**The heartbeat is armed for you.** Every persona starts with
`/loop 30m Heartbeat tick: run the Heartbeat section of your CLAUDE.md…`, so it runs one
tick at launch and every 30 minutes after. Change the interval, or turn it off, in `.env`:

```sh
TROUPELY_HEARTBEAT=1h      # 30m default · off = no heartbeat
./troupely.sh restart <name>
```

What a tick does is the **Heartbeat** section of that persona's `CLAUDE.md`; edit it there.

**Your own loops.** For anything else recurring, attach and add one:

```sh
./troupely.sh attach <name>
# then, inside the session:
/loop 10m check the deploy and tell me when it goes green
```

`10m` is the interval (`5m`, `1h`, …). Omit it to let the model self-pace. A loop you add
by hand lasts for the life of that session (a restart drops it) and expires after 7 days.

**What it's for / best use cases.**
- **Heartbeats** — drain a task/inbox queue, keep state fresh, surface blockers.
- **Watchers** — poll a feed, a price, a CI job, a folder; ping you on change.
- **Recurring digests** — a morning brief, an end-of-day summary.
- **Long autonomous work** — let an agent grind a backlog between check-ins.

**When NOT to.** Don't loop tight intervals to poll something that already notifies
you, and don't loop work that needs a human decision each cycle — that's just
nagging. A good loop is maintenance, not a substitute for a real task.

## Topic routing — one supergroup, many agents

Instead of DMing each bot 1:1, you can put the whole troupe in one Telegram
**supergroup with forum topics**, one topic per persona. Each bot is filtered to
its own topic (`TELEGRAM_TOPIC_FILTER`), so you talk to each agent in its lane and
they don't cross-chatter, and its replies are posted back into that topic. Pick this
in `./setup.sh` (it collects the supergroup id + each persona's topic id) or use
`./troupely.sh topic`. Disable each bot's privacy mode in @BotFather (`/setprivacy` →
Disable) *before* adding it to the group, so it sees non-@mention messages in its topic.

Groups skip pairing, so troupely opens a persona's group only to the people already
paired with it in DM. A persona nobody has paired ignores the group. Step-by-step:
`docs/QUICKSTART.md` → "Group with a topic per persona".

## Extending a persona — skills, tools, MCP servers

The quick path: **modules**. A module bundles MCP servers + skills + required env
into one drop-in capability:

```sh
./troupely.sh module list                 # what's available (e.g. linear)
./troupely.sh module add <module> <name>  # give persona <name> the capability
```

See [`../modules/README.md`](../modules/README.md) for the format and how to author
your own. Under the hood it's the same primitives you can also wire by hand:

- **Skills** — drop a `SKILL.md` under the persona's `.claude/skills/<name>/`
  (in its archetype, so every instance gets it). Skills are scoped capabilities the
  model invokes on demand — the `add-agent` skill the orchestrator ships is one.
- **Tools / MCP servers** — give a persona external tools by adding an `.mcp.json`
  to its dir (or the vault) listing MCP servers. Secrets for those servers go in
  `.env` / the environment, not in the persona files. (MCP servers run alongside the
  session; in Docker, anything they need must be reachable from the container.)
- **Domain capability** — a persona's `CLAUDE.md` + a bundle of skills + the right
  MCP servers is how you turn a generic archetype into a real specialist (a research
  desk, an ops assistant, a trading analyst). Build the bundle once, ship it in the
  archetype, and every agent spun from it inherits the capability.

## Auth & model

All personas share one auth. With a subscription on Docker or Linux that is a
`claude setup-token` token in `.env`; on a Mac running natively it is the Mac's own
Claude login. Metered: a provider key in `.env`. See
[AUTH-AND-COST.md](AUTH-AND-COST.md).
