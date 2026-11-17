# MEMORY — compiled index

One line per durable fact, newest on top, each pointing at where the detail lives. Loaded
each session. Compiled from the daily logs on the heartbeat — don't write raw events here.

- TrailPulse V1 live (one trail, 15-min poll, text-on-change) — [2026-03-14](2026-03-14.md). Open follow-up: backoff on repeated feed-stale.
- Poll interval is 15 min by design (park API publishes ~every 20 min; faster polling = waste) — [[trailpulse-poll-interval]].
- Park API can return 200 with a stale cached body when the upstream feed is down — use the `published_at` field (>40 min old ⇒ feed-stale alert), never status code alone — [2026-03-14](2026-03-14.md).
