# LiteLLM proxy — troupely OpenAI-proxy tier

Run troupely on OpenAI / Gemini / a local model. Claude Code only speaks the Anthropic
Messages API; LiteLLM's unified endpoint accepts that shape and translates it to your chosen
backend.

## Setup

1. **Map your backends.** Copy `config.example.yaml` → `config.yaml` and edit the
   `model_list`. Each `model_name` is an alias troupely references (the example defines
   `gpt-main` / `gpt-small` to match `providers/profiles/litellm-openai.env`). Backend keys
   come from env vars (`os.environ/OPENAI_API_KEY`) — never inline secrets.

2. **Set secrets.** Create a gitignored `.env` beside this file:
   ```
   LITELLM_MASTER_KEY=sk-litellm-<your-strong-key>
   OPENAI_API_KEY=sk-...
   GEMINI_API_KEY=...
   ```
   `LITELLM_MASTER_KEY` must equal `ANTHROPIC_AUTH_TOKEN` in the troupely profile.

3. **Run the proxy.**
   ```bash
   docker compose -f compose.yaml up -d
   curl -s http://localhost:4000/health   # sanity check
   ```

4. **Point troupely at it.**
   ```bash
   ../troupely-provider use litellm-openai
   docker compose up -d   # restart troupely (from the repo root)
   ```
   The profile uses `ANTHROPIC_BASE_URL=http://litellm:4000` — make sure both containers
   share a compose network so that hostname resolves (run them from one compose project, or
   attach via an external network). For host-run troupely, use `http://localhost:4000`.

## Networking notes

- A **local Ollama** on the host is reachable from the proxy container at
  `http://host.docker.internal:11434` (see the `llama-local` example).
- Pin a specific LiteLLM image digest in production (the compose uses `main-stable` for
  convenience). PyPI `1.82.7`/`1.82.8` were compromised — never install those.

## Switching backends

Change the backend behind an alias in `config.yaml` (e.g. point `gpt-main` at
`gemini/gemini-2.5-pro`), or change `ANTHROPIC_MODEL` in the profile to a different alias you
defined. No troupely code changes either way.
