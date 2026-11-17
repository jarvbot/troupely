# troupely modules

**Add-ons, not part of the default install.** The core stack (orchestrator, planning,
builder) runs without any module. Add one when a persona needs the capability.

A **module** is a reusable capability you can drop onto any persona: a bundle of
MCP servers, skills, and required env. Instead of hand-wiring an `.mcp.json` and
copying skill files, you run one command and the persona gains the capability.

```sh
./troupely.sh module list                 # what's available
./troupely.sh module add <module> <name>  # add a module to persona <name>
```

`module add` merges the module's MCP servers into the persona's `.mcp.json`,
copies any skills into its `.claude/skills/`, prompts for required secrets (written
to `.env`, gitignored), and enables the servers. Restart the persona to load them.

## Module format

Each module is a directory under `modules/<name>/` with a `module.json`:

```json
{
  "name": "linear",
  "description": "Linear project management — issues, projects, comments.",
  "mcpServers": {
    "linear": { "type": "http", "url": "https://mcp.linear.app/mcp" }
  },
  "env": [
    { "key": "SOME_API_KEY", "prompt": "Your X API key", "required": true }
  ],
  "skills": ["skills/<skill-name>"],
  "notes": "Anything the operator should know — auth flow, prerequisites."
}
```

- **mcpServers** — merged verbatim into the persona's `.mcp.json` (Claude Code's
  standard MCP config). `http`/`sse` remote servers or `stdio` local servers.
- **env** — secrets/config the server needs; the operator is prompted, values land
  in `.env`. Never commit secrets into `module.json`.
- **skills** — optional skill dirs (relative to the module) copied into the persona.
- **notes** — shown after install (e.g. "first use runs the OAuth flow").

## Authoring a module

1. `mkdir modules/<name>` and write `module.json`.
2. Reference a remote MCP by URL, or a local one by command + the env it needs.
3. Add any skills under `modules/<name>/skills/<skill>/SKILL.md`.
4. `./troupely.sh module add <name> <persona>` to test, then restart the persona.

## A note on private / credentialed servers

Modules that wrap a *personal* integration (your bank, broker, vault) should ship
only the **generic** server + an `env` list — never your own keys or a server bound
to your account. Keep credentialed/private modules out of any public fork; put them
in a private module set you apply to your own personas.
