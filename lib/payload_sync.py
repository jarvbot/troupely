#!/usr/bin/env python3
"""Sync the troupely payload (shared rules, memory system, framework, skills) into a vault.

One writer: the Docker entrypoint calls this with the image-baked payload
(/opt/troupely/payload); native mode calls it with the repo root. setup.sh never syncs.

Ownership:
  * troupely-owned files are refreshed on every sync. RULES.md is always overwritten
    (it is never user-edited; put your own rules in CLAUDE.md). Any other owned file
    the user has edited is left alone and the new version lands next to it as
    <file>.troupely-new. A file the user deleted is recorded as deleted and not
    brought back.
  * seed-once files (CLAUDE.md, the linter config) are created if missing and then
    never touched.

State lives in <vault>/.troupely/payload.json. An older payload VERSION than the
manifest records means a downgrade: nothing is synced and a warning is printed.

usage: payload_sync.py <payload-root> <vault-dir>
"""
import hashlib
import json
import os
import shutil
import sys

# (source path in payload, dest path in vault). Directories are walked.
OWNED = [
    ("RULES.md", "RULES.md"),
    ("MEMORY-SYSTEM.md", "MEMORY-SYSTEM.md"),
    ("framework", "framework"),
    ("memory/memory_lint.py", "memory/memory_lint.py"),
    ("skills", ".claude/skills"),
]
ALWAYS_OVERWRITE = {"RULES.md"}
SEED_ONCE = [
    ("templates/vault-CLAUDE.md", "CLAUDE.md"),
    ("memory/memory-lint.config.json", "memory/memory-lint.config.json"),
]
SKIP_NAMES = {"__pycache__", ".DS_Store"}


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def vtuple(v):
    out = []
    for part in v.strip().split("."):
        try:
            out.append(int(part))
        except ValueError:
            out.append(0)
    return tuple(out)


def walk(payload, src, dest):
    """Yield (abs_src, rel_dest) for a file or every file under a directory."""
    a = os.path.join(payload, src)
    if os.path.isfile(a):
        yield a, dest
        return
    for root, dirs, files in os.walk(a):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_NAMES)
        for name in sorted(files):
            if name in SKIP_NAMES or name.endswith(".pyc"):
                continue
            s = os.path.join(root, name)
            yield s, os.path.join(dest, os.path.relpath(s, a))


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = dst + ".troupely-tmp"
    shutil.copy2(src, tmp)
    os.replace(tmp, dst)


def main(payload, vault):
    version = open(os.path.join(payload, "VERSION")).read().strip()
    state_dir = os.path.join(vault, ".troupely")
    man_path = os.path.join(state_dir, "payload.json")
    try:
        with open(man_path) as f:
            man = json.load(f)
    except (OSError, ValueError):
        man = {"version": "0", "files": {}}

    if vtuple(version) < vtuple(man.get("version", "0")):
        print(f"  ⚠ payload {version} is older than the vault's {man['version']}: "
              "not syncing (no downgrades). Rebuild from a newer checkout.", file=sys.stderr)
        return 0

    files = man.setdefault("files", {})
    counts = {"updated": 0, "unchanged": 0, "kept-edited": 0, "deleted": 0, "seeded": 0}

    for src, dest in OWNED:
        for s, rel in walk(payload, src, dest):
            d = os.path.join(vault, rel)
            new = sha(s)
            rec = files.get(rel)
            if not os.path.exists(d):
                if rec is not None and rel not in ALWAYS_OVERWRITE:
                    files[rel] = "deleted"          # user removed it: respect that
                    counts["deleted"] += 1
                    continue
                copy(s, d)
                files[rel] = new
                counts["updated"] += 1
                continue
            cur = sha(d)
            if cur == new:
                files[rel] = new
                counts["unchanged"] += 1
            elif rel in ALWAYS_OVERWRITE or rec == cur:
                # owned file unchanged since our last sync: refresh it
                copy(s, d)
                files[rel] = new
                counts["updated"] += 1
            elif rec == new:
                # edited locally, but our version hasn't moved since the last sync:
                # nothing new to offer, so don't re-warn on every boot
                counts["kept-edited"] += 1
            else:
                copy(s, d + ".troupely-new")
                files[rel] = new                    # offered once; warn again only on the next change
                counts["kept-edited"] += 1
                print(f"  ⚠ {rel} was edited locally; kept yours, new version at "
                      f"{rel}.troupely-new", file=sys.stderr)

    for src, dest in SEED_ONCE:
        s = os.path.join(payload, src)
        d = os.path.join(vault, dest)
        if os.path.isfile(s) and not os.path.exists(d):
            copy(s, d)
            counts["seeded"] += 1

    man["version"] = version
    os.makedirs(state_dir, exist_ok=True)
    tmp = man_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(man, f, indent=2, sort_keys=True)
    os.replace(tmp, man_path)
    print(f"  ✓ payload {version} synced: " + ", ".join(f"{v} {k}" for k, v in counts.items()))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
