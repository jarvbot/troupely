# Memory example (shape, not data)

A worked example of the [memory system](../../MEMORY-SYSTEM.md) on an **invented,
non-sensitive subject** — a hobby project called *TrailPulse* (texts you when a hiking
trail's conditions change). The rigor is real (decisions, a blocker, a same-turn reconcile, an
atomic note with a wikilink); the subject is fictional so nothing leaks.

This shows you the *shape* a persona's memory takes. Your real `memory/` and `notes/` are
gitignored out of the package — this is the template to recognize, not your content.

```
memory-example/
  memory/
    2026-03-14.md      # a daily log — append-only, written per-turn as state changed
    MEMORY.md          # the compiled index — one line per durable fact, points at detail
    active-tasks.md    # canonical live state (reconciled same-turn with PRIORITIES)
  notes/
    trailpulse-poll-interval.md   # an atomic note, one concept, linked
```

Read them in that order to see the loop: things happen and land in the **daily log**; the
durable distillation gets compiled into **MEMORY.md**; live status lives in **active-tasks**;
a reusable decision becomes an **atomic note** the index points at.
