#!/usr/bin/env python3
"""
Opt a persona's bot into its supergroup, restricted to the people paired in DMs.

The Telegram plugin treats a group's empty allowFrom as "anyone in the group", and
group messages never go through pairing. A persona runs with permission prompts off,
so an open group would hand the agent to every member. This keeps the group entry's
allowFrom equal to the persona's paired senders (top-level allowFrom):

  - nobody paired yet  → no group entry, so the group stays closed (pair in DM first)
  - someone paired     → groups[<id>] = {requireMention: false, allowFrom: <paired>}
  - --close            → no group entry (persona isn't topic-routed, so it must not
                         answer the group at all)

Other keys on an existing group entry are kept. Idempotent; safe to run on every
launch and after every pairing.

Usage: group-access.py <telegram-state-dir> <group-id> [--close]
Exit: 0 ok (prints one status line) · 1 bad args or unreadable access.json
"""
import json
import os
import sys

close = sys.argv[3:] == ["--close"]
if len(sys.argv) - close != 3 or not sys.argv[2]:
    print("usage: group-access.py <telegram-state-dir> <group-id> [--close]", file=sys.stderr)
    sys.exit(1)
sd, gid = sys.argv[1], sys.argv[2]
p = os.path.join(sd, "access.json")
try:
    with open(p) as f:
        a = json.load(f)
except FileNotFoundError:
    a = {"dmPolicy": "pairing", "allowFrom": [], "groups": {}, "pending": {}}
except (OSError, ValueError) as e:
    print(f"  ✗ can't read {p}: {e}", file=sys.stderr)
    sys.exit(1)

paired = [str(s) for s in a.get("allowFrom", [])]
groups = a.setdefault("groups", {})
before = json.dumps(groups.get(gid), sort_keys=True)

if close:
    groups.pop(gid, None)
    status = f"group {gid} closed (no topic set for this persona)"
elif paired:
    g = groups.setdefault(gid, {})
    g["requireMention"] = False
    g["allowFrom"] = paired
    status = f"group {gid} open to paired sender(s) {', '.join(paired)}"
else:
    groups.pop(gid, None)
    status = f"group {gid} closed until someone pairs in DM"

if json.dumps(groups.get(gid), sort_keys=True) != before or not os.path.exists(p):
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(a, f, indent=2)
    os.replace(tmp, p)
print(f"  • {status}")
