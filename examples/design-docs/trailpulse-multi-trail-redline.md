---
project: trailpulse
topic: multi-trail-redline
mode: redline
tier: design-doc
author: planning-persona
date: 2026-04-03
status: ready for builder-persona (red-team round applied)
builder: builder-persona
supersedes: trailpulse-multi-trail-plan-v0.md (kept unchanged for diff)
source: operator, "can you review my multi-trail plan before the builder starts?"
---

# TrailPulse multi-trail: v1 (redline of v0)

> Example artifact (invented subject, nothing real). A redline produced with the `planning`
> skill's redline mode (`references/redline.md`, `templates/redline.md`) from the sample plan
> `trailpulse-multi-trail-plan-v0.md`. The red-team round is a real reviewer pass on the
> first draft of this document; its findings changed the spec below.

## TL;DR: the five changes that matter

1. **One park-wide request every 15 minutes, not 140 requests every 5.** The status endpoint
   already returns every trail in one response, and it only republishes every ~20 minutes. v0
   plans 40,320 requests a day to learn what 96 requests tell us. (O1)
2. **A shared `state.json` written by two processes loses subscriptions.** If a friend's
   `/watch` lands between the poller's read and its write, the poller writes back the old file
   and the subscription is gone with no error. v1 uses SQLite (stdlib), and every table has
   exactly one writer. (D1, RT2)
3. **Every alert goes through an outbox, and a poll only counts if the feed moved forward.**
   v0 sends inline: one blocked chat aborts the loop and the rest never hear, and a cached
   older body replays a change that never happened. v1 writes alerts in the same transaction
   as the new state, sends them per chat, and skips any poll whose `published_at` isn't newer
   than the last one. (RT3, RT4)
4. **The first run, or any long gap, must not page everyone.** 139 trails have no last-seen
   status, so v0 reports all of them as changed. v1 baselines silently and tells the operator
   when it did, including after a restore or outage. (D3, D6, RT5)
5. **`/watch` confirms a trail instead of guessing, and the bot is invite-only and private.**
   Fuzzy matching silently subscribes "bear lake" to Bear Creek. An open bot collects
   strangers' chat ids, and a group chat would bypass any invite. (D2, P1, RT8)

**Everything else in v0 stands:** reusing the single-trail change detection (diff `status`,
`published_at` freshness guard, UTC parsing), Telegram as the channel, and the existing VPS.

---

## Goal and load-bearing claims

**What v0 is trying to achieve:** friends get one timely, correct message when a trail they
care about changes status, without the operator babysitting it.

| Claim v0 depends on | Checked against | Holds? |
|---|---|---|
| Polling each trail separately is needed | One call to the park status endpoint | **No:** a single response carries all ~140 trails, each with `status`; one `published_at` for the whole feed |
| 5-minute polling catches changes faster | `trailpulse-notifier.md` research + decision log | **No:** the feed republishes every ~20 min; polling faster than ~15 min only repeats the same body |
| "It's a public endpoint, the volume is fine" | Park site terms page | **Unverified:** no published rate limit. Treated as a reason to stay low, not a licence to go high. Our side is capped by acceptance 10; whether the park minds is an Open question |
| The single-trail change logic carries over | `trailpulse-notifier.md` architecture | Yes, per trail, once there is a baseline (D3) and the body is newer than the last (RT4) |
| Telegram can broadcast to subscribers | Telegram Bot API limits | Yes at this scale: ~30 messages/second overall, ~1/second per chat |

---

## Red-line findings

Verdicts: **Accept** (v0 is right, keep it) · **Change** (v1 does it differently) ·
**Reject** (dropped, with a reason). Variants: *Accept + spec*, *Change (scoped)*.

### Operations and cost

| # | Finding | Verdict | v1 resolution |
|---|---|---|---|
| O1 | 140 trails × 12 polls/hour = 1,680 requests/hour, 40,320/day, against a feed that changes every ~20 min and returns all trails per call. Most likely outcome: the park blocks the VPS IP and every trail goes dark at once. | **Change** | One `GET /status` every 15 min. Parse all trails from that response. |
| O2 | The feed has one `published_at`. When it goes stale, v0 would treat 140 trails as stale and alert every subscriber of every trail. | **Change** | A stale feed produces one alert to the **operator only**, with the existing hourly backoff. Subscribers are not told about feed health. |
| O3 | Same VPS as the single-trail notifier. | **Accept** | 96 requests/day and a few hundred messages is nothing for it. The single-trail notifier is retired once v1 runs, so there is one poller, not two. |
| O4 | A partial feed (an outage that returns 20 of 140 trails with a fresh `published_at`) looks like 120 trails disappearing. | **Change** | A poll listing fewer than 80% of the trails in the **last healthy poll** is a broken feed: operator alert, no diffs, no unlisting. (Baseline per RT1.) |

### Data and correctness

| # | Finding | Verdict | v1 resolution |
|---|---|---|---|
| D1 | `state.json` is read and written by the poller and the signup bot. Read-modify-write from two processes loses whichever write lands first. A subscription can vanish silently. | **Change** | SQLite, WAL mode, stdlib only. One writer per table: `trail_state`, `feed_state` and `outbox` belong to the poller; `subscription` and `chat` belong to the bot. Each write is one transaction. |
| D2 | Fuzzy name matching picks a trail without telling the user. "bear lake" → Bear Creek is a silent wrong subscription. | **Change** | `/watch <text>` replies with up to 3 matches as buttons; the subscription stores the chosen `trail_id`. No match → "no trail found" and nothing stored. |
| D3 | 139 trails have no last-seen status. The first poll reads every one of them as a change. | **Change** | A trail seen for the first time is written as baseline with no alert. |
| D4 | A trail renamed or removed from the feed leaves subscriptions pointing at nothing. | **Accept + spec** | Subscriptions key on `trail_id`, so renames are free. A trail missing from 3 polls with **distinct** `published_at` values is marked `unlisted_at` by the poller; its subscribers get one "no longer listed" message via the outbox. **Subscriptions are kept**; if the trail returns, alerts resume. (Changed by RT1, RT2.) |
| D5 | Reuse the single-trail diff and freshness logic. | **Accept** | Diff `status` per trail, `published_at` > 40 min = stale, parse as UTC. The logic stands; only its scope changes. |
| D6 | D3's silent baseline also fires after the database is lost: real changes during the gap are swallowed with no trace. | **Change** | Any poll that baselines a gap (see RT5) sends the operator one message saying how many trails were baselined and how many subscriptions exist. Subscribers get nothing. |

### Privacy and abuse

| # | Finding | Verdict | v1 resolution |
|---|---|---|---|
| P1 | Anyone who finds the bot can subscribe, and the bot stores their chat id. "Friends" isn't enforced anywhere. | **Change** | `/start <invite-code>` required before `/watch`, private chats only (RT8). One code, rotatable by the operator. Unknown chats get a one-line refusal and nothing is stored. |
| P2 | No way to stop. A friend who wants out has to block the bot. | **Change** | `/list` and `/stop [trail]`. `/stop` with no argument deletes every row for that chat id. |
| P3 | Broadcast volume against Telegram's limits. | **Accept** | At this scale a change reaches at most a few dozen chats. The outbox sends sequentially with a short gap; no queue service needed. |

### Scope

| # | Finding | Verdict | v1 resolution |
|---|---|---|---|
| X1 | "All trails are watched. Friends can subscribe" can't fail, so it can't be checked. | **Change** | Replaced by the acceptance list below. |

### Red-team round (reviewer sub-agent, 2026-04-03)

A fresh reviewer was given v0, the single-trail design and the first draft of this redline,
and told to attack the fixes. Every finding changed the spec.

| # | Sev | Attack | Resolution |
|---|---|---|---|
| RT1 | High | The 80% gate compared against "known trails", which only shrinks when D4 removes a trail, and D4 only ran on healthy polls. If the park drops 30 winter-closed trails, every poll after that reads as broken: diffs stop for the other 110 and the gate never recovers. In the other direction, an outage returning 120 of 140 (86%) passes the gate, and 45 minutes of it would unsubscribe everyone on the missing 20. | **Changed.** The gate compares against the **last healthy poll's** count (O4). D4 no longer deletes subscriptions: a missing trail is marked `unlisted_at`, its subscribers are told once, and the subscriptions stay. |
| RT2 | High | D4's "subscription is dropped" could only be done by the poller, a second writer on `subscription`. That brings back D1's race: a `/watch` committing during a removal could vanish. And nobody owned cleaning up a chat that blocked the bot. | **Changed.** The poller writes only `trail_state.unlisted_at`. The bot owns every `subscription` delete, including cleanup of chats the outbox marks `blocked` after a Telegram 403. |
| RT3 | High | Sends happened inline after the state write. One 403 or 429 on subscriber 4 of 30 aborted the loop: 26 people never heard, and the next poll saw no change to resend. Crashing before the write instead would resend to everyone. | **Changed.** The poller writes one `outbox` row per (chat, trail, new status) in the **same transaction** as the `trail_state` update. The sender works through unsent rows, marks each one sent, handles errors per chat (403 → `blocked`, 429 → retry after the given delay), and never aborts the loop. |
| RT4 | High | The endpoint can serve a stale cached body. A 10:30 poll that hits a cache holding the 09:40 body is still under 40 min old, so it reads as "fresh": subscribers get "open", then "closed" on the next poll, for a flap that never happened. The same body could also count twice toward D4's three misses. | **Changed.** `feed_state` stores the last accepted `published_at`. A poll whose `published_at` is not strictly newer is skipped: no diffs, no misses counted. |
| RT5 | Med | Losing the DB also loses every subscription, which the first-draft operator message didn't mention. A restore from last night's backup diffs against day-old statuses and sends a burst of stale "changes". A plain file copy of a WAL database can miss the `-wal` contents. And a ">10 trails first seen" rule would fire falsely the day the park adds 11 new trails. | **Changed.** Backups use SQLite's `.backup`. If the stored `published_at` is more than 6 hours old, or `trail_state` is empty, the poll **re-baselines** instead of diffing, and the operator message reports the trail and subscription counts (D6). New trails appearing in a normal poll are baselined quietly, with no gap alert. |
| RT6 | Med | Acceptance items 1, 3 and 5 could pass without testing anything. A fresh DB has no subscribers, so "no messages on first poll" is trivially true. The concurrency test never triggered the only real cross-writer case. And `/stop` "leaves no rows" even if `/watch` never stored one. | **Changed.** Item 1 seeds subscriptions by `trail_id` before the first poll. Item 3 includes unlisting during the run. Item 5 asserts rows exist before `/stop`. |
| RT7 | Med | Five fixes (O2, D6, D4, D2, and "the same body twice sends nothing") had no acceptance item. Item 6's "96 ±1 requests" would fail on any retry while proving nothing about outcomes. | **Changed.** An acceptance item was added for each, and item 6 is now "at most one request per 15-minute window, plus retries of a failed request". |
| RT8 | Low | Rotating the invite code doesn't remove anyone who joined with a leaked one, and the operator has no way to list or remove a chat. `/start <code>` in a group stores the group's chat id, handing alerts to everyone in it. | **Changed.** Operator-only `/subs` and `/revoke <chat_id>`. `/start` and `/watch` are refused outside private chats. |

### Rejected from v0

- **Per-trail polling every 5 minutes. Rejected.** One park-wide call carries the same
  information, and 5 minutes is faster than the feed changes (O1).
- **A shared JSON file as the store. Rejected.** Two writers, no locking (D1).
- **Sending alerts inline from the poll loop. Rejected.** One failed send loses the rest (RT3).

---

## Revised spec (what builder-persona builds)

**Scope:** every trail in the park's status feed, invite-only Telegram subscriptions in private
chats, alerts on status change. Not in this phase: per-friend alert hours, a web UI, other parks.

### Components

| # | Component | What it is | Notes |
|---|---|---|---|
| C1 | Poller | Every 15 min: one `GET /status`. In order: skip if `published_at` isn't newer (RT4) → stale check (O2) → broken-feed check (O4) → re-baseline if the gap is over 6h or state is empty (RT5) → per-trail diff. | Only writer of `trail_state`, `feed_state`, `outbox` inserts. State update and outbox rows in one transaction (RT3). |
| C2 | Sender | Works through unsent `outbox` rows, one chat at a time. | Marks rows sent; 403 → `blocked`; 429 → waits the given delay. Never aborts the loop (RT3). |
| C3 | Bot | `/start <code>`, `/watch <text>` with match buttons, `/list`, `/stop [trail]`; operator-only `/subs`, `/revoke <chat_id>`. Private chats only. | Only writer of `subscription` and `chat`, including deletes for `blocked` chats (RT2, RT8). |
| C4 | Store | SQLite file, WAL mode. | Nightly backup with SQLite `.backup`, not a file copy (RT5). |

### Numbers

| Setting | Value | Why |
|---|---|---|
| Poll interval | 15 min | O1, feed republishes ~20 min |
| Stale feed | `published_at` older than 40 min | D5, unchanged from the single-trail design |
| Repeated or older body | `published_at` not strictly newer than the last accepted one → skip | RT4 |
| Broken feed | fewer than 80% of the last healthy poll's trails | O4, RT1 |
| Unlisting | missing from 3 polls with distinct `published_at` | D4, RT4 |
| Re-baseline instead of diff | stored `published_at` older than 6 h, or `trail_state` empty | RT5 |
| `/watch` matches shown | up to 3 | D2 |

### Acceptance (all must pass, fixture-driven)

1. Seed two subscriptions by `trail_id`, then run the first poll on a recorded feed: every trail
   is baselined, **no** subscriber messages, one operator message with the trail and
   subscription counts (D3, D6, RT6).
2. Change one trail's status in the fixture: exactly its subscribers get exactly one message.
   Poll the **same** fixture again: zero messages (RT7).
3. Serve an older `published_at` body after a newer one: poll skipped, no messages, no miss
   counted (RT4).
4. Run the bot and the poller concurrently (500 `/watch` calls during 50 polls, with one trail
   going unlisted mid-run): every subscription is still present afterwards (D1, RT2, RT6).
   **Run the same test against the v0 shared-JSON store and confirm it loses subscriptions**;
   if it doesn't, the test isn't exercising the race.
5. A fixture with 20 of 140 trails and a fresh `published_at`: operator alert, no diffs, nothing
   unlisted (O4). A stale fixture: one operator alert, nothing to subscribers (O2).
6. A trail missing from 3 distinct fresh polls: marked unlisted, subscribers told once,
   subscriptions still present; when it reappears, alerts resume (D4, RT1).
7. The sender hits a 403 on the 4th of 30 chats: the other 29 are still sent, the 403 chat is
   marked `blocked`, and the bot later removes its subscriptions (RT2, RT3).
8. Restore the store from a day-old `.backup`: the next poll re-baselines and messages the
   operator, with no stale "changed" alerts to subscribers (RT5).
9. Bot: `/watch` from a chat without the invite code is refused and stores nothing (P1);
   `/start` in a group is refused (RT8); `/watch` with no match stores nothing (D2); after a
   successful `/watch` the row exists, and `/stop` with no argument removes it (P2, RT6).
10. Request log over 24 hours: at most one request per 15-minute window, plus retries of a
    failed request (O1, RT7).

## Open questions for the operator

- Should friends see feed outages? v1 says no (O2): they can't act on them, and an outage
  message to everyone is noise. Recommendation: keep it operator-only.
- The park publishes no rate limit (load-bearing claims table). v1 polls once per 15 minutes,
  about 96 requests a day. Recommendation: email the park's web team once to confirm that's
  fine, and set a descriptive User-Agent with a contact address either way.

## Decision log

| Decision | Why | Finding |
|---|---|---|
| Single bulk poll at 15 min | Same information, 0.24% of the requests | O1 |
| SQLite, one writer per table | Removes the lost-update race without a server | D1, RT2 |
| Outbox in the state transaction | No lost or duplicated alerts when a send fails or the process dies | RT3 |
| Only accept a strictly newer `published_at` | Cached older bodies can't fake a change | RT4 |
| Unlist trails, keep subscriptions | A partial outage can't silently unsubscribe people | D4, RT1 |
| Silent baseline, operator told on a gap | No alert storm, but a gap is never hidden | D3, D6, RT5 |
| Confirm trail by button, store id | No silent wrong subscriptions; renames survive | D2 |
| Invite code, private chats, operator revoke | "Friends" becomes enforceable and reversible | P1, RT8 |
| Accepted risk: a real status flap (open → closed → open within an hour) sends three messages | The feed republishes every ~20 min, so a flap means the park changed it twice. Revisit if a friend complains | (author's pass) |
