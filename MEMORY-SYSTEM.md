# Memory System

How a troupely persona remembers across sessions. `RULES.md` imports this file, so every persona
loads it every session. The mechanism is plain files plus a linter: no database, no vector
store, and it works with any model the stack runs on.

One principle: **memory is files a persona writes on purpose, not an automatic log.** A persona
decides what's worth keeping and writes it where a future session will find it. The linter
catches the lapses; the judgment is the persona's.

> This page describes what ships in troupely 1.1. Anything marked **planned** does not exist
> yet. If you find a described feature missing, that's a bug — please report it.

## The four stores

| Store | What it holds | When it's written | Where it lives |
|---|---|---|---|
| **Daily log** | What happened worth surviving: decisions, blockers, pivots, feedback. Dated, append-only. | Same turn as the state change | `personas/<p>/memory/YYYY-MM-DD.md` |
| **Memory index** | One line per durable fact, each pointing at detail. **Loaded into context automatically every session.** | When a fact turns out to be durable | Claude Code's auto-memory `MEMORY.md` ↓ |
| **Memory notes** | One fact or concept per file. The index points at these. | Alongside the index line | Claude Code's auto-memory dir ↓ |
| **Canonical state** | What's true right now: active tasks, priorities, project status. | Same turn as the change | Your choice, e.g. `memory/active-tasks.md`; the orchestrator owns it |

**Where the index and notes actually live.** They are Claude Code's built-in auto-memory, not
loose vault files. Claude Code loads `MEMORY.md` at session start (the first 200 lines / 25 KB),
which is why recall survives a `/clear` and even a model switch. In troupely each persona has
its own HOME, so each has its own store:

```
vault/.claude/homes/<persona>/.claude/projects/<project-key>/memory/MEMORY.md
```

`<project-key>` is derived from the persona's working directory, or from the **git root** if
the vault is inside a git repository. That second case is a trap: if you `git init` the vault
itself, every persona's key can resolve to the same repo root. Each persona still has its own
HOME today, so the stores stay separate. (Planned for 1.1 phase 2: an explicit per-persona
store pin plus a `doctor` check that it's honoured.)

## Writing memory

1. **Same turn, not session end.** If task state changed this turn, the matching daily-log
   entry exists before the user-visible reply. Started, finished, blocked, pivoted, got
   feedback: write it now. "Done" without a memory entry is a bug. Don't log routine reads.
2. **Tag durable lines** at the end with one of `#decision #lesson #feedback #ship #fact`.
   It marks which lines should outlive the day.
3. **Promote what lasts.** A `#fact`, or a `#lesson` / `#feedback` that should change how the
   persona behaves, gets a note in the auto-memory dir plus one index line in `MEMORY.md`.
   Keep index lines short. The index is loaded every session and truncates past its limit, so
   bloat silently drops the newest lines.

## Recall

1. **Index → note.** `MEMORY.md` is already in context. Scan it, follow the pointer.
2. **Grep the daily logs** for "when did we decide X": `grep -rn 'X' personas/*/memory/`.
3. **Follow links** between notes (`[[note-name]]`). A link to a note that doesn't exist yet
   marks something worth writing.

> ⚠️ Recalled memory reflects what was true **when written**. If it names a file, flag or
> function, check it still exists before acting on it.

## Keeping state from drifting

1. **One writer per canonical file.** Others propose changes through that owner's inbox.
2. **Reconcile in the same turn.** When one canonical file changes, update the ones that must
   agree with it in that turn.
3. **Append, don't freeze.** When a "done" item changes, add a dated update line rather than
   leaving the stale "done" as the only truth.
4. **The linter** catches what slips through (below).

## Drain protocol (three states)

Every `inbox/` has a sibling `processing/`:

```
inbox/file.md  →  processing/file.md  →  deleted (or moved to notes/)
   pending           being worked on          done
```

Read → `mv` to `processing/` to claim it → do the work → delete. At session start check
`processing/` **first**: anything there is a task that was interrupted. Empty `processing/`
means caught up. `processing/` is not a waiting room: a thread blocked on a human lives in your
daily log, and the file gets deleted. Helper: `framework/inbox-drain/drain.sh`.

## The linter

`memory/memory_lint.py` is stdlib Python, driven by `memory/memory-lint.config.json`, and exits
nonzero when it finds something. Relative paths resolve against the vault root;
`drain_dirs` paths may be globs. Checks that ship:

| Check | Flags | Config key |
|---|---|---|
| **drain-zombies** | Files stuck in an `inbox/` or `processing/` past a max age | `drain_dirs` (on by default: `personas/*/inbox`, `personas/*/processing`) |
| **compile-age** | A file you expect to be refreshed regularly has gone stale or is missing | `compile_age` |
| **reconcile-drift** | Two files that should change together were edited far apart | `reconcile_pair` |
| **producer-deadman** | An output that should stay fresh is stale or empty | `producers` |

Only `drain_dirs` is configured out of the box. Add the others once you have the files they
watch, e.g.:

```json
"compile_age":    [{ "path": "memory/active-tasks.md", "max_age_hours": 168 }],
"reconcile_pair": { "a": "memory/active-tasks.md", "b": "memory/priorities.md", "max_skew_hours": 48 },
"producers":      [{ "name": "daily-digest", "path": "memory/digest.md", "max_age_hours": 24, "min_bytes": 100 }]
```

Run it from a heartbeat, or at session start if the persona has no heartbeat:

```bash
framework/heartbeat/memory-check.sh   # silent when clean; prints findings and exits nonzero otherwise
```

Treat findings as the current tick's to-do.

**Planned for 1.1 phase 2:** a `drain_lanes` check (lists the lanes it scanned and flags
missing ones, so a typo'd path can't pass as "empty"); an `automemory_index` check (warns at
80% of the index load limit); `memory-index` (full-text search over the logs); and `recall`
(a one-screen session-start state pack). **Planned for 1.2:** debt-triggered compile
(`compile-backlog`), tag fan-out checks, curated-file size limits.

## What ships vs what's yours

- **Ships with troupely (refreshed on update):** this file, `RULES.md`, the linter, the
  framework scripts, the drain convention.
- **Yours (never overwritten):** `CLAUDE.md` at the vault root, `memory/memory-lint.config.json`,
  your personas, their logs, notes and memory. See `examples/memory-example/` for the shape.
