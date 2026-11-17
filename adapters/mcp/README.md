# MCP adapter — the general third-party integration pattern

Most external services a persona needs (Linear, GitHub, Notion, a custom internal API) connect
the same way: as an **MCP server** the persona's Claude Code session can call tools on. This is
the one pattern to learn; specific services are just instances of it.

## Wiring (config, not keys)

MCP servers are declared in the persona's Claude Code config (e.g. a `.mcp.json` in the persona
dir, or the user/project settings). The declaration carries the connection — **not** the
secret. Two shapes:

- **Remote (URL) server** — the common case for hosted services:
  ```json
  {
    "mcpServers": {
      "linear": { "type": "http", "url": "https://mcp.linear.app/mcp" }
    }
  }
  ```
  Auth is an OAuth flow you complete once (interactively); the token persists on the vault
  (`/vault/.claude`), not in this file.

- **Local (stdio) server** — a tool you run yourself:
  ```json
  {
    "mcpServers": {
      "my-tool": { "command": "node", "args": ["/vault/tools/my-mcp-server.js"],
                   "env": { "MY_TOKEN": "${MY_TOKEN}" } }
    }
  }
  ```
  Any secret comes from the environment (`${MY_TOKEN}` resolved from the gitignored `.env`),
  referenced by name — never written into the config.

## Linear (worked example)

Project tracking is a natural MCP adapter — it gives the operator a mobile-readable surface for
project state and operator-facing questions, separate from the agent-to-agent inboxes.

1. Declare the server: `{ "linear": { "type": "http", "url": "https://mcp.linear.app/mcp" } }`.
2. Complete the Linear OAuth once from the session; the token persists on the vault.
3. The persona now has Linear tools (create issue, comment, list). Convention worth keeping:
   stamp issues with a `from-<persona>` label so the operator knows which persona authored, and
   extract the operator-facing content into the issue body (don't path-drop — they read it on a
   phone).

## Adding any other service

Same three steps: declare the server (URL or command), complete its auth once (persists on the
vault), use its tools. The key never touches a tracked file. If a service has no MCP server,
wrap its API in a small local stdio MCP server under `/vault/tools/` and declare that.
