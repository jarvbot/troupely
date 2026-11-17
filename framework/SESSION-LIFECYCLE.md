# Session lifecycle

How a persona session starts, stays alive, and recovers — re-homed to the **container**, with
no assumptions about a host process manager (launchd / systemd) or a host terminal multiplexer.
The container is the unit of life; the entrypoint owns the lifecycle.

## Boot (handled by the container entrypoint)

On `docker compose up`, the entrypoint (`docker/entrypoint.sh`) for each persona:

1. **Auth-guards** — confirms model auth is present (a subscription login that persists on the
   mounted vault, or a provider key). If not, it sleeps with a hint instead of crash-looping,
   so you can fix auth and restart without rebuilding.
2. **Launches the session** — one `tmux` session per persona running Claude Code with the
   Telegram channel, each with its own bot token + isolated channel state. tmux here is the
   *in-container* keep-alive, not a host dependency.
3. **Arms the heartbeat.** The launcher (`lib/launch-persona.sh`) starts Claude Code with
   `/loop <interval> <tick prompt>` as its first message, so the first tick runs at once (that
   tick is the re-orient) and the rest are scheduled. Set the interval with
   `TROUPELY_HEARTBEAT` in `.env` (`30m` default, `2h`, or `off`).

State (OAuth creds, plugin state, memory) lives on the bind-mounted vault, so it survives
rebuilds — restarting the container does not re-onboard or lose memory.

## First actions in a fresh session

1. **Re-orient** — read canonical state, today's daily log, and **check `processing/` before
   `inbox/`** (resume any in-flight task). See the shared rules → Orient first.
2. **Leave the heartbeat alone.** A session's loops die with the process (fresh boot, crash,
   container restart) and the launcher arms a new one on every launch. They **survive
   `/clear`**, so after a `/clear` do not create another one: list scheduled jobs, and if more
   than one heartbeat is listed, cancel the extras. See `heartbeat/HEARTBEAT.md`.

## Liveness + recovery

- **Keep-alive:** each persona is its own tmux session, so one crashing doesn't take the others
  down. In Docker, PID 1 checks every 60 s and relaunches any persona whose session is gone
  (re-reading the host `.env`, so a persona added with `add` survives a container restart),
  and `restart: unless-stopped` brings the container back after a reboot. Native mode does the
  same only after `./troupely.sh autostart on` (launchd on macOS, a systemd user timer on
  Linux); without it a crashed persona stays down until `./troupely.sh start`.
- **Self-heal a dropped channel:** if the Telegram channel disconnects mid-session, reload the
  plugin and reconnect rather than sitting dead. Surface a brief "recovered" note so the
  operator knows the heal happened.
- **External watchdog (optional, recommended for anything load-bearing):** an in-process
  liveness check dies with the process. For a persona whose silence would be costly (a watcher,
  an executor), add an *out-of-process* watchdog that alerts if the heartbeat goes stale past
  ~2× its interval. The heartbeat writing a timestamp each tick is enough for a separate job to
  check. (This is the C5 health/ops layer — keep it minimal.)

## What deliberately does NOT port from a host stack

The as-run macOS stack used launchd jobs + host tmux + host file paths. None of that ships —
the container is the substrate. The *patterns* port (keep-alive, re-orient-on-boot,
heartbeat-rearm, output-freshness watching); the host-specific mechanics don't.
