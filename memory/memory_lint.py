#!/usr/bin/env python3
"""troupely memory linter — enforces the memory-system conventions on heartbeat.

The memory system is conventions + protocols, not code (so it travels) — but
"conventions are aspirational until something enforces them" (design red-team #5).
This linter IS that enforcement. It's a V1 ship-gate and runs every heartbeat.

Four checks:
  1. compile-age      — MEMORY.md / PRIORITIES.md gone stale (not compiled recently)
  2. drain-zombies    — files stuck in any inbox/ or processing/ past a max age
  3. reconcile-drift  — active-tasks vs PRIORITIES edited out of sync (no-drift rule)
  4. producer-deadman — "should-be-live" output files gone stale or empty

Portable: driven by `memory-lint.config.json` (the instance fills paths/thresholds);
ships with a documented example config. Stdlib only. Exit non-zero if any check
fails (so a heartbeat hook can surface it).

Paths: `~` expands; relative paths resolve against the vault root (the directory
holding memory/); drain_dirs paths may be globs (`personas/*/inbox`).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import time

DEFAULT_CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "memory-lint.config.json")
VAULT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _path(p: str) -> str:
    """~ expands; a relative path resolves against the vault root."""
    p = os.path.expanduser(p)
    return p if os.path.isabs(p) else os.path.join(VAULT_ROOT, p)


def _age_hours(path: str, now: float) -> float | None:
    try:
        return (now - os.path.getmtime(path)) / 3600.0
    except OSError:
        return None


def check_compile_age(cfg: dict, now: float) -> list[str]:
    """Canonical compiled files (MEMORY/PRIORITIES) must be touched within max_age_hours."""
    out = []
    for entry in cfg.get("compile_age", []):
        path = _path(entry["path"])
        maxh = entry.get("max_age_hours", 168)  # default 1 week
        age = _age_hours(path, now)
        if age is None:
            out.append(f"compile-age: MISSING {path}")
        elif age > maxh:
            out.append(f"compile-age: {path} stale ({age:.0f}h > {maxh}h) — recompile")
    return out


def check_drain_zombies(cfg: dict, now: float) -> list[str]:
    """Files lingering in inbox/ or processing/ past max_age_hours = a stuck drain."""
    out = []
    for entry in cfg.get("drain_dirs", []):
        maxh = entry.get("max_age_hours", 24)
        ignore = set(entry.get("ignore", []))
        files = [(d, f) for d in sorted(glob.glob(_path(entry["path"])))
                 for f in glob.glob(os.path.join(d, "*"))]
        for d, f in files:
            base = os.path.basename(f)
            if base in ignore or base.startswith(".") or os.path.isdir(f):
                continue
            age = _age_hours(f, now)
            if age is not None and age > maxh:
                out.append(f"drain-zombie: {f} stuck {age:.0f}h in {os.path.basename(d.rstrip('/'))}/ (> {maxh}h)")
    return out


def check_reconcile_drift(cfg: dict, now: float) -> list[str]:
    """No-drift rule: when active-tasks changes, PRIORITIES reconciles same turn.
    Generic proxy — flag if one was edited much more recently than the other
    (a divergence signal worth a human eyeball)."""
    out = []
    r = cfg.get("reconcile_pair")
    if not r:
        return out
    a, b = _path(r["a"]), _path(r["b"])
    skew = r.get("max_skew_hours", 48)
    aa, ab = _age_hours(a, now), _age_hours(b, now)
    if aa is None or ab is None:
        out.append(f"reconcile-drift: missing {a if aa is None else b}")
    elif abs(aa - ab) > skew:
        newer, older = (a, b) if aa < ab else (b, a)
        out.append(f"reconcile-drift: {os.path.basename(newer)} edited {abs(aa-ab):.0f}h "
                   f"after {os.path.basename(older)} (> {skew}h) — verify they're in sync")
    return out


def check_producer_deadman(cfg: dict, now: float) -> list[str]:
    """Should-be-live producers: output FRESH (max_age) + non-empty (min_bytes)."""
    out = []
    for p in cfg.get("producers", []):
        path = _path(p["path"])
        maxh = p.get("max_age_hours", 24)
        minb = p.get("min_bytes", 1)
        age = _age_hours(path, now)
        if age is None:
            out.append(f"producer-deadman: {p.get('name', path)} MISSING ({path})")
            continue
        if age > maxh:
            out.append(f"producer-deadman: {p.get('name', path)} stale ({age:.0f}h > {maxh}h)")
        try:
            if os.path.getsize(path) < minb:
                out.append(f"producer-deadman: {p.get('name', path)} too small (< {minb}B)")
        except OSError:
            pass
    return out


CHECKS = [check_compile_age, check_drain_zombies, check_reconcile_drift, check_producer_deadman]


def lint(cfg: dict, now: float | None = None) -> list[str]:
    now = time.time() if now is None else now
    findings = []
    for c in CHECKS:
        findings.extend(c(cfg, now))
    return findings


def main() -> int:
    ap = argparse.ArgumentParser(description="troupely memory linter")
    ap.add_argument("--config", default=DEFAULT_CONFIG)
    ap.add_argument("--quiet", action="store_true", help="only print on findings")
    args = ap.parse_args()
    try:
        cfg = json.load(open(os.path.expanduser(args.config)))
    except (OSError, ValueError) as e:
        print(f"memory-lint: cannot read config {args.config}: {e}", file=sys.stderr)
        return 2
    findings = lint(cfg)
    if findings:
        print(f"⚠️  memory-lint: {len(findings)} finding(s):")
        for f in findings:
            print(f"  • {f}")
        return 1
    if not args.quiet:
        print("✅ memory-lint: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
