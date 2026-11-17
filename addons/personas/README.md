# Add-on persona archetypes

Optional. The default install is the core three in [`../../personas/`](../../personas/)
(orchestrator, planning, builder), and a stack runs fine without anything here.

| Archetype | Role | Owns | Hands off to |
|---|---|---|---|
| `specialist` | One domain, deep | a single domain lane (research, trading, ops, …) | builder / orchestrator |
| `executive-assistant` | Comms, scheduling, triage for a principal | a principal's inbox/calendar surface (gated) | orchestrator |

Add one with `./troupely.sh add specialist <name>`, or pick "Add-on archetypes…" in
`./setup.sh`. Each archetype's `CLAUDE.md` imports `@../../CLAUDE.md`, which resolves once the
archetype is copied to `vault/personas/<name>/`.
