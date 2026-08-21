#!/usr/bin/env bash
# session-facts.sh — a universal minimum of facts about a project.
#
# Called by the /handoff and /resume skills when the project has NO
# scripts/session-snapshot.sh of its own. It lives next to the skills, not in the
# project, and that is deliberate: the skills treat a project snapshot as the source
# of truth and do not re-check by hand what it printed. This script does not earn that
# status and says so at the end of its output: it knows only git and which bookkeeping
# files exist.
#
#   session-facts.sh              facts about the current repository
#   session-facts.sh --root DIR   explicit root instead of the git root
set -euo pipefail

ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:-}"; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "session-facts: not a git repository and --root not given." >&2
        exit 1
    }
fi

# readlink -f, not echo: the dir may be a symlink, and git refuses paths that live
# beyond one ("beyond a symbolic link"). SESSION_DOCS_DIR / SESSION_SCRIPTS_DIR name a
# nested layout (e.g. "sub/docs") when a project keeps one; unset = plain docs/, scripts/.
pick() { for d in "$@"; do [ -d "$d" ] && { readlink -f "$d"; return 0; }; done; echo "$1"; }
DOCS=$(pick "$ROOT/docs" ${SESSION_DOCS_DIR:+"$ROOT/$SESSION_DOCS_DIR"})
SCRIPTS=$(pick "$ROOT/scripts" ${SESSION_SCRIPTS_DIR:+"$ROOT/$SESSION_SCRIPTS_DIR"})
g() { git -C "$ROOT" "$@"; }

echo "ROOT   $ROOT"
echo "BRANCH $(g branch --show-current 2>/dev/null || echo '<detached>')"
echo "HEAD   $(g log -1 --format='%h %s' 2>/dev/null || echo '<empty>')"

if UPSTREAM=$(g rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then
    AHEAD=$(g rev-list --count "@{upstream}..HEAD" 2>/dev/null || echo 0)
    BEHIND=$(g rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)
    echo "SYNC   upstream $UPSTREAM — ahead $AHEAD, behind $BEHIND"
else
    echo "SYNC   no upstream set (local repository)"
fi

DIRTY=$(g status --short | wc -l)
echo "DIRTY  $DIRTY"
if [ "$DIRTY" -gt 0 ]; then
    g status --short | head -20 | sed 's/^/       /'
    [ "$DIRTY" -gt 20 ] && echo "       … and $((DIRTY - 20)) more"
fi

echo "RECENT"
g log --oneline -10 2>/dev/null | sed 's/^/       /' || echo "       <no commits>"

echo "BOOKS"
for f in "$ROOT/SESSION_HANDOFF.md" "$ROOT/CHRONICLE.md" \
         "$DOCS/PENDING_LEDGER.md" "$DOCS/PROJECT_STATE.md" "$DOCS/BACKLOG.md"; do
    if [ -e "$f" ]; then printf '       yes  %s\n' "${f#"$ROOT"/}"
    else                 printf '       no   %s\n' "${f#"$ROOT"/}"; fi
done

if [ -e "$DOCS/PENDING_LEDGER.md" ]; then
    OPEN=$(grep -cE '^- \[ \]' "$DOCS/PENDING_LEDGER.md" || true)
    CLOSED=$(grep -cE '^- \[x\]' "$DOCS/PENDING_LEDGER.md" || true)
    echo "LEDGER open $OPEN, closed $CLOSED"
fi
if [ -e "$ROOT/CHRONICLE.md" ]; then
    ENTRIES=$(grep -cE '^- \*\*[0-9]{4}-' "$ROOT/CHRONICLE.md" || true)
    echo "CHRON  entries in canonical format: $ENTRIES"
    # Zero entries in a non-empty file is the silent breakage: /handoff will prepend a
    # canonical line, /resume will read only it and silently skip the whole history.
    if [ "$ENTRIES" = 0 ] && [ -s "$ROOT/CHRONICLE.md" ]; then
        echo "       ⚠ file is non-empty but has no canonical-format entries —"
        echo "         do not append until the format matches the contract"
    fi
fi

echo "SCOPE  only git and which bookkeeping files exist."
echo "       Live facts about services, disks and derived artifacts are NOT here:"
echo "       those come from $SCRIPTS/session-snapshot.sh, if the project set one up."
