#!/usr/bin/env bash
# session-init.sh — create the project bookkeeping structure if it does not exist.
#
# Called by the /handoff, /resume, /hygiene skills when they find nowhere to write.
# Idempotent: existing files are NEVER touched, only missing ones are created.
#
#   session-init.sh                  create what is missing
#   session-init.sh --dry-run        show the plan, write nothing
#   session-init.sh --minimal        only SESSION_HANDOFF.md and CHRONICLE.md
#   session-init.sh --with-backlog   plus BACKLOG.md and a card directory
#   session-init.sh --root DIR       explicit root instead of the git root
#
# Layout (search order is fixed, not guessed):
#   <root>/SESSION_HANDOFF.md   CHRONICLE.md
#   <root>/{docs|$SESSION_DOCS_DIR}/PENDING_LEDGER.md   PROJECT_STATE.md
#
# What is NOT created by default and why:
#   BACKLOG.md — not a file but a subsystem: an index plus a directory of cards (a large
#     project may have hundreds). It pays off when an item lives across many sessions and
#     grows a history of its own; a short tail is covered by PENDING_LEDGER. Pass
#     --with-backlog when you want it.
#   scripts/session-snapshot.sh — the live-facts collector, project-specific by nature (for a
#     containerized project it is services, health, disk). The skills treat it as the SOURCE
#     OF TRUTH and do not re-check by hand what it printed. A stub that knows only git would
#     inherit that status over facts it does not collect. Write it per project by hand; until
#     it exists, the skills gather the minimum themselves.
set -euo pipefail

DRY_RUN=0
MINIMAL=0
WITH_BACKLOG=0
ROOT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --minimal) MINIMAL=1 ;;
        --with-backlog) WITH_BACKLOG=1 ;;
        --root)    ROOT="${2:-}"; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$ROOT" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "session-init: not a git repository and --root not given." >&2
        echo "  Bookkeeping is anchored to the repo root: without it the next session" >&2
        echo "  cannot find the files. Run git init or pass --root DIR." >&2
        exit 1
    }
fi
[ -d "$ROOT" ] || { echo "session-init: no such directory $ROOT" >&2; exit 1; }

# Existing layout wins, plain docs/ preferred. readlink -f, not echo: the dir may be a
# symlink, and git refuses paths beyond one ("beyond a symbolic link"). SESSION_DOCS_DIR
# names a nested layout (e.g. "sub/docs"); unset = plain docs/. On a fresh repo where neither
# exists, create under the declared SESSION_DOCS_DIR when set, so init honors the layout.
pick() { for d in "$@"; do [ -d "$d" ] && { readlink -f "$d"; return 0; }; done; echo ""; }
DOCS=$(pick "$ROOT/docs" ${SESSION_DOCS_DIR:+"$ROOT/$SESSION_DOCS_DIR"})
[ -n "$DOCS" ] || DOCS="$ROOT/${SESSION_DOCS_DIR:-docs}"

TODAY=$(date +%Y-%m-%d)
CREATED=0
SKIPPED=0

plan() { printf '  %-8s %s\n' "$1" "${2#"$ROOT"/}"; }

# create <path> <<<content — writes only if the file does not exist.
create() {
    local path="$1"
    if [ -e "$path" ]; then
        plan "exists" "$path"; SKIPPED=$((SKIPPED + 1)); cat >/dev/null; return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        plan "create" "$path"; CREATED=$((CREATED + 1)); cat >/dev/null; return 0
    fi
    mkdir -p "$(dirname "$path")"
    cat >"$path"
    plan "created" "$path"; CREATED=$((CREATED + 1))
}

echo "session-init: root $ROOT"
[ "$DRY_RUN" = 1 ] && echo "  (dry-run: nothing is written)"

create "$ROOT/CHRONICLE.md" <<EOF
# CHRONICLE — $(basename "$ROOT")

Project chronicle: what changed and when, substantively. **Append-only**: entries are
prepended and never rewritten. Current state lives in \`SESSION_HANDOFF.md\`, which is derived
and rewritten each session; here is the history that does not get lost.

Entry format (the skills' tail reading depends on it — do not change):

\`- **YYYY-MM-DD**: [Type] in <area>. Description: <2-6 sentences>. Status: Success|Pending|Failed|Reverted.\`

Type: Feature | Bugfix | Refactor | Infra | Security | Docs | Engineering Quality | Engineering QA | Migration

---

- **$TODAY**: [Docs] in \`$(basename "$ROOT")\`. Description: project bookkeeping initialized — CHRONICLE, SESSION_HANDOFF$([ "$MINIMAL" = 1 ] || echo ", PENDING_LEDGER, PROJECT_STATE"). Status: Success.
EOF

create "$ROOT/SESSION_HANDOFF.md" <<EOF
# SESSION_HANDOFF — $TODAY (bookkeeping initialized)

> A stub created by \`session-init.sh\`. The first \`/handoff\` rewrites it entirely: this file
> is derived; the source of truth is \`CHRONICLE.md\` (history) and \`PENDING_LEDGER.md\` (tail).

## Commits this session

<filled in by \`/handoff\`>

## What was done

<filled in by \`/handoff\`>

## What was NOT done — priority

### Top-1: describe the project state

What the project does, what already works, what is open. Until the first \`/handoff\` the next
session learns about the project only from the code.

## Next session start

1. Read this file. 2. \`/resume\`. 3. Estimate Effort before starting.

## Key files

<paths grouped by area>
EOF

if [ "$MINIMAL" = 0 ]; then
    create "$DOCS/PENDING_LEDGER.md" <<EOF
# PENDING LEDGER — open planned items (append-only)

A safety journal of tasks that were **planned in a session but did not reach the end**.
It exists because \`SESSION_HANDOFF.md\` is rewritten entirely: an item from the
"What was NOT done" section may not survive the next handoff generation. This file is not
rewritten, so an item physically cannot be lost here.

## Contract (obeyed by \`/handoff\` and \`/resume\`)

- **Append + single-line edits only.** The file is never rewritten as a whole.
- \`/handoff\` at the end of a session: each "What was NOT done" item not already open is
  appended as \`- [ ]\` under today's date. Nothing is deleted.
- Closing an item — mark the line \`[x]\` and the close date. One-line edit, not a bulk one.
- \`/resume\` at the start of a session reads ALL open \`[ ]\` — that is the priority tail.
- Long-lived item (2+ sessions) -> a card in \`BACKLOG.md\`; the line here closes with a reference.

---

## $TODAY

- [ ] ($TODAY) Describe the project state in SESSION_HANDOFF
EOF

    create "$DOCS/PROJECT_STATE.md" <<EOF
# PROJECT_STATE — project invariants

Stable facts that do NOT change from session to session: what not to touch, what safety
switches exist, how the project differs from expectations. \`SESSION_HANDOFF.md\` references
this file and does NOT duplicate it.

Edited surgically and only when an invariant has actually changed.

## Do not touch

<files, directories and settings whose change breaks the project in non-obvious ways>

## Safety switches

<flags, kill-switches, modes turned off on purpose>

## Environment quirks

<versions, paths, permissions — anything a fresh session trips over>
EOF
fi

if [ "$WITH_BACKLOG" = 1 ]; then
    create "$DOCS/BACKLOG.md" <<EOF
# BACKLOG — long-lived initiatives

A slim index of cards. One line per card, detail in \`BACKLOG/<slug>.md\`.
This is NOT a duplicate of \`PENDING_LEDGER.md\`: the ledger is the short-lived session tail,
here is what lives across many sessions and has a history of its own.

The index line and the card's \`## Status\` are edited TOGETHER: a mismatch between them is
the main job of \`/hygiene\` Step 1.

| Card | State | Summary |
|---|---|---|
EOF
    if [ "$DRY_RUN" = 1 ]; then
        plan "create" "$DOCS/BACKLOG/"
    elif [ ! -d "$DOCS/BACKLOG" ]; then
        mkdir -p "$DOCS/BACKLOG"; plan "created" "$DOCS/BACKLOG/"
    else
        plan "exists" "$DOCS/BACKLOG/"
    fi
fi

echo
if [ "$DRY_RUN" = 1 ]; then
    echo "session-init: plan — create $CREATED, already present $SKIPPED. Run without --dry-run."
else
    echo "session-init: created $CREATED, already present $SKIPPED."
    [ "$CREATED" -gt 0 ] && echo "  Files are not committed — /handoff does that with the rest."
fi
exit 0
