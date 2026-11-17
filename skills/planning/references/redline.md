# Redline mode: reviewing someone else's plan

Create mode writes a design. Redline mode takes a plan **someone else wrote** and marks it
up: what stands, what changes, what goes, and the revised version a builder can act on.
The output is a new document. The original is never edited.

Use it when a plan, spec, PRD, or design doc lands on you for review, or when the operator
asks you to "redline", "review", "mark up", "pressure-test", or "sanity-check" a plan.

## The procedure

1. **Read the plan for its goal, not just its text.** Write one sentence: what is this plan
   trying to achieve? Every finding is judged against that goal. A finding that doesn't
   change whether the goal is reached is a nit; leave it out or batch it at the end.
   If the goal isn't worth reaching, or the plan solves the wrong problem, say so first.
   TL;DR item 1 becomes that verdict (don't build, or build X instead, with the reason), and
   the line-item findings can be cut to the ones that support it.

2. **Verify the plan's load-bearing claims.** A plan is a stack of assumptions: "this API
   supports X", "the limit is N", "users will do Y". List the ones the plan depends on, then
   check each one against a source (docs, code, a quick test, a research sub-agent; see
   `research.md`). A claim you could not check is labelled *unverified*, not assumed true.
   Every *unverified* claim has to go somewhere: either it becomes an acceptance item that
   verifies it, or it becomes an Open question. Most of the value of a redline comes from
   this step.

3. **Sort findings by lens.** Pick the lenses the plan actually touches (for example
   security, correctness, cost/economics, operations, UX, legal/compliance, scope). One
   table per lens, numbered with a lens prefix (`S1`, `E2`, `U3`…) so findings can be cited.

4. **Give every finding exactly one verdict:**
   - **Accept**: the plan is right here; keep it. Use it for things a reader might doubt, so
     the doubt is closed. Variant **Accept + spec**: right, but underspecified; the
     resolution adds the missing spec.
   - **Change**: the next version does it differently. The resolution says *exactly* how
     (names, numbers, interfaces), not "consider improving". Variant **Change (scoped)**: the
     fix is to cut the risky part from this phase.
   - **Reject**: dropped from the plan, with the reason. Rejections also get a line in
     *Rejected from v0*.
   A finding with no verdict is not done. "Needs discussion" is not a verdict; if the call
   belongs to the plan's owner, write your recommendation as the resolution and flag it in
   *Open questions*.

5. **Red-team your own redline.** Your fixes are new design, and new design has holes. Spawn
   a fresh sub-agent with `red-team.md`'s prompt, and give it the original plan *and* your
   redline. In redline mode the target is your fixes, not v0, so put this framing in front
   of the verbatim prompt: *"Here's the original plan (v0) and a redline of it (v1). Attack
   v1's changes: where does a fix break, get bypassed, or introduce a new failure that v0
   didn't have? Don't re-review v0 except where a fix depends on it."* Without it the
   reviewer re-redlines v0 and repeats your findings. Record every attack in the *Red-team
   round* table with a severity and a resolution (Changed / Accepted risk because…). Fold
   changes back into the findings and the revised spec. Re-run after a major revision.

6. **Write the revised spec.** What the builder builds now: scope, components, concrete
   numbers, acceptance criteria. Acceptance criteria should be testable and should include
   at least one negative case: the check must **fail** on the broken version it exists to
   catch, or it proves nothing.

7. **Write the TL;DR last: the N changes that matter.** Only now, after the red-team round
   and the revised spec, because both change what the TL;DR has to say. Usually 3–5 items.
   Each one is a bold claim, the mechanism in a sentence or two, and the finding IDs it
   rolls up (RT IDs included). If step 1 found the plan shouldn't be built as conceived,
   lead with the whole-plan verdict. Then one line: **"Everything else in v0 stands: …"**
   listing what you checked and kept. A reader who stops after the TL;DR must know what
   changed and what didn't.

8. **Handle amendments in place.** When the plan's owner overrules a verdict after review,
   don't rewrite history: strike the old text and add **Amended (who, when): …** next to it,
   so the reasoning and the override both stay visible.

## Quality bar

- **Concrete or cut.** "Consider rate limiting" is not a finding. "The poller runs every 60s
  against an API that allows 100 calls/day, so it is blocked by 2am" is.
- **Numbers get named.** If the plan says "a cap" or "medium risk", the redline says what
  the number is, or makes picking it an acceptance item.
- **Sources for anything checkable.** A finding that rests on an external fact cites where
  the fact came from.
- **Keep what's right.** A redline that only lists problems leaves the reader unsure what
  survived. Say it explicitly.
- **Original stays unchanged.** Link it in `supersedes:` so anyone can diff v0 against v1.
