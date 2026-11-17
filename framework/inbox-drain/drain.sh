#!/usr/bin/env bash
# troupely inbox-drain helper — the three-state drain protocol as a CLI.
#
#   inbox/file.md  →  processing/file.md  →  done (deleted, or kept in notes/)
#     pending            work in flight           complete
#
# A persona's inbox lives at <persona-dir>/inbox/ with a sibling <persona-dir>/processing/.
# This helper just does the file moves safely — the *judgment* (accept/clarify/decline, do the
# work) is yours. See README.md in this dir for the full convention.
#
#   drain.sh next <persona-dir>           # print the oldest pending item's path (or nothing)
#   drain.sh claim <persona-dir> <file>   # mv inbox/<file> -> processing/<file>
#   drain.sh done  <persona-dir> <file>   # rm processing/<file>  (work finished)
#   drain.sh keep  <persona-dir> <file>   # mv processing/<file> -> <persona-dir>/notes/
#   drain.sh status <persona-dir>         # counts + any stuck processing/ items
set -euo pipefail

die() { echo "✗ $*" >&2; exit 1; }
sub() { local d="$1" s="$2"; printf '%s/%s' "${d%/}" "$s"; }

cmd="${1:-status}"; shift || true
[ $# -ge 1 ] || die "usage: drain.sh $cmd <persona-dir> [file]"
PDIR="${1%/}"; shift || true
INBOX="$(sub "$PDIR" inbox)"; PROC="$(sub "$PDIR" processing)"; NOTES="$(sub "$PDIR" notes)"

case "$cmd" in
  next)
    mkdir -p "$INBOX"
    # oldest .md that isn't a keepfile/index
    find "$INBOX" -maxdepth 1 -type f -name '*.md' ! -name '.gitkeep' ! -name 'PENDING-INDEX.md' \
      -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2- ;;
  claim)
    [ $# -ge 1 ] || die "usage: drain.sh claim <persona-dir> <file>"
    f="$(basename "$1")"; mkdir -p "$PROC"
    [ -f "$(sub "$INBOX" "$f")" ] || die "no pending item '$f' in $INBOX"
    mv "$(sub "$INBOX" "$f")" "$(sub "$PROC" "$f")"
    echo "claimed → $(sub "$PROC" "$f")" ;;
  done)
    [ $# -ge 1 ] || die "usage: drain.sh done <persona-dir> <file>"
    f="$(basename "$1")"
    [ -f "$(sub "$PROC" "$f")" ] || die "no in-flight item '$f' in $PROC"
    rm -f "$(sub "$PROC" "$f")"; echo "done (removed $f)" ;;
  keep)
    [ $# -ge 1 ] || die "usage: drain.sh keep <persona-dir> <file>"
    f="$(basename "$1")"; mkdir -p "$NOTES"
    [ -f "$(sub "$PROC" "$f")" ] || die "no in-flight item '$f' in $PROC"
    mv "$(sub "$PROC" "$f")" "$(sub "$NOTES" "$f")"; echo "kept → $(sub "$NOTES" "$f")" ;;
  status)
    pend=$(find "$INBOX" -maxdepth 1 -type f -name '*.md' ! -name '.gitkeep' 2>/dev/null | wc -l | tr -d ' ')
    inflight=$(find "$PROC" -maxdepth 1 -type f -name '*.md' ! -name '.gitkeep' ! -name 'PENDING-INDEX.md' 2>/dev/null | wc -l | tr -d ' ')
    echo "pending: $pend  |  in-flight (processing/): $inflight"
    if [ "$inflight" -gt 0 ]; then
      echo "⚠ resume these before draining new items:"
      find "$PROC" -maxdepth 1 -type f -name '*.md' ! -name '.gitkeep' ! -name 'PENDING-INDEX.md' -exec basename {} \;
    fi ;;
  *) die "unknown command '$cmd' (next | claim | done | keep | status)" ;;
esac
