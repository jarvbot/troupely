#!/usr/bin/env python3
"""Seed Claude Code's first-run flags so a persona boots straight into its channel session.

Without these, a fresh vault blocks on the interactive onboarding wizard (theme → API-key
prompt → trust-folder → tour), which exits on completion rather than continuing. Two files:
  <vault>/.claude.json           onboarding complete, provider-key approval, per-dir trust
  <vault>/.claude/settings.json  skipDangerousModePermissionPrompt (the bypass-permissions
                                 accept prompt lives here, not in .claude.json)
Idempotent and non-destructive: merges into existing config.

usage: seed_onboarding.py <vault-dir> [persona-dir ...]
       Trusts the vault root, every dir under <vault>/personas/, and any extra dirs given.
       ANTHROPIC_API_KEY, if set in the environment, is pre-approved.
"""
import json
import os
import sys


def load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save(p, d):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2)
    os.replace(tmp, p)


def main(vault, extra):
    cj_path = os.path.join(vault, ".claude.json")
    cj = load(cj_path)
    cj["hasCompletedOnboarding"] = True
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if api_key:  # pre-approve the key so claude doesn't ask "use this key?" (stores the suffix)
        cr = cj.setdefault("customApiKeyResponses", {"approved": [], "rejected": []})
        if api_key[-20:] not in cr.setdefault("approved", []):
            cr["approved"].append(api_key[-20:])
    projects = cj.setdefault("projects", {})

    def trust(p):
        proj = projects.setdefault(p, {})
        proj["hasTrustDialogAccepted"] = True
        proj["hasCompletedProjectOnboarding"] = True
        # Persona CLAUDE.md files @-import ../../CLAUDE.md, outside their own dir, which
        # triggers "allow external CLAUDE.md imports". The standard layout always does this.
        proj["hasClaudeMdExternalIncludesApproved"] = True
        proj["hasClaudeMdExternalIncludesWarningShown"] = True

    trust(vault)
    root = os.path.join(vault, "personas")
    if os.path.isdir(root):
        for name in sorted(os.listdir(root)):
            if os.path.isdir(os.path.join(root, name)):
                trust(os.path.join(root, name))
    for p in extra:
        trust(p)
    save(cj_path, cj)

    st_path = os.path.join(vault, ".claude", "settings.json")
    st = load(st_path)
    st["skipDangerousModePermissionPrompt"] = True
    save(st_path, st)
    print("  ✓ seeded claude onboarding flags (.claude.json + settings.json)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: seed_onboarding.py <vault-dir> [persona-dir ...]", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2:])
