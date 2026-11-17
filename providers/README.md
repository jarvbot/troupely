# troupely — model / provider config (pillar C7)

Bring your own model. troupely runs on whatever LLM backend you point it at — switch with
one command, no code changes.

> **Telegram personas need a claude.ai subscription or Anthropic Console login.** They run on
> Claude Code channels, which Bedrock, Vertex and the OpenAI-proxy tier can't use. Those
> backends are for personas you drive from the terminal. `./setup.sh` only offers the paths
> that can run a Telegram persona.

Two tiers:

| Tier | Profiles | How it works |
|---|---|---|
| **Native-Anthropic** | `anthropic-api`, `openrouter`, `bedrock`, `vertex` | Claude Code speaks the Anthropic API directly to the backend. Best fidelity — every Claude feature works. |
| **OpenAI-proxy** | `litellm-openai` | A [LiteLLM](https://docs.litellm.ai) proxy translates the Anthropic API ↔ OpenAI/Gemini/local models. The "run troupely on GPT / Gemini / Ollama" path. |

## Quick switch

```bash
./providers/troupely-provider list            # what's available + what's active
./providers/troupely-provider use openrouter  # rewrite the provider block in .env
./providers/troupely-provider current         # which profile is active
./providers/troupely-provider show bedrock    # preview a profile (secrets masked)
docker compose up -d                          # restart so the container picks up .env
```

`use` rewrites **only** the provider block in your active `.env` — bot tokens
(`TROUPELY_TG_TOKEN_*`) and everything else are preserved. Fill in the real creds in the
chosen `providers/profiles/<name>.env` (or directly in the `.env` block) — profiles ship
with `REPLACE_ME` placeholders and the switcher warns when any remain.

## How auth + model selection work (the load-bearing details)

These are pinned against current Claude Code docs ([llm-gateway](https://code.claude.com/docs/en/llm-gateway),
[model-config](https://code.claude.com/docs/en/model-config)) — re-verify at major version bumps.

- **`ANTHROPIC_BASE_URL`** points Claude Code at a gateway endpoint. Unset / `api.anthropic.com`
  = first-party.
- **`ANTHROPIC_AUTH_TOKEN`** is the gateway credential — sent as `Authorization: Bearer`.
  Use this for OpenRouter, LiteLLM, any proxy.
- **`ANTHROPIC_API_KEY`** is sent as `x-api-key` and is for the **first-party API only**.
- **⚠️ The empty-string gotcha:** behind a gateway, set `ANTHROPIC_API_KEY=""` — **empty, not
  unset.** If a real key sits alongside `ANTHROPIC_AUTH_TOKEN`, both headers go out and the
  gateway rejects the request. Empty-string holds the slot so nothing else fills it. Every
  gateway profile here already does this.
- **Model aliases** (`opus`/`sonnet`/`haiku`/`fable`) auto-resolve to current versions on the
  first-party API — leave model vars unset there. On **gateways and Bedrock/Vertex the aliases
  lag or are namespaced**, so those profiles pin explicit IDs via:
  - `ANTHROPIC_MODEL` — the main model
  - `ANTHROPIC_DEFAULT_HAIKU_MODEL` — the haiku alias **and** the background/small-task model
  - `ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_SONNET_MODEL` / `ANTHROPIC_DEFAULT_FABLE_MODEL`
- **Deprecation:** `ANTHROPIC_SMALL_FAST_MODEL` is **deprecated** → use
  `ANTHROPIC_DEFAULT_HAIKU_MODEL` (what all profiles here use).

## OpenAI-proxy tier (LiteLLM)

Run any non-Claude model through LiteLLM's **unified endpoint** (its native Anthropic-format
route — preferred over the `/anthropic` pass-through for load-balancing + fallbacks + cost
tracking). See [`litellm/`](./litellm/): `config.example.yaml` (map your backends to the
`gpt-main` / `gpt-small` aliases the profile references) + `compose.yaml` (run the proxy).
`ANTHROPIC_MODEL` then references the LiteLLM `model_name` alias, not a Claude name.

Caveat: behind a non-Claude model, Claude-specific features (adaptive thinking, effort,
prompt caching) degrade to whatever the backend supports. Functionality over fidelity.

> Security note (LiteLLM): PyPI `1.82.7`/`1.82.8` were compromised — do not install those.
> Pin a known-good image digest in production.

## Auto-failover (reserved — pillar C10, deliberately minimal)

Claude Code has a **built-in** fallback-chain — no extra component needed in V1. Set it in
the container's Claude Code settings (`/vault/.claude/settings.json`) or via `--fallback-model`:

```json
{ "fallbackModel": ["claude-sonnet-4-6", "claude-haiku-4-5"] }
```

It switches models for the current turn on overload / non-retryable server errors. That's the
whole V1 failover story — a learned per-request router is a fast-follow (C10), not V1. Don't
gold-plate. (LiteLLM also offers proxy-layer `fallbacks` for the OpenAI-proxy tier — see its
config; that's independent of Claude Code's chain.)

## Files

```
providers/
  troupely-provider          # the quick-switch CLI (stdlib bash, zero deps)
  profiles/
    anthropic-api.env        # first-party Anthropic API (default)
    openrouter.env           # OpenRouter Anthropic-skin gateway
    bedrock.env              # Amazon Bedrock (direct)
    vertex.env               # Google Vertex AI (direct)
    litellm-openai.env       # OpenAI-compatible models via LiteLLM proxy
  litellm/
    config.example.yaml      # LiteLLM backend mapping
    compose.yaml             # run the proxy alongside troupely
    README.md
```
