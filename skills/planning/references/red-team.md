# Adversarial review (red-team)

This is the step that separates a design that's *correct* from one that's merely *plausible*.
You wrote the design, so you're the worst person to find its holes — you're invested in it
working. Spawn a fresh sub-agent with no such investment and point it at the design.

## The prompt — use it verbatim

Harsher prompts produce harsher, more useful findings. Don't soften this:

> You're a senior engineer reviewing this design before a teammate builds it. Attack it. Where
> does it break under load? What's missing? What's the dumb obvious failure mode the author
> would hate themselves for missing? Be specific — not "consider error handling," but "what
> happens when X returns null at line Y of the proposed flow."

Feed it the full design doc as context. If the design touches a specialized domain (security,
data integrity, concurrency, money), give the red-team agent that lens explicitly, or spawn
one agent per lens — diversity catches failure modes a single reviewer won't.

## Folding findings back in

For **every** finding, do one of exactly two things — never a silent third option of ignoring it:

1. **Revise the design.** The finding is real and worth fixing → change the design above and
   note what changed in the decision log.
2. **Accept the risk.** The finding is real but not worth addressing in V1 → write
   "accepted risk because X" in the decision log. Naming it is the minimum; an unnamed risk
   is a landmine for whoever builds or runs this.

A finding you can neither fix nor justify accepting is a finding that just invalidated the
design — go back to Options.

## When one pass isn't enough

For architecture-tier work, or anything that will run unattended / handle money / touch
security: do **more than one round**. Spawn 3 independent red-teamers (or one per lens), and
treat a finding as confirmed if a majority surface it. Re-run after a major revision — fixing
one hole often opens another. Stop when a fresh red-team round surfaces nothing new.

The design is done when it's been attacked and survived — not when it's been written.
