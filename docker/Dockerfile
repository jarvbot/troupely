# troupely base image — a portable multi-persona Claude Code stack.
#
# Generalized from a proven single-persona substrate (Claude Code in a
# long-running container with the Telegram plugin). troupely runs N personas as N
# tmux sessions in ONE container (topology A, the lean default); see compose for
# the opt-in per-persona-container scale-out (topology B).
#
# Runs as a non-root user matching the HOST uid/gid (build args) so the
# volume-mounted /vault has matching ownership inside + outside. Claude Code
# refuses --dangerously-skip-permissions as root, hence the user setup.
#
#   Build:  docker compose build              (set HOST_UID/HOST_GID if not 501/20)
#   Run:    docker compose up -d
#   Auth (one-time, interactive from host, per persona that uses a subscription):
#           docker exec -it troupely claude auth login --claudeai
#   After OAuth the creds persist at /vault/.claude (volume-mounted) across rebuilds.

FROM node:20-bookworm-slim

# System deps: tmux (per-persona sessions + keep-alive), git/curl/jq (ad-hoc),
# python3 (skills/linter — stdlib; personas add their own libs via a derived image),
# procps, sudo, less.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq python3 python3-pip python3-venv \
        tmux less procps sudo \
    && rm -rf /var/lib/apt/lists/*

# bun — the official Telegram plugin's server.ts runs under bun, not node.
RUN npm install -g bun

# Claude Code via Anthropic's official installer (lands at /root/.local/bin/claude);
# copy to a globally-readable path so the non-root user can run it.
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/install-claude.sh \
    && bash /tmp/install-claude.sh \
    && cp /root/.local/bin/claude /usr/local/bin/claude \
    && chmod 0755 /usr/local/bin/claude \
    && rm /tmp/install-claude.sh

# Non-root user matching the HOST uid/gid. Defaults = macOS (501 / staff 20);
# Linux hosts are usually 1000/1000 — override at build: --build-arg HOST_UID=1000 ...
ARG HOST_UID=501
ARG HOST_GID=20
# node:20 ships a `node` user/group at uid/gid 1000 — the usual Linux host default —
# so `useradd -u 1000` collides ("UID is not unique"). Remove whatever user already
# holds HOST_UID before creating troupe. (--non-unique on the group lets troupegroup
# share a gid with an existing group, e.g. macOS staff=20 / node=1000.)
RUN groupadd -g "${HOST_GID}" --non-unique troupegroup || true \
    && if getent passwd "${HOST_UID}" >/dev/null; then \
         userdel -rf "$(getent passwd "${HOST_UID}" | cut -d: -f1)"; \
       fi \
    && useradd -m -u "${HOST_UID}" -g "${HOST_GID}" -s /bin/bash troupe

# /vault is the volume-mounted host workspace. Claude Code stores OAuth + plugin
# state under $HOME → point HOME there so auth + state persist across rebuilds.
# Chown the built-in /vault to the non-root user so a bare `docker run` (no mount,
# or a named volume) still boots to the auth guard instead of dying on a perms
# error. A host bind-mount masks this dir with the host's ownership at runtime.
RUN mkdir -p /vault && chown troupe:troupegroup /vault
WORKDIR /vault
ENV HOME=/vault
ENV PATH="/usr/local/bin:/usr/bin:/bin"
# Telegram plugin (server) + /telegram:access skill both resolve their state from
# $HOME/.claude/channels/telegram — and the skill HARDCODES that path (it ignores
# TELEGRAM_STATE_DIR). The entrypoint therefore isolates personas by giving each
# its OWN HOME (vault/.claude/homes/<persona>) rather than a per-persona
# TELEGRAM_STATE_DIR, so server + skill stay aligned per persona and pairing works.

# NOTE: build context is the REPO ROOT (see docker/compose.yaml), so paths below
# are repo-root-relative.
COPY --chown=troupe:troupegroup docker/entrypoint.sh /usr/local/bin/troupely-entrypoint.sh
RUN chmod +x /usr/local/bin/troupely-entrypoint.sh

# topic-filter patch for the Telegram plugin (public plugin doesn't read
# TELEGRAM_TOPIC_FILTER; the entrypoint applies this after plugin install).
COPY --chown=troupe:troupegroup plugin-patch /usr/local/lib/troupely/plugin-patch

# The shared payload (rules, memory system, framework, skills) is baked into the image
# at a versioned path. The entrypoint is its only writer into /vault (lib/payload_sync.py):
# RULES.md is always refreshed, CLAUDE.md is seeded once and then belongs to you.
COPY --chown=troupe:troupegroup lib /usr/local/lib/troupely/lib
COPY --chown=troupe:troupegroup VERSION RULES.md MEMORY-SYSTEM.md /opt/troupely/payload/
COPY --chown=troupe:troupegroup framework /opt/troupely/payload/framework
COPY --chown=troupe:troupegroup skills /opt/troupely/payload/skills
COPY --chown=troupe:troupegroup templates /opt/troupely/payload/templates
COPY --chown=troupe:troupegroup memory/memory_lint.py memory/memory-lint.config.json /opt/troupely/payload/memory/

USER troupe
ENTRYPOINT ["/usr/local/bin/troupely-entrypoint.sh"]
