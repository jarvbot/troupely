# SHOWCASE

## What troupely is

A portable, Docker-substrate, **bring-your-own-model multi-persona Claude Code stack**. You
`docker run` it and have an orchestrator + specialist personas running a self-maintaining loop —
each on its own Telegram channel, coordinating through file inboxes, planning with rigor, and
remembering across sessions. MIT licensed. Telegram personas run on Claude Code channels, which
need a claude.ai or Anthropic Console login (a Claude subscription is the tested path; an API key
or OpenRouter may work). Bedrock, Vertex and OpenAI-compatible models via LiteLLM (see
`providers/`) run terminal sessions but can't drive the Telegram channel.

The point isn't "agents that chat." It's that the **discipline travels with the personas** — the
design-doc/research/red-team planning workflow, the file-convention memory system, the no-drift
canonical state, the three-state inbox drain. That discipline is what makes a stack you can
leave running and trust, rather than a demo that impresses once and rots.

## What makes it different

- **BYO-model, one-command switch.** `troupely-provider use openrouter` and restart. Not locked
  to one vendor.
- **Stripped personas aren't inert.** Each archetype is a thin CLAUDE.md, but it ships with the
  *capabilities* — the planning skill, the memory system, the heartbeat — so a fresh persona
  plans and remembers like a senior one from message one. (The hero-demo below proves this.)
- **Memory that survives.** Files + git + a heartbeat linter, not a black-box vector store. You
  can read it, grep it, and the linter catches drift.
- **Ships the architecture, never the instance.** Conventions, skeletons, templated configs, one
  sanitized example each — your keys and memories stay yours (gitignore + a pre-commit
  secret-scan hook enforce it).

## Hero demo — "stripped personas aren't inert"

The one flow that proves a freshly-stripped persona does real work on stock tooling (model +
Telegram + filesystem + sub-agents + memory — no external connectors needed):

**Seed (DM the planning persona):**
> "I keep missing when a hiking trail I like changes status. Worth building a notifier?"

**What should happen, end to end:**
1. **The planning agent pressure-tests** the idea (one trail? what's the data source? what's the failure
   mode?) instead of just agreeing — then invokes the **`planning` skill**.
2. It **fans out research sub-agents** (data source, polling vs webhook, prior art, failure
   modes) and aggregates the findings.
3. It writes a **design doc** with options, a defended recommendation, and an architecture —
   landing roughly the artifact in `examples/design-docs/trailpulse-notifier.md`.
4. It spawns a **red-team sub-agent** that attacks the design; the findings get folded back in
   (the backoff + timezone fixes in that example came from this step).
5. It **files** the locked design and **logs a memory pointer**.
6. On the **next heartbeat**, the persona **recalls** the decision from memory — the design isn't
   gone when the session moves on.

Every step runs on the base toolset. If a stripped persona can take a one-line idea to a
red-teamed, filed, recalled design with nothing but the model and the stack's own conventions,
the personas aren't inert markdown — which is the whole bet.

**Run it yourself:** boot per the [quickstart](QUICKSTART.md) with the `planning` archetype,
send the seed, and watch the trace in the session logs (`docker compose logs -f`) and the
resulting design doc in the persona's designs area. Layer connectors on afterward — they're not
needed to prove the core.
