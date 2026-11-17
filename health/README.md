# Health / ops

Keeping a long-running persona stack healthy without a host process manager. The as-run macOS
stack used launchd jobs + host scripts; none of that ports. The **patterns** do, re-homed to
the container + the heartbeat. Three of them:

## 1. Output-freshness watching

The failure these catch: a producer that's *alive but silently degraded* — exit 0, no error,
but its output went stale or empty (a feed 200-ing a cached body, a pipeline that runs and
writes nothing). Status codes lie; freshness doesn't.

- **`output-health.sh`** — config-driven (`output-health.config.json`), stdlib, checks each
  producer for freshness (max age), non-emptiness (min bytes), and an optional content regex
  (catches a silently-empty sub-source inside a present file). Exits nonzero on any down
  producer. Run it on the heartbeat alongside the memory linter:
  ```bash
  health/output-health.sh   # nonzero + findings if a producer is stale/empty/missing pattern
  ```
- For **memory** producers specifically (MEMORY.md, active-tasks, a digest feeding them), the
  memory linter's producer-deadman check already covers this — use that. Use `output-health.sh`
  for non-memory producers (data pipelines, external feeds, scheduled jobs).

When a producer is down, the persona pings the operator (retire it, or fix it) — a degraded
producer that nobody notices is worse than a crashed one.

## 2. Context-watcher → auto-clear + re-orient

A long-lived session fills its context window. The pattern: watch the context budget, and when
it crosses a threshold, **compact or clear, then re-orient** — re-read canonical state, check
`processing/`, and keep exactly one heartbeat job (see `../framework/SESSION-LIFECYCLE.md` → first actions).
The re-orient is the load-bearing half: a clear without a re-orient is amnesia. Modern Claude
Code manages context automatically; the persona's job is to make the *first actions after a
clear* deterministic (orient-first is in the shared rules) so a clear is never lossy.

## 3. Keep-alive

The container keeps the session up (`restart: unless-stopped` + the per-persona tmux session).
For anything load-bearing — a watcher, an executor, a persona whose silence is costly — add an
**out-of-process watchdog** that alerts if the heartbeat goes stale past ~2× its interval. An
in-process check dies with the process, so it must be external. The heartbeat writing a
timestamp each tick is enough for a separate job to watch. Keep it minimal — one watchdog can
cover several personas. See `../framework/SESSION-LIFECYCLE.md` → liveness + recovery.

## Wiring

Add to your heartbeat playbook, next to the memory linter:

```bash
framework/heartbeat/memory-check.sh   # memory drift
health/output-health.sh               # producer freshness (if you have producers)
```

Both are silent on success and nonzero-with-findings on a problem.
