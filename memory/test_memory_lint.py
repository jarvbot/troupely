"""Tests for the troupely memory linter — each of the 4 checks, clean + dirty."""
import os
import sys
import time
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import memory_lint as ml

NOW = 1_750_000_000.0
H = 3600.0


def _touch(path, age_hours):
    with open(path, "w") as f:
        f.write("x" * 200)
    t = NOW - age_hours * H
    os.utime(path, (t, t))


def _layout(tmp):
    os.makedirs(os.path.join(tmp, "memory"))
    os.makedirs(os.path.join(tmp, "inbox"))
    os.makedirs(os.path.join(tmp, "processing"))
    return tmp


def _cfg(tmp):
    return {
        "compile_age": [{"path": f"{tmp}/memory/MEMORY.md", "max_age_hours": 168}],
        "drain_dirs": [{"path": f"{tmp}/processing", "max_age_hours": 24, "ignore": [".gitkeep"]}],
        "reconcile_pair": {"a": f"{tmp}/memory/active-tasks.md", "b": f"{tmp}/PRIORITIES.md", "max_skew_hours": 48},
        "producers": [{"name": "digest", "path": f"{tmp}/memory/digest.md", "max_age_hours": 24, "min_bytes": 100}],
    }


def test_clean_layout_no_findings():
    with tempfile.TemporaryDirectory() as tmp:
        _layout(tmp)
        _touch(f"{tmp}/memory/MEMORY.md", 1)
        _touch(f"{tmp}/memory/active-tasks.md", 2)
        _touch(f"{tmp}/PRIORITIES.md", 2)
        _touch(f"{tmp}/memory/digest.md", 1)
        assert ml.lint(_cfg(tmp), now=NOW) == []


def test_compile_age_stale():
    with tempfile.TemporaryDirectory() as tmp:
        _layout(tmp)
        _touch(f"{tmp}/memory/MEMORY.md", 200)        # > 168h
        _touch(f"{tmp}/memory/active-tasks.md", 2); _touch(f"{tmp}/PRIORITIES.md", 2)
        _touch(f"{tmp}/memory/digest.md", 1)
        f = ml.lint(_cfg(tmp), now=NOW)
        assert any("compile-age" in x and "MEMORY.md" in x for x in f)


def test_drain_zombie():
    with tempfile.TemporaryDirectory() as tmp:
        _layout(tmp)
        _touch(f"{tmp}/memory/MEMORY.md", 1)
        _touch(f"{tmp}/memory/active-tasks.md", 2); _touch(f"{tmp}/PRIORITIES.md", 2)
        _touch(f"{tmp}/memory/digest.md", 1)
        _touch(f"{tmp}/processing/stuck-task.md", 48)  # > 24h in processing
        f = ml.lint(_cfg(tmp), now=NOW)
        assert any("drain-zombie" in x and "stuck-task" in x for x in f)


def test_drain_zombie_ignores_gitkeep():
    with tempfile.TemporaryDirectory() as tmp:
        _layout(tmp)
        _touch(f"{tmp}/memory/MEMORY.md", 1)
        _touch(f"{tmp}/memory/active-tasks.md", 2); _touch(f"{tmp}/PRIORITIES.md", 2)
        _touch(f"{tmp}/memory/digest.md", 1)
        _touch(f"{tmp}/processing/.gitkeep", 999)      # ignored
        assert ml.lint(_cfg(tmp), now=NOW) == []


def test_reconcile_drift():
    with tempfile.TemporaryDirectory() as tmp:
        _layout(tmp)
        _touch(f"{tmp}/memory/MEMORY.md", 1)
        _touch(f"{tmp}/memory/active-tasks.md", 1)     # edited 1h ago
        _touch(f"{tmp}/PRIORITIES.md", 100)            # edited 100h ago → 99h skew > 48h
        _touch(f"{tmp}/memory/digest.md", 1)
        f = ml.lint(_cfg(tmp), now=NOW)
        assert any("reconcile-drift" in x for x in f)


def test_producer_deadman_stale_and_empty():
    with tempfile.TemporaryDirectory() as tmp:
        _layout(tmp)
        _touch(f"{tmp}/memory/MEMORY.md", 1)
        _touch(f"{tmp}/memory/active-tasks.md", 2); _touch(f"{tmp}/PRIORITIES.md", 2)
        _touch(f"{tmp}/memory/digest.md", 99)          # stale > 24h
        f = ml.lint(_cfg(tmp), now=NOW)
        assert any("producer-deadman" in x and "digest" in x for x in f)
        # empty producer
        with open(f"{tmp}/memory/digest.md", "w") as fh:
            fh.write("")
        os.utime(f"{tmp}/memory/digest.md", (NOW, NOW))
        f2 = ml.lint(_cfg(tmp), now=NOW)
        assert any("too small" in x for x in f2)


def test_missing_files_flagged():
    with tempfile.TemporaryDirectory() as tmp:
        _layout(tmp)  # nothing created
        f = ml.lint(_cfg(tmp), now=NOW)
        assert any("MISSING" in x for x in f)


def test_drain_glob_and_relative_paths():
    with tempfile.TemporaryDirectory() as tmp:
        for p in ("alpha", "beta"):
            os.makedirs(f"{tmp}/personas/{p}/inbox")
        _touch(f"{tmp}/personas/beta/inbox/old.md", 48)
        _touch(f"{tmp}/personas/alpha/inbox/new.md", 1)
        old_root = ml.VAULT_ROOT
        ml.VAULT_ROOT = tmp
        try:
            f = ml.lint({"drain_dirs": [{"path": "personas/*/inbox", "max_age_hours": 24}]}, now=NOW)
        finally:
            ml.VAULT_ROOT = old_root
        assert len(f) == 1 and "beta/inbox/old.md" in f[0], f


if __name__ == "__main__":
    import traceback
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    p = 0
    for fn in fns:
        try:
            fn(); print(f"  ✓ {fn.__name__}"); p += 1
        except Exception:
            print(f"  ✗ {fn.__name__}"); traceback.print_exc()
    print(f"\n{p}/{len(fns)} passed")
    sys.exit(0 if p == len(fns) else 1)
