# Tests

Plain bash, no test framework. Each suite prints `N passed, M failed` and exits non-zero
on any failure. Nothing touches a real install: every suite builds its own sandbox.

| suite | covers | needs |
|---|---|---|
| `test_units.sh` | `.env` writer, group access, `pair`, payload sync | python3 |
| `test_topic_patch.sh` | topic patch on the real upstream plugin (`fixtures/telegram-0.0.7`), `status` check | python3 (bun optional) |
| `test_secret_isolation.sh` | persona env scrub (W3) | python3 |
| `test_setup.sh` | `setup.sh` re-run, no-echo secrets | python3, fake curl/docker |
| `test_lifecycle.sh` | start/stop/restart <name>/update/remove/uninstall, heartbeat arming, stale lock | tmux, git |
| `test_docker_guard.sh` | image builds; a no-auth container holds with a hint | Docker |
| `../memory/test_memory_lint.py` | memory linter | python3 |

Run everything: `for t in tests/test_*.sh; do bash "$t" || echo "FAILED: $t"; done`

CI (`.github/workflows/ci.yml`) runs all of them on Ubuntu, plus shellcheck. macOS is not
in CI (runner minutes): run the suites on a Mac before tagging a release. The launchd half
of `autostart` and the Linux systemd half are not covered by any suite.
