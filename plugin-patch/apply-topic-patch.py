#!/usr/bin/env python3
"""
Teach the installed Telegram channel plugin to honor TELEGRAM_TOPIC_FILTER.

The public telegram@claude-plugins-official plugin already handles supergroups
(allowlist + requireMention) but has NO topic filtering — it never reads
TELEGRAM_TOPIC_FILTER, so a bot scoped to a forum topic still answers every topic
in the group. troupely's supergroup-topic routing needs that filter, so this
patch injects it into the installed plugin's server.ts.

It's a surgical, idempotent, generic patch (Apache-2.0 plugin; this adds the
TELEGRAM_TOPIC_FILTER behavior and nothing else):
  1. a tiny helper block (parse + filter) just above `function gate(...)`
  2. a one-line inbound drop at the top of gate(): if a topic filter is set and
     the inbound message's message_thread_id doesn't match, drop it.

  3. an outbound API transformer right after `const bot = new Bot(TOKEN)`: every
     send to a group that carries no message_thread_id gets the filter's topic.
     The public plugin never sets message_thread_id and tells the model to omit
     reply_to on normal answers, so without this a topic-routed persona's replies
     land in the group's General topic.

Stages 1-2 and stage 3 have separate markers, so an install patched before stage 3
existed picks it up on the next run.

Safe by design: if the plugin already understands TELEGRAM_TOPIC_FILTER, or the
anchor isn't found (upstream changed), it leaves the file untouched and exits 0 —
DM/group routing keeps working, only topic scoping is unavailable.

Every server.ts under the root is patched (one per installed version dir), so the
version Claude Code actually loads is covered whichever it is.

Usage: apply-topic-patch.py [--check] <plugin-dir-or-glob-root>
       (defaults to $HOME/.claude/plugins/cache/claude-plugins-official/telegram)
  --check   change nothing; print each server.ts and whether it filters topics.
            Exit 1 if any lacks the filter, or no server.ts exists.

Why not pin the plugin: Claude Code reserves the marketplace name
claude-plugins-official for GitHub sources in the anthropics org, so a vendored copy
can't keep the plugin id the --channels flag loads, and a GitHub #ref takes a branch or
tag (the repo has no tags), not a commit. So troupely records the version it was tested
against and `./troupely.sh status` warns when the installed one differs.
"""
import glob
import json
import os
import sys

# The plugin version this patch was last verified against (anchors + live topic routing).
TESTED_VERSION = "0.0.7"

GATE_ANCHOR = "function gate(ctx: Context): GateResult {"

HELPERS = """// --- troupely topic-filter patch (honors TELEGRAM_TOPIC_FILTER) ---
function __parseTopicFilter(raw: string | undefined): number | undefined {
  if (raw == null || raw === '') return undefined
  const n = Number(raw)
  if (!Number.isInteger(n) || n < 0) {
    throw new Error(`TELEGRAM_TOPIC_FILTER must be a non-negative integer (got "${raw}")`)
  }
  return n
}
function __topicFilterAllows(filter: number | undefined, messageThreadId: number | undefined): boolean {
  if (filter === undefined) return true
  return (messageThreadId ?? 0) === filter
}
const __TOPIC_FILTER = __parseTopicFilter(process.env.TELEGRAM_TOPIC_FILTER)
// --- end troupely topic-filter patch ---

"""

# Groups only: a DM has no message_thread_id, so filtering it would drop every DM,
# pairing included, once a persona is topic-routed.
GATE_CALL = ("if (ctx.chat?.type !== 'private' && "
             "!__topicFilterAllows(__TOPIC_FILTER, ctx.message?.message_thread_id)) return { action: 'drop' }")
GATE_FILTER = (
    "\n  // troupely: scope this bot to its forum topic when TELEGRAM_TOPIC_FILTER is set\n"
    "  " + GATE_CALL + "\n"
)
# The pre-fix gate line (filtered DMs too); replaced in place on the next run.
OLD_GATE_CALL = "if (!__topicFilterAllows(__TOPIC_FILTER, ctx.message?.message_thread_id)) return { action: 'drop' }"

BOT_ANCHOR = "const bot = new Bot(TOKEN)\n"
OUTBOUND_MARKER = "troupely topic-outbound patch"

OUTBOUND = """// --- troupely topic-outbound patch (sends land in TELEGRAM_TOPIC_FILTER's topic) ---
{
  const raw = process.env.TELEGRAM_TOPIC_FILTER
  const tid = raw == null || raw === '' ? NaN : Number(raw)
  // 0 is General, which takes no message_thread_id.
  if (Number.isInteger(tid) && tid > 0) {
    bot.api.config.use((prev, method, payload, signal) => {
      const p = payload as Record<string, unknown> | undefined
      if (p && method.startsWith('send') && p.message_thread_id == null &&
          String(p.chat_id ?? '').startsWith('-')) {
        return prev(method, { ...p, message_thread_id: tid } as typeof payload, signal)
      }
      return prev(method, payload, signal)
    })
  }
}
// --- end troupely topic-outbound patch ---
"""


def find_servers(root: str) -> list[str]:
    if os.path.isfile(root):
        return [root]
    found = set(glob.glob(os.path.join(root, "**", "server.ts"), recursive=True))
    return sorted(f for f in found if "node_modules" not in f.split(os.sep))


def version_of(server: str) -> str:
    d = os.path.dirname(server)
    for _ in range(3):
        pj = os.path.join(d, ".claude-plugin", "plugin.json")
        if os.path.isfile(pj):
            try:
                return str(json.load(open(pj)).get("version", "?"))
            except (OSError, ValueError):
                return "?"
        d = os.path.dirname(d)
    return "?"


def has_filter_code(src: str) -> bool:
    """Topic-filter code outside our outbound block (that block reads the variable too)."""
    a = src.find("// --- troupely topic-outbound patch")
    if a != -1:
        b = src.find("// --- end troupely topic-outbound patch ---", a)
        src = src[:a] + (src[b:] if b != -1 else "")
    return "function __topicFilterAllows(" in src or "TELEGRAM_TOPIC_FILTER" in src


def status_of(src: str) -> tuple[bool, bool]:
    """(inbound, outbound) as troupely verifies them: our exact gate call inside gate(),
    and our outbound block. Anything else, including an upstream implementation, counts
    as unverified."""
    g = src.find(GATE_ANCHOR)
    inbound = g != -1 and GATE_CALL in src[g:g + len(GATE_ANCHOR) + len(GATE_FILTER) + 8] \
        and "function __topicFilterAllows(" in src
    return inbound, OUTBOUND_MARKER in src


def patch_one(server: str) -> bool:
    """Patch one server.ts. True when both halves end up in place."""
    src = open(server).read()
    patched = src.replace(OLD_GATE_CALL, GATE_CALL) if GATE_CALL not in src else src
    inbound, _ = status_of(patched)
    if not inbound:
        if GATE_ANCHOR not in patched:
            print(f"  ⚠ topic-patch: gate() anchor not found in {server} (plugin changed); "
                  "topic scoping unavailable there, DM/group routing unaffected.", file=sys.stderr)
        elif has_filter_code(patched):
            print(f"  ⚠ topic-patch: {server} has topic-filter code troupely didn't write, or a "
                  "partial patch; left alone. Check it by hand.", file=sys.stderr)
        else:
            patched = patched.replace(GATE_ANCHOR, HELPERS + GATE_ANCHOR + GATE_FILTER, 1)
    if OUTBOUND_MARKER not in patched:
        if BOT_ANCHOR in patched:
            patched = patched.replace(BOT_ANCHOR, BOT_ANCHOR + OUTBOUND, 1)
        else:
            print(f"  ⚠ topic-patch: Bot() anchor not found in {server}; topic replies may land "
                  "in General.", file=sys.stderr)
    if patched != src:
        tmp = server + ".tmp"
        with open(tmp, "w") as f:
            f.write(patched)
        os.replace(tmp, server)
        print(f"  ✓ topic-patch: applied to {server}")
    return all(status_of(patched))


def main() -> int:
    args = sys.argv[1:]
    check = "--check" in args
    args = [a for a in args if a != "--check"]
    root = args[0] if args else os.path.expanduser(
        "~/.claude/plugins/cache/claude-plugins-official/telegram"
    )
    servers = find_servers(root)
    if not servers:
        print(f"  ⚠ topic-patch: no server.ts under {root} (plugin not installed?); "
              "topic scoping unavailable.", file=sys.stderr)
        return 1 if check else 0
    bad = 0
    for server in servers:
        ver = version_of(server)
        try:
            if check:
                inb, outb = status_of(open(server).read())
                if inb and outb:
                    print(f"  ✓ telegram {ver}: filters topics, replies threaded ({server})")
                else:
                    miss = " and ".join(x for x, ok in (("NO topic filter", inb), ("replies NOT threaded", outb)) if not ok)
                    print(f"  ✗ telegram {ver}: {miss} ({server})")
                bad += not (inb and outb)
            else:
                bad += not patch_one(server)
        except OSError as e:
            print(f"  ✗ topic-patch: can't read or write {server}: {e}", file=sys.stderr)
            bad += 1
        if ver not in ("?", TESTED_VERSION):
            print(f"  ⚠ telegram plugin {ver} installed; troupely's topic patch was tested on "
                  f"{TESTED_VERSION}. Check topic routing after upgrades.", file=sys.stderr)
    return 1 if (check and bad) else 0


if __name__ == "__main__":
    sys.exit(main())
