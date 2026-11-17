---
project: trailpulse
topic: change-notifier
tier: design-doc
status: locked
builder: builder-persona
date: 2026-03-13
estimate: weekend
---

# Design Doc — TrailPulse · change-notifier

> Example artifact (shape, not real data). A filled-in `design-doc`-tier output from the
> `planning` skill, on the invented "TrailPulse" subject — real rigor, nothing sensitive. This
> is what a persona produces before handing a build off.

## Problem

I want a text when a specific hiking trail's official status changes (open ⇄ closed ⇄
conditions-advisory), so I stop manually checking the park page before driving out. Today it's a
manual check I forget half the time, and a wasted drive when I do.

## Goals / Non-goals

**Goals (V1):**
- Watch ONE trail's official status; text me on a real change.
- Don't false-alarm on a flapping/cached feed.

**Non-goals (deferred):** multiple trails · user accounts · a UI · push beyond SMS/Telegram ·
predicting conditions (only reporting the official status).

## Research

| Agent | Angle | Key finding |
|---|---|---|
| 1 | Park status data source | Park publishes a JSON status endpoint, updated ~every 20 min, with a `published_at` field. |
| 2 | Polling vs webhook | No webhook offered. Polling is the only option. |
| 3 | Prior art (status-change notifiers) | Common pattern: poll → hash the meaningful field → compare to last → notify on diff. Pitfall everyone hits: alerting on cosmetic field churn. |
| 4 | Failure mode | Endpoint returns HTTP 200 with a **stale cached body** when the upstream feed is down — looks healthy, isn't. |

### Aggregated findings
- The feed gives `status` + `published_at`. Hash `status`, not the whole body (avoids cosmetic churn — finding 3).
- 200-with-stale-body (finding 4) means status code alone can't distinguish "no change" from "feed dead." `published_at` is the freshness signal.

## Options considered

| Option | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| A | Poll every 5 min, diff `status` | Fast detection | 3× requests for no gain (feed updates ~20 min); risks rate limit | weekend |
| B | Poll every 15 min, diff `status`, treat `published_at` >40 min old as feed-stale | Matches feed cadence; handles the dead-feed case | Up to ~15 min detection lag | weekend |
| C (do nothing) | Keep checking manually | Zero build | The actual problem | — |

## Recommended approach

**Option B.** Detection lag of ≤15 min is fine for "should I drive out"; it stays under the
feed's own ~20-min publish cadence so a real change is caught within one cycle, at a third of
A's request volume. The `published_at` freshness guard is what makes it trustworthy — without
it, a dead feed reads as "no change" forever, which is the silent failure that makes a notifier
worse than useless.

## Architecture

- **Data model:** last-seen `{status, published_at}` in a small local JSON file. That's the
  whole state.
- **Flow:** poll → if `published_at` older than 40 min → alert "feed stale", don't compare; else
  if `status` changed since last-seen → notify + persist new state.
- **Interface:** one scheduled function; config = trail endpoint URL, poll interval, notify
  target. Errors recoverable (network blip → skip this cycle); a 4xx/5xx run logs + continues.
- **Notify:** reuse the stack's Telegram channel.

## Testing strategy
- **Smoke:** run once against the live endpoint, force a state file with a different status,
  confirm a notify fires.
- **Chaos:** stale `published_at` → feed-stale alert (not silence); network error → skip, no crash.

## Observability
- Errors → stderr + a Telegram ping. Optional: a heartbeat line so the watcher's own liveness is
  visible (a notifier that silently dies is the worst outcome).

## Adversarial review

Red-team finding: *"What happens when the feed is dead for 6 hours — do I get pinged every 15
min?"* → Real. **Revised:** feed-stale alerts get exponential backoff capped at hourly (don't
re-alert every cycle while a feed stays down). Logged below.

Red-team finding: *"`published_at` in a timezone you didn't parse → every poll looks stale."* →
Real. **Revised:** parse `published_at` as UTC explicitly; add a startup self-check that the
parsed age is sane (<24h on first run) or it refuses to run.

## Decision log

| Decision / finding | Resolution + why |
|---|---|
| Poll interval 15 min | Matches ~20-min feed cadence; 5-min (option A) is 3× cost for no gain. |
| Diff `status` only, not whole body | Avoids cosmetic-churn false alarms (research finding 3). |
| `published_at` >40 min ⇒ feed-stale | Status code can't detect a dead feed (finding 4); freshness can. |
| Backoff on repeated feed-stale | Red-team: a 6h outage would spam every 15 min. Cap at hourly. |
| Parse `published_at` as UTC + sanity-check | Red-team: TZ mismatch would make everything look stale. |
