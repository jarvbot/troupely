# Persona archetypes

The three core archetypes of a troupely stack. Optional ones (`specialist`,
`executive-assistant`) live in [`../addons/personas/`](../addons/personas/). Each is a **thin** `CLAUDE.md` — identity,
scope, voice, heartbeat, permissions — and nothing else. Thin is the point: a small,
purpose-built context is what makes a persona fast and focused. Orchestration baggage,
unused tools, and other personas' concerns are exactly what you leave out.

| Archetype | Role | Owns | Hands off to |
|---|---|---|---|
| `orchestrator` | Routes work, holds canonical state, keeps the operator in the loop | priorities, canonical state, the shared inbox | everyone |
| `planning` | Turns rough ideas into build-ready designs; redlines other people's plans | idea curation, design docs, plan reviews | builder |
| `builder` | Scoped spec → working prototype; codes, tests, iterates | back-of-funnel building, the active project dir | orchestrator (on completion) |

## How to use

1. Start with the core three (or just the orchestrator) and add others when a lane needs one. Copy each into your
   instance and rename to your persona's actual name.
2. Fill the `<…>` placeholders — the persona's name, its domain, the operator's name, channel
   IDs. Everything in angle brackets is instance-specific.
3. Each archetype ends with `@../../CLAUDE.md` — the shared-rules file, which itself imports
   `MEMORY-SYSTEM.md`. So a persona gets the shared conventions + the memory rules through one
   import. The path is **relative to the CLAUDE.md file** (set for the package layout
   `personas/<name>/CLAUDE.md` → repo-root `CLAUDE.md`); fix it if you relocate the archetype.
4. Add the persona to your roster (`TROUPELY_PERSONAS` / `troupely-roster.json` / a
   `personas/<name>/` dir) and give it a bot token. See the top-level README.

## Conventions every archetype shares

- **Heartbeat** — each runs a periodic playbook (drain inbox → log state → do maintenance).
  See each file's Heartbeat section and `framework/heartbeat/`.
- **Memory** — per the imported `MEMORY-SYSTEM.md`: write state changes the same turn, recall
  via the compiled index + dated logs + atomic notes.
- **Inboxes** — three-state drain (`inbox/ → processing/ → done`). Cross-persona handoffs go
  to the target's inbox; canonical-state changes go to the orchestrator.
- **Keep the operator in the loop** — when you pick up a cross-persona handoff, tell the
  operator (one line on accept, one on done/blocked). Silent magic erodes trust.
