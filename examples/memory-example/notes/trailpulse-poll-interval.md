# TrailPulse poll interval — why 15 minutes

**Decision:** poll the park API every 15 minutes for trail status.

**Why:** the park feed publishes at most about every 20 minutes (the `published_at` timestamps
never move faster than that). Polling every 5 minutes triples the request volume for zero extra
freshness — you just re-read the same body twice before it changes. 15 min stays comfortably
under the publish cadence so a real change is caught within one cycle, without hammering the API.

**Revisit if:** the park ever moves to a faster/push feed, or we add enough trails that even
15-min polling bumps a rate limit — at which point batch the trails into one request rather than
shortening the interval.

Related: the feed-staleness gotcha (200-with-stale-body) handled via `published_at` — see the
[2026-03-14 log](../memory/2026-03-14.md).
