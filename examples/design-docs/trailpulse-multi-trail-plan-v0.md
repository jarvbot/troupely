---
project: trailpulse
topic: multi-trail
author: operator (first draft)
date: 2026-04-02
status: draft, sent for review
---

# TrailPulse: watch every trail in the park (plan v0)

> Example artifact (invented subject, nothing real). A deliberately rough first-draft plan, the
> kind of thing that lands on a planning agent for review. Its redline is
> `trailpulse-multi-trail-redline.md`, produced with the `planning` skill's redline mode.

## What

The single-trail notifier works (see `trailpulse-notifier.md`). Extend it to every trail in the
park (about 140), and let friends subscribe to the trails they care about.

## Plan

1. **Poll every trail every 5 minutes.** One request per trail to the park's status endpoint,
   so we hear about changes fast. 140 trails × 12 per hour is fine, it's a public endpoint.
2. **Store everything in one JSON file**, `state.json`: last status per trail plus the
   subscriber list. The poller and the signup bot both read and write it.
3. **Subscriptions over Telegram.** Friends message the bot `/watch <trail name>`. We match
   the name against the park's trail list with fuzzy matching so typos work.
4. **Alerts:** when a trail's status changes, message every subscriber of that trail.
5. **Reuse the single-trail logic** for change detection: diff the `status` field, treat a
   `published_at` older than 40 minutes as a stale feed.
6. **Run it on the same small VPS** as the current notifier.

## Done when

- All trails are watched.
- Friends can subscribe and get alerts.
