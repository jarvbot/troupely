# Heartbeat

A persona stays alive and self-maintaining by running a periodic **heartbeat** — a short
maintenance playbook on a timer. It's how inboxes get drained, memory gets logged, and drift
gets caught without waiting for the operator to prompt.

## How it fires

The heartbeat is a prompt re-enqueued on an interval. In Claude Code, run it with `/loop`:

```
/loop 30m <your heartbeat prompt>
```

…fires the prompt every ~30 minutes while the session is idle. **troupely arms this for you:**
every launch (`start`, `restart`, the Docker supervisor relaunching a dead session) starts the
persona with that `/loop` as its first message. Set the interval in `.env`:

```
TROUPELY_HEARTBEAT=30m     # default · 15m, 2h, … · off = no heartbeat
```

Busy stacks: 15–30 min; quiet ones: hourly. Changing it takes effect at the next
`./troupely.sh restart <name>`.

> **Seven-day expiry.** Claude Code expires recurring jobs after 7 days. The armed prompt
> renews itself: the launcher touches `~/.troupely-heartbeat-armed` in the persona's HOME,
> and once that file is 6 days old the tick deletes the job, creates it again and touches the
> file. A `restart <name>` also resets it.
>
> **Don't stack them.** `/clear` does NOT cancel a loop, so the armed heartbeat keeps firing
> after a clear. Never create a second one on re-orient; if `CronList` shows more than one
> heartbeat, cancel the extras.

## The playbook (each tick)

Keep it tight — heartbeats are maintenance, not deep work.

1. **Drain `processing/` then `inbox/`.** Resume any in-flight item first (a non-empty
   `processing/` = unfinished work), then handle new arrivals. For each: accept + do, clarify
   back, or decline. Don't let briefs rot. (See `../inbox-drain/`.)
2. **Keep the operator in the loop.** On accepting a cross-persona handoff, one line to the
   operator; on done/blocked, one line with the result or the blocker. (See the shared rules.)
3. **Log state.** Anything since the last tick worth surviving — shipped / blocked / pivoted /
   feedback — to today's daily log. Skip if nothing happened.
4. **Run the memory linter.** `./memory-check.sh` — fix anything it flags (stale index to
   compile, a drain zombie, a reconcile drift, a dead producer).
5. **Note active-work state** if you're mid-build, so a fresh session resumes cleanly.

If nothing needs attention, reply `HEARTBEAT_OK` and stop. Don't manufacture work.

## Files

- `memory-check.sh` — runs the memory linter; exits nonzero + prints findings on drift.
- Per-persona heartbeat specifics live in each persona's own `CLAUDE.md` → Heartbeat section.
