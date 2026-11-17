#!/usr/bin/env python3
"""The one writer for troupely's .env: set KEY=VALUE pairs, keep every other line.

  envfile.py <path> KEY=VALUE [KEY=VALUE ...] [-KEY ...]

`-KEY` deletes every KEY= line (used by `troupely.sh remove`).

.env is read two ways: `set -a; . .env` in bash, and `--env-file` in docker compose.
Values are written single-quoted, which both treat as literal: no `$` expansion, no
command substitution. A single quote or a control character can't be represented
that way in both, so those values are refused rather than mangled. Keys must be
shell identifiers. The file is written atomically and always left mode 600: it
holds bot tokens and API keys.
"""
import os, re, sys

KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def check(key, val):
    if not KEY_RE.match(key):
        sys.exit(f"✗ invalid .env key: {key!r}")
    if "'" in val or any(ord(ch) < 32 or ord(ch) == 127 for ch in val):
        sys.exit(f"✗ value for {key} contains a quote or control character; refusing to write it")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path, pairs = sys.argv[1], sys.argv[2:]
    updates, drops = [], []
    for kv in pairs:
        if kv.startswith("-"):
            if not KEY_RE.match(kv[1:]):
                sys.exit(f"✗ invalid .env key: {kv[1:]!r}")
            drops.append(kv[1:])
            continue
        if "=" not in kv:
            sys.exit(f"✗ expected KEY=VALUE, got {kv!r}")
        k, v = kv.split("=", 1)
        check(k, v)
        updates.append((k, v))
    lines = open(path).read().splitlines() if os.path.exists(path) else [
        "# troupely — written by setup.sh / troupely.sh. Gitignored. Values are literal."]
    lines = [l for l in lines if not any(l.startswith(k + "=") for k in drops)]
    for k, v in updates:
        new = f"{k}='{v}'"
        for i, l in enumerate(lines):
            if l.startswith(k + "="):
                lines[i] = new
                break
        else:
            lines.append(new)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


if __name__ == "__main__":
    main()
