#!/usr/bin/env bash
# session-facts.sh — a universal minimum of facts about a project.
#
# Called by the /handoff, /pickup, /hygiene and /sweep skills when the project has NO
# scripts/session-snapshot.sh of its own. It lives next to the skills, not in the
# project, and that is deliberate: the skills treat a project snapshot as the source
# of truth and do not re-check by hand what it printed. This script does not earn that
# status and says so at the end of its output: it knows only git and which bookkeeping
# files exist.
#
#   session-facts.sh              facts about the current repository
#   session-facts.sh --paths      resolved layout as shell assignments, nothing else
#   session-facts.sh --root DIR   explicit root instead of the git root
#
# --paths is the single source of truth for layout resolution: the skills eval it in their
# Step 0 instead of each re-deriving the same paths. It is read-only, exits 0
# even when every optional file is missing (absence is the normal case, not a failure),
# and on a hard error prints an evaluable SESSION_FACTS_ERROR instead of nothing.
set -euo pipefail

ROOT=""
PATHS_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --paths) PATHS_ONLY=1 ;;
        --root)
            ROOT="${2:-}"
            [ -n "$ROOT" ] || { echo "--root needs a directory" >&2; exit 2; }
            shift ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

fail() {
    if [ "$PATHS_ONLY" = 1 ]; then printf 'SESSION_FACTS_ERROR=%q\n' "$1"; fi
    echo "session-facts: $1" >&2
    exit 1
}

if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
        || fail "not a git repository and --root not given."
fi
[ -d "$ROOT" ] || fail "no such directory $ROOT"
# readlink -f, not echo: the dir may be a symlink, and git refuses paths that live
# beyond one ("beyond a symbolic link"). It also makes the ROOT/MAIN comparison below
# meaningful — the same worktree reached by two paths must compare equal.
ROOT=$(readlink -f "$ROOT")

# --- worktree ---------------------------------------------------------------
# `git worktree list` prints the MAIN worktree first, always; that holds whatever the
# .git layout is (a linked worktree's .git is a file, a submodule's is elsewhere), which
# is why it beats parsing --git-common-dir. Not a git repo under --root -> MAIN = ROOT.
# A BARE main repository is listed the same way, with a `bare` line in its record: it has no
# working tree, so it can hold no bookkeeping and must not become MAIN. Note that
# `rev-parse --is-bare-repository` reads FALSE from inside the linked worktree — the porcelain
# `bare` line is the only usable signal. Records are blank-line separated; take the first.
WT_FIRST=$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk 'NF==0{exit} {print}' || true)
MAIN=$(printf '%s\n' "$WT_FIRST" | sed -n '1s/^worktree //p')
if printf '%s\n' "$WT_FIRST" | grep -qx bare; then MAIN=""; fi
if [ -n "$MAIN" ] && [ -d "$MAIN" ]; then MAIN=$(readlink -f "$MAIN"); else MAIN="$ROOT"; fi

# --- where the bookkeeping actually lives -----------------------------------
# A linked worktree checks out tracked files only. Bookkeeping that is tracked travels
# with it and nothing special happens. Bookkeeping kept out of git (ignored or excluded, the
# usual choice for maintainer notes) exists ONLY in the main worktree — and a skill that
# resolved against the worktree root would report "this project keeps no handoff" and
# offer to create a second, competing set of files.
BOOKS="$ROOT"
BOOKS_SOURCE=worktree
BOOKS_WRITE=direct
if [ "$MAIN" != "$ROOT" ] \
   && [ ! -e "$ROOT/SESSION_HANDOFF.md" ] && [ ! -e "$ROOT/CHRONICLE.md" ] \
   && { [ -e "$MAIN/SESSION_HANDOFF.md" ] || [ -e "$MAIN/CHRONICLE.md" ]; }; then
    BOOKS="$MAIN"
    BOOKS_SOURCE=main-worktree
fi

# SESSION_DOCS_DIR / SESSION_SCRIPTS_DIR name a nested layout (e.g. "sub/docs") when a
# project keeps one; unset = plain docs/, scripts/. The plain layout always wins.
pick() { for d in "$@"; do [ -d "$d" ] && { readlink -f "$d"; return 0; }; done; echo "$1"; }
DOCS=$(pick "$BOOKS/docs" ${SESSION_DOCS_DIR:+"$BOOKS/$SESSION_DOCS_DIR"})
# The snapshot is code: it is tracked and travels with the checkout, so it resolves
# against ROOT — its job is the live state of the worktree you are actually in. Only if
# there is none here do we fall back to the main worktree's.
SCRIPTS=$(pick "$ROOT/scripts" ${SESSION_SCRIPTS_DIR:+"$ROOT/$SESSION_SCRIPTS_DIR"})
if [ ! -x "$SCRIPTS/session-snapshot.sh" ] && [ "$BOOKS" != "$ROOT" ]; then
    ALT=$(pick "$BOOKS/scripts" ${SESSION_SCRIPTS_DIR:+"$BOOKS/$SESSION_SCRIPTS_DIR"})
    if [ -x "$ALT/session-snapshot.sh" ]; then SCRIPTS="$ALT"; fi
fi

# The two /sweep files split along the same line as everything above: the coverage map is
# bookkeeping, written by a skill, so it follows BOOKS via DOCS; the detector script is the
# project's own code like session-snapshot.sh, so it travels with the checkout via SCRIPTS.
SWEEPMAP="$DOCS/SWEEP_MAP.md"
SWEEPTOOLS="$SCRIPTS/sweep-tools.sh"

# Reading from the main worktree is always safe. WRITING is not: if the books are tracked
# there, writing dirties a checkout that may be mid-work on another branch. Untracked ->
# writing changes nothing git can see, and there is nothing to commit. Every file a skill may
# write is checked, not just the two root ones: a project can keep the handoff local and the
# ledger tracked, and then a two-file check would report "untracked" and dirty the ledger
# anyway. Conservative: ANY tracked file is enough to require asking the operator.
if [ "$BOOKS_SOURCE" = main-worktree ]; then
    BOOKS_WRITE=fallback-untracked
    for f in "$BOOKS/SESSION_HANDOFF.md" "$BOOKS/CHRONICLE.md" \
             "$DOCS/PENDING_LEDGER.md" "$DOCS/PROJECT_STATE.md" "$DOCS/BACKLOG.md" \
             "$SWEEPMAP"; do
        if git -C "$MAIN" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
            BOOKS_WRITE=fallback-tracked
            break
        fi
    done
fi

have() { if [ -e "$1" ]; then echo yes; else echo no; fi; }
HAVE_HANDOFF=$(have "$BOOKS/SESSION_HANDOFF.md")
HAVE_CHRONICLE=$(have "$BOOKS/CHRONICLE.md")
HAVE_LEDGER=$(have "$DOCS/PENDING_LEDGER.md")
HAVE_STATE=$(have "$DOCS/PROJECT_STATE.md")
HAVE_BACKLOG=$(have "$DOCS/BACKLOG.md")
HAVE_SWEEPMAP=$(have "$SWEEPMAP")
HAVE_SNAPSHOT=$(have "$SCRIPTS/session-snapshot.sh")
HAVE_SWEEPTOOLS=$(have "$SWEEPTOOLS")

if [ "$PATHS_ONLY" = 1 ]; then
    printf 'ROOT=%q\n'            "$ROOT"
    printf 'MAIN=%q\n'            "$MAIN"
    printf 'BOOKS=%q\n'           "$BOOKS"
    printf 'DOCS=%q\n'            "$DOCS"
    printf 'SCRIPTS=%q\n'         "$SCRIPTS"
    printf 'SWEEPMAP=%q\n'        "$SWEEPMAP"
    printf 'SWEEPTOOLS=%q\n'      "$SWEEPTOOLS"
    printf 'BOOKS_SOURCE=%q\n'    "$BOOKS_SOURCE"
    printf 'BOOKS_WRITE=%q\n'     "$BOOKS_WRITE"
    printf 'HAVE_HANDOFF=%q\n'    "$HAVE_HANDOFF"
    printf 'HAVE_CHRONICLE=%q\n'  "$HAVE_CHRONICLE"
    printf 'HAVE_LEDGER=%q\n'     "$HAVE_LEDGER"
    printf 'HAVE_STATE=%q\n'      "$HAVE_STATE"
    printf 'HAVE_BACKLOG=%q\n'    "$HAVE_BACKLOG"
    printf 'HAVE_SWEEPMAP=%q\n'   "$HAVE_SWEEPMAP"
    printf 'HAVE_SNAPSHOT=%q\n'   "$HAVE_SNAPSHOT"
    printf 'HAVE_SWEEPTOOLS=%q\n' "$HAVE_SWEEPTOOLS"
    exit 0
fi

g() { git -C "$ROOT" "$@"; }

echo "ROOT   $ROOT"
# --show-current exits 0 with EMPTY output on a detached HEAD, so `|| echo` never fires;
# a detached HEAD is the common case in a worktree, which is where this matters.
BRANCH=$(g branch --show-current 2>/dev/null || true)
[ -n "$BRANCH" ] || BRANCH="<detached at $(g rev-parse --short HEAD 2>/dev/null || echo '<empty>')>"
echo "BRANCH $BRANCH"
echo "HEAD   $(g log -1 --format='%h %s' 2>/dev/null || echo '<empty>')"

if [ "$MAIN" != "$ROOT" ]; then
    echo "WTREE  linked worktree; main worktree is $MAIN"
fi

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

echo "BOOKS  in $BOOKS ($BOOKS_SOURCE)"
printf '       %-4s %s\n' \
    "$HAVE_HANDOFF"   "SESSION_HANDOFF.md" \
    "$HAVE_CHRONICLE" "CHRONICLE.md" \
    "$HAVE_LEDGER"    "${DOCS#"$BOOKS"/}/PENDING_LEDGER.md" \
    "$HAVE_STATE"     "${DOCS#"$BOOKS"/}/PROJECT_STATE.md" \
    "$HAVE_BACKLOG"   "${DOCS#"$BOOKS"/}/BACKLOG.md" \
    "$HAVE_SWEEPMAP"  "${DOCS#"$BOOKS"/}/SWEEP_MAP.md"
if [ "$BOOKS_SOURCE" = main-worktree ]; then
    echo "       ⚠ the bookkeeping is NOT in this worktree — it lives in the main one."
    if [ "$BOOKS_WRITE" = fallback-tracked ]; then
        echo "         Those files are TRACKED there: writing dirties a checkout that may"
        echo "         be mid-work. Read freely; ask the operator before /handoff writes."
    else
        echo "         Untracked there, so writing is safe and commits nothing."
    fi
fi

# Reported on its own line, not among the books: it is project code and can sit outside BOOKS
# entirely, so it is shown against the worktree it actually belongs to.
SWEEPREL=${SWEEPTOOLS#"$ROOT"/}; SWEEPREL=${SWEEPREL#"$MAIN"/}
printf 'SWEEP  %-4s %s\n' "$HAVE_SWEEPTOOLS" "$SWEEPREL"

if [ "$HAVE_LEDGER" = yes ]; then
    OPEN=$(grep -cE '^- \[ \]' "$DOCS/PENDING_LEDGER.md" || true)
    CLOSED=$(grep -cE '^- \[x\]' "$DOCS/PENDING_LEDGER.md" || true)
    echo "LEDGER open $OPEN, closed $CLOSED"
fi
if [ "$HAVE_CHRONICLE" = yes ]; then
    ENTRIES=$(grep -cE '^- \*\*[0-9]{4}-' "$BOOKS/CHRONICLE.md" || true)
    echo "CHRON  entries in canonical format: $ENTRIES"
    # Zero entries in a non-empty file is the silent breakage: /handoff will prepend a
    # canonical line, /pickup will read only it and silently skip the whole history.
    if [ "$ENTRIES" = 0 ] && [ -s "$BOOKS/CHRONICLE.md" ]; then
        echo "       ⚠ file is non-empty but has no canonical-format entries —"
        echo "         do not append until the format matches the contract"
    fi
fi

echo "SCOPE  only git and which bookkeeping files exist."
echo "       Live facts about services, disks and derived artifacts are NOT here:"
echo "       those come from $SCRIPTS/session-snapshot.sh, if the project set one up."
