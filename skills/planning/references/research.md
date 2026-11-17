# Research fan-out pattern

Don't research serially in your own context — it's slow and you lose objectivity (you start
rationalizing the first option you read about). Fan out instead.

## The pattern

1. **Decompose into angles.** Before spawning anything, list the distinct questions that would
   change your recommendation. Good angles are independent and concrete:
   - "What does candidate library/tool A actually do, and what does it cost?"
   - "How does competing approach B compare on the dimensions that matter here?"
   - "How have others solved this problem — prior art, license, what to borrow vs avoid?"
   - "What's the dominant failure mode of approach X under real load / bad input?"

2. **Spawn one sub-agent per angle, in parallel.** Each agent gets ONE tightly-scoped question
   and returns a short structured finding (claim + evidence + source), not an essay. Tight
   scope is what keeps the findings comparable and the cost bounded. Launch them in a single
   batch so they run concurrently.

3. **Aggregate, then judge.** Collect the findings into the Research table. Only after they're
   all in do you move to Options — so the comparison is grounded in evidence from every angle,
   not just the one you happened to read first.

## Rules that keep it honest

- **Cite or cut.** A finding without a source (doc URL, repo, benchmark) is a guess — mark it
  as one or drop it. Pros/cons in the Options table must trace back to a cited finding.
- **Prior art is mandatory for anything non-trivial.** Someone has probably built a version of
  this. Find it: what's the license, when was it last touched, what did they get right, where
  did they fail. Borrowing a proven approach beats inventing a fragile one.
- **One angle the others are blind to: failure modes.** At least one agent should be tasked
  purely with "how does this break" — the happy-path agents won't surface it.

## Scale to the task

A small design-doc might need 2–3 angles; an architecture-tier decision might need 5–6. Don't
fan out 6 agents for a weekend tool, and don't single-thread research for a system three agents
will build against. Match the breadth to what's actually at stake.
