#!/usr/bin/env bash
# install.sh — connect this repository's skills and scripts to Claude Code.
#
# By default it links SYMLINKS from ~/.claude into the clone: `git pull` updates the
# skills immediately, with no copying and no version drift.
#
#   install.sh              symlinks (default)
#   install.sh --copy       copies instead of symlinks
#   install.sh --force      overwrite what is already there
#   install.sh --dry-run    show the plan, change nothing
#   install.sh --uninstall  remove the symlinks installed from here
#
# Existing files are NOT overwritten without --force: you may have your own skills
# with the same names, and silently clobbering them is worse than refusing.
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
DEST="${CLAUDE_HOME:-$HOME/.claude}"
MODE=link
FORCE=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --copy)      MODE=copy ;;
        --force)     FORCE=1 ;;
        --dry-run)   DRY_RUN=1 ;;
        --uninstall) MODE=uninstall ;;
        -h|--help)   sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

SKILLS="handoff resume hygiene"
SCRIPTS="session-init.sh session-facts.sh"
DONE=0
SKIPPED=0

say() { printf '  %-10s %s\n' "$1" "${2/#$HOME/~}"; }

# link_one <source> <destination>
link_one() {
    local src="$1" dst="$2"
    if [ "$MODE" = uninstall ]; then
        # Remove only OUR symlinks: a foreign file in that place is left untouched.
        if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
            [ "$DRY_RUN" = 1 ] || rm "$dst"
            say "removed" "$dst"; DONE=$((DONE + 1))
        else
            say "not ours" "$dst"; SKIPPED=$((SKIPPED + 1))
        fi
        return 0
    fi

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
            say "already" "$dst"; SKIPPED=$((SKIPPED + 1)); return 0
        fi
        if [ "$FORCE" = 0 ]; then
            say "occupied" "$dst"
            echo "             ↑ exists and is not ours. --force overwrites"
            SKIPPED=$((SKIPPED + 1)); return 0
        fi
        [ "$DRY_RUN" = 1 ] || rm -rf "$dst"
    fi

    if [ "$DRY_RUN" = 1 ]; then
        say "install" "$dst"; DONE=$((DONE + 1)); return 0
    fi
    mkdir -p "$(dirname "$dst")"
    if [ "$MODE" = copy ]; then cp -r "$src" "$dst"; else ln -s "$src" "$dst"; fi
    say "$([ "$MODE" = copy ] && echo copied || echo linked)" "$dst"
    DONE=$((DONE + 1))
}

echo "install: $SRC -> $DEST  (mode: $MODE)"
[ "$DRY_RUN" = 1 ] && echo "  (dry-run: nothing changes)"

for s in $SKILLS;  do link_one "$SRC/skills/$s" "$DEST/skills/$s"; done
for f in $SCRIPTS; do link_one "$SRC/bin/$f"    "$DEST/bin/$f";    done

echo
if [ "$MODE" = uninstall ]; then
    echo "install: removed $DONE, skipped $SKIPPED."
else
    echo "install: connected $DONE, skipped $SKIPPED."
    if [ "$DRY_RUN" = 0 ] && [ "$DONE" -gt 0 ]; then
        echo "  The skill list is read at startup — restart Claude Code."
        echo "  Check: /resume in any git repository."
    fi
fi
exit 0
