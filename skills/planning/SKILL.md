---
name: planning
description: Turn a rough idea into a build-ready design through research, options analysis, and adversarial red-teaming. Use BEFORE building anything non-trivial — when a request is bigger than a single obvious edit, has alternatives worth comparing, spans multiple components, or will be handed to another agent/persona to build. Produces a tiered design doc (napkin / design-doc / architecture) plus a decision log. Also use when asked to "scope", "design", "spec", "pressure-test", or "plan" a feature or project. Redline mode: when someone else's plan, spec, or design doc needs reviewing, marked up, or "redlined", produce a v1 with Accept / Change / Reject verdicts per finding, a red-team round, and a revised spec.
---

# Planning

Take a scoped-but-rough idea and produce a design a builder can act on without re-inventing decisions mid-build. The craft is in three things smaller models skip: **researching before deciding**, **comparing real alternatives**, and **attacking your own design before someone else does**.

This skill is provider-agnostic. It works on any model the stack runs on — the rigor comes from the workflow, not the model.

## Two modes

| Mode | Use when | Output |
|---|---|---|
| **create** (default) | You're designing something new from a rough idea | A design doc at the right tier (the workflow below) |
| **redline** | Someone else's plan, spec, or design doc needs reviewing, marking up, or pressure-testing | A new v1 document: TL;DR of the changes that matter, findings with Accept / Change / Reject verdicts, a red-team round on your own fixes, and a revised spec. The original stays unchanged. Follow `references/redline.md` and fill `templates/redline.md`. |

If you're asked to review a plan, you're in redline mode even if nobody uses the word. Everything below describes create mode.

## When to use which tier

Pick the tier FIRST — it sets what's required.

| Tier | Use when | Required sections |
|---|---|---|
| **napkin** | < ~2h of work, or the answer is obviously correct | Problem · Approach · Risks (use `templates/napkin.md`) |
| **design-doc** | 2h+, alternatives worth comparing, or a cross-agent handoff. **The default.** | Full `templates/design-doc.md` |
| **architecture** | V1 meant to scale, or multiple subsystems interact | Full template + extra rigor on Data model, Adversarial review, Decision log |

If you're unsure, default to **design-doc**. Don't gold-plate a 50-line script with an architecture doc; don't napkin a system three agents will build against.

## The workflow

1. **Scope.** State the problem in one paragraph — concrete enough to later check whether the design solved it. Then name **Goals (V1)** and **Non-goals**. Naming what's NOT in V1 is half the work — it's how scope creep gets parked.

2. **Research (design-doc + architecture).** Don't decide from memory. Fan out: spawn parallel sub-agents, each investigating ONE angle — a candidate library's capabilities + cost, a competing approach, prior art (how others solved this), a specific failure mode. Aggregate findings into a table with sources. See `references/research.md` for the fan-out pattern and how to keep each agent's scope tight.

3. **Options considered (design-doc + architecture).** Table at least 3 options — one of which is always "do nothing / use what we already have." Pros/cons must cite the Research section, not vibes.

4. **Recommend.** Be opinionated. State the pick and defend it against the alternatives in two paragraphs. A design that won't commit is a design that didn't decide.

5. **Architecture.** Data model (what state, where it lives, what owns it), interface/contract (signatures, data shapes, error modes, config knobs), storage + recovery, auth/secrets if any. Specific enough that the builder doesn't invent these mid-build.

6. **Testing + observability.** Match rigor to scale — a smoke test for a small tool, integration tests where it spans systems, chaos cases for the failure modes that matter. What gets logged, what raises an alert, what counts as "broken."

7. **Adversarial review (THE step that separates good from plausible).** Spawn a red-team sub-agent and have it attack the design. Fold every finding back in — either revise the design or record an accepted risk in the decision log. Never silently drop a finding. The exact prompt and procedure are in `references/red-team.md` — use it verbatim; harsher prompts produce harsher (more useful) findings.

8. **Decision log.** Every load-bearing decision + why, every red-team finding + how it was resolved. This is what lets a future reader (or your future self) understand the design without re-deriving it.

## Output

Write the design doc to the persona's notes/designs area (e.g. `personas/<name>/designs/<project>/<date>-<topic>.md` or wherever the stack keeps design artifacts) with frontmatter: `project`, `tier`, `status` (draft → locked → superseded), `builder`, `date`. Log the decision + a one-line pointer to your memory so the next session/heartbeat can recall it.

A design isn't done when it's written — it's done when it's been **attacked and survived** (or been revised until it does).

## Files

- `templates/design-doc.md` — the full tiered template (copy, fill, delete the guide notes)
- `templates/napkin.md` — the 3-section lightweight version
- `references/research.md` — the parallel research fan-out pattern
- `references/red-team.md` — the verbatim adversarial-review prompt + how to fold findings
- `references/redline.md` — redline mode: reviewing someone else's plan, verdict rules, quality bar
- `templates/redline.md` — the redline document shape (TL;DR → findings → red-team round → revised spec)
