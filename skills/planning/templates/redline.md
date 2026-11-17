---
project: <slug>
topic: <plan-name>-redline
mode: redline
tier: design-doc            # same tier ladder as create mode
author: <you>
date: YYYY-MM-DD
status: draft               # draft | ready for <builder> | superseded
builder: <who builds the revised plan>
supersedes: <path or link to the original plan, v0>   # the original is kept unchanged for diff
source: <who asked for the review, and where>
---

# <Plan name>: v1 (redline of v0)

## TL;DR: the <N> changes that matter

<!-- Write this LAST, after the red-team round and the revised spec. 3-5 items. Bold claim,
     then the mechanism, then the finding IDs. The verdict line below is optional: use it
     when the plan as a whole shouldn't be built as conceived (step 1), and make it item 1. -->

**Verdict on the plan as a whole:** build as revised / build something else / don't build

1. **<The change, stated as a claim.>** <Why v0 doesn't work as written, in one or two
   sentences, and what v1 does instead.> (<IDs, e.g. S1, RT2>)
2. **<...>** <...> (<IDs>)
3. **<...>** <...> (<IDs>)

**Everything else in v0 stands:** <the parts you checked and kept, in one line>.

---

## Goal and load-bearing claims

**What v0 is trying to achieve:** <one sentence. Every finding below is judged against it.>

| Claim v0 depends on | Checked against | Holds? |
|---|---|---|
| <"service X allows N requests/min"> | <docs link, test, research agent> | Yes / **No: <actual>** / Unverified |

Every **Unverified** claim goes somewhere: an acceptance item that verifies it, or an Open
question. None is left only in this table.

---

## Red-line findings

Verdicts: **Accept** (v0 is right, keep it) · **Change** (v1 does it differently) ·
**Reject** (dropped, with a reason). Variants: *Accept + spec*, *Change (scoped)*.

### <Lens 1, e.g. Security>

| # | Finding | Verdict | v1 resolution |
|---|---|---|---|
| S1 | <What's wrong or at risk, concretely: inputs, numbers, the failure.> | **Change** | <Exactly what v1 does: names, numbers, interfaces.> |
| S2 | <...> | **Accept** | <Why it stands; what doubt this closes.> |

### <Lens 2, e.g. Operations / Cost / UX>

| # | Finding | Verdict | v1 resolution |
|---|---|---|---|
| O1 | <...> | **Reject** | <Why it's dropped.> |

<!-- When the plan's owner overrules a verdict after review, keep the old text struck through
     and add the amendment next to it:
     ~~old resolution~~ **Amended (<who>, <date>): <new resolution>.** -->

### Red-team round (reviewer sub-agent, <date>)

The redline's own fixes, attacked by a fresh reviewer given v0 and this document.

| # | Sev | Attack | Resolution |
|---|---|---|---|
| RT1 | High | <How a v1 fix breaks or can be bypassed.> | **Changed.** <What moved in the findings / spec.> |
| RT2 | Low | <...> | **Accepted risk** because <reason>. |

### Rejected from v0

- **<Part of v0>. Rejected.** <Reason, and what replaces it if anything.>

---

## Revised spec (what <builder> builds)

**Scope:** <one paragraph: what is in this phase, and what is explicitly not.>

### Components

| # | Component | What it is | Notes |
|---|---|---|---|
| C1 | <name> | <responsibility, interface> | <constraints from the findings> |

### Numbers

<!-- Every limit, threshold, or cap the findings named, as a concrete value. -->

| Setting | Value | Why |
|---|---|---|
| <...> | <...> | <finding ID> |

### Acceptance (all must pass)

1. <Testable statement of the golden path.>
2. <Each guard from the findings rejects its bad input: list them.>
3. <At least one check that must FAIL on the v0 behaviour it was written to catch.>

## Open questions for <plan owner>

- <A call that's theirs to make, with your recommendation.>

## Decision log

| Decision | Why | Finding |
|---|---|---|
| <...> | <...> | <ID> |
