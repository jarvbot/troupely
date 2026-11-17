---
project: <slug>
topic: <slug>
tier: design-doc        # napkin | design-doc | architecture
status: draft           # draft | locked | superseded
builder: <who builds it>
date: YYYY-MM-DD
estimate: weekend       # 2h | weekend | week | multi-week
---

# Design Doc — <project> · <topic>

## Problem

One paragraph. What's broken, what's missing, what friction is actually felt. Concrete enough that you can later check whether the design solved it.

## Goals / Non-goals

**Goals (V1):**
- ...

**Non-goals (deferred / out of scope):**
- ...

Naming what's NOT in V1 is half the work — it's how scope creep gets parked.

## Research

Required for design-doc + architecture. Fan out parallel sub-agents, one angle each, then aggregate. (See `references/research.md`.)

| Agent | Angle | Key finding (1 line) |
|---|---|---|
| 1 | Library/tool A — capabilities + cost | ... |
| 2 | Library/tool B — comparison | ... |
| 3 | Prior art — how others solve this | ... |
| 4 | Failure mode under load | ... |

### Aggregated findings
- **A** ([docs](url)) — what it does · pros · cons · fit
- **Prior art** — link, license, last commit, what to borrow / avoid

## Options considered

At least 3, one being "do nothing / use what we have." Pros/cons cite Research — don't invent them.

| Option | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| A | ... | ... | ... | ... |
| B | ... | ... | ... | ... |
| C (do nothing) | ... | ... | ... | ... |

## Recommended approach

Be opinionated. State the pick, defend it against the alternatives. Two paragraphs max.

## Architecture

### Data model
What state exists, where it lives, what owns it. Prose is usually enough; reach for a diagram only when relationships are non-obvious.

### Interface / contract
For anything that gets built: function signatures, data shapes, error modes (what raises what, what's recoverable), config knobs (env vars, settings, flags). Specific enough that the builder doesn't invent these mid-build.

### Storage / state
Where persistent state lives. Recovery story if it goes bad.

### Auth + secrets (if applicable)
How auth flows; which secret-store entries (by name), which API tier/key/header.

## Testing strategy

Match rigor to scale — not enterprise bureaucracy.
- **Smoke test** — does the happy path work end-to-end against real(istic) input?
- **Integration** (if it spans systems) — exercise the real seams; mocks hide the bugs that matter.
- **Chaos cases** — API down / wrong key / slow network / bad input.

## Observability

What gets logged, what alerts, what counts as broken. Errors → stderr + optional notification; optional heartbeat for long-running pieces.

## Adversarial review

Run the red-team sub-agent (`references/red-team.md`, prompt verbatim). For each finding: revise the design above, OR record an accepted risk in the Decision log. Never ignore a finding.

## Decision log

| Decision / finding | Resolution + why |
|---|---|
| ... | ... |
