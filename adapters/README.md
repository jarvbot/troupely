# Adapters

How a troupely persona reaches the outside world — Telegram, Linear, other MCP services, bot
minting. The principle is in the name: **adapters, not keys.** The package ships the *wiring*
(how to connect, what config shape) and never a secret. Keys come from your gitignored `.env`
or your OS secret store at runtime; the `.gitignore` + the pre-commit secret-scan hook make
shipping one hard on purpose.

| Adapter | What it connects | How it's wired | Key lives in |
|---|---|---|---|
| **telegram** | The persona's chat channel (operator ↔ persona) | The official Telegram channel plugin, launched per-persona by the container entrypoint | per-persona `.env` (`TROUPELY_TG_TOKEN_<NAME>`) |
| **mcp** | Any MCP service (the general pattern) | An MCP server entry in the persona's Claude Code config | gitignored config / env |
| **linear** | Project tracking (a worked MCP example) | An MCP server (`mcp.linear.app`) — see `mcp/` | OAuth, gitignored |
| **mint-bot** | Minting new Telegram bots for new personas | A small minter script driving a manager bot | OS secret store |

## telegram (live)

Already wired by the container: the entrypoint launches each persona's Claude Code session with
the official Telegram channel plugin and an isolated channel-state dir, reading that persona's
bot token from `TROUPELY_TG_TOKEN_<NAME>` (set in `.env`). Inbound messages inject into the
session; the persona replies through the plugin. Nothing to build per persona beyond minting a
bot (see `mint-bot/`) and setting its token. First DM gets gated by the plugin's access
control — pair the operator's chat once, then it's open.

## The "adapters not keys" rule

- Connection config (server URLs, plugin names, the *shape* of what's needed) ships in the
  package. **Secrets never do.**
- At runtime, a key arrives from your `.env` (gitignored) or OS secret store and is referenced
  by name, never inlined into a tracked file.
- Placeholders in any shipped example are obviously fake (`sk-…-REPLACE_ME`).
- The pre-commit hook scans staged changes for real-shaped tokens and blocks the commit. If you
  ever see it fire, it did its job — move the secret to `.env`.

See `mcp/` for the general third-party-integration pattern (Linear is the worked example) and
`mint-bot/` for bringing a new persona online.

## Optional capability tools (enrich a persona — opt-in, per-lane)

Beyond the core four, you'll want to give specific personas extra reach: an X/Twitter reader,
a web scanner, a market-data CLI, a niche API. These are **per-persona options**, not
stack-wide installs — give the specialist an X-reader, the EA a calendar tool, and nothing
gets capabilities it doesn't need. Wire each one the same two ways as any adapter:

- **As an MCP server** (preferred when one exists) — declare it in the persona's config; tools
  appear in that persona's session only. See `mcp/`.
- **As a local CLI the persona calls via Bash** — drop the binary on the vault (`/vault/tools/`)
  and the persona invokes it. If it has no MCP server, wrap its API in a tiny local stdio MCP
  server so it's a first-class tool with typed args.

Enable a tool only in the personas that need it (its CLAUDE.md names what it has). That keeps
each persona's surface small and its blast radius bounded.

### ⚠️ Vet third-party tools before you wire them — especially scrapers

troupely ships the *pattern* + vetted examples, **not a grab-bag of scrapers**, on purpose.
A tool like an X/Twitter or social scraper carries real risk that varies per tool:

- **Supply chain.** Verify the source + maintainer before installing. A cautionary real case:
  a popular X-reader's original repo was taken down, its handle squatted, and downstream forks
  were contaminated — pulling "the obvious one" from a search would land you malware. Pin to a
  source you can personally vouch for; build from clean source rather than a random binary;
  scan before you trust (and **especially** before you redistribute to anyone else).
- **Terms of service / licensing.** Scraping X/Twitter, LinkedIn, etc. may violate ToS or
  licensing. That's the operator's call to make per tool, not a default the package makes for you.
- **Secrets.** The tool's keys follow the same rule as every adapter — gitignored `.env` or the
  OS secret store, referenced by name, never committed.

Rule of thumb: if you wouldn't `curl | bash` it onto your laptop, don't wire it into a persona.
Bring your own vetted tools; troupely makes adding them clean — it doesn't vouch for them.
