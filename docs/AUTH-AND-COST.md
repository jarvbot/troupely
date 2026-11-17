# Auth & cost

## Auth — pick one branch

troupely runs Claude Code in a container; the entrypoint guards on auth at boot and waits
(instead of crash-looping) until one of these is satisfied:

- **Subscription, Docker or Linux (recommended): a long-lived token.** Run `claude setup-token`
  on any computer with Claude Code, approve in the browser, and paste the `sk-ant-oat01-…` token
  when `./setup.sh` asks. It goes in `.env` as `CLAUDE_CODE_OAUTH_TOKEN`, every persona reads it
  from the environment, and it doesn't rotate, so personas can't log each other out.
- **Subscription, interactive login (one persona only).** `./troupely.sh login` runs
  `claude auth login --claudeai` in the container and saves one shared `.credentials.json` on
  the vault. With two or more personas this breaks: the first token refresh rotates the
  refresh token and the other personas lose auth hours later. Use the token above instead.
- **Subscription, Mac native.** Personas share the Mac's own Claude login through the login
  Keychain (`./troupely.sh login` checks it). Nothing to paste.
- **Provider key (headless — no display needed).** Set a provider credential in the container
  env and you're done, no interactive step: `ANTHROPIC_API_KEY` for the first-party API, or a
  gateway profile (`ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL`) for OpenRouter / Bedrock /
  Vertex / a LiteLLM proxy. Pick + switch profiles with `providers/troupely-provider` (see
  `providers/README.md`).

That's the whole decision: **subscription → setup-token token (or the Mac's own login when
native); metered → provider key.** Both live in `.env` and survive restarts and rebuilds.

## Cost — keep the cadence cheap

Per-token pricing (first-party API; cached 2026-05, re-check the
[pricing page](https://platform.claude.com/docs/en/pricing) for current numbers):

| Model | Input $/1M | Output $/1M | Use for |
|---|---|---|---|
| Fable 5 | $10 | $50 | hardest, longest-horizon work only |
| Opus 4.8 | $5 | $25 | complex reasoning, the orchestrator/builder default |
| Sonnet 4.6 | $3 | $15 | daily work, high-volume lanes |
| Haiku 4.5 | $1 | $5 | simple/fast tasks + **all background token usage** |

What actually moves the bill in an always-on stack:

- **Heartbeat cadence.** Every tick is tokens. Match the interval to how fast the stack moves —
  hourly for quiet personas, 15–30 min only for busy ones. A heartbeat that finds nothing should
  reply `HEARTBEAT_OK` and stop, not re-read everything.
- **Model per lane.** Don't run Opus where Sonnet or Haiku suffices. The background/small-task
  model is `ANTHROPIC_DEFAULT_HAIKU_MODEL` — keep it on Haiku. Set the main model per persona to
  the cheapest tier that does the job.
- **Effort.** Lower effort = fewer tokens. Reserve `high`/`xhigh` for the personas that need
  deep reasoning; let routine lanes run lower.
- **Prompt caching is automatic** and large — keep each persona's context (its CLAUDE.md +
  imports) stable so the cached prefix keeps hitting. Churning the system prompt every session
  throws the cache away. (Disable per-tier with `DISABLE_PROMPT_CACHING_*` only if you must.)
- **Subscription vs API.** On a subscription, in-container login means a persona's usage draws
  from your plan rather than per-token billing — often the cheapest path for steady personal use.
  Metered API billing is what the per-token table above costs.

Rule of thumb: **a heartbeat interval and a per-lane model choice set 90% of an idle stack's
cost.** Tune those two first.
