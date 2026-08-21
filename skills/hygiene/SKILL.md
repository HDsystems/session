---
name: hygiene
description: Periodic deep-clean of project bookkeeping — BACKLOG card status-drift audit, documentation-sync with recent commits, PENDING_LEDGER prune of old closed items, and disk reclaim when the project ships a prune script. Works in any git repository: every step activates only when the file or script it needs is present. Run weekly, or when /handoff nags about closed ledger items past the archive window, or when a snapshot flags a ⚠ disk. This is the heavy hygiene deliberately split OUT of the every-session /handoff so the daily handoff stays light.
---

# Hygiene — periodic deep-clean

## When
- Weekly, or on a nag from `/handoff` or the project's snapshot script
- NOT every session: that is why it is split out of `/handoff`

## Step 0: Resolve project and scope
```bash
ROOT=$(git rev-parse --show-toplevel) || { echo "not a git repo"; exit 1; }
# readlink -f, not echo: the dir may be a symlink, and git refuses paths that live
# beyond one ("beyond a symbolic link"). SESSION_DOCS_DIR / SESSION_SCRIPTS_DIR name a
# nested layout (e.g. "sub/docs") when a project keeps one; unset = plain docs/, scripts/.
pick() { for d in "$@"; do [ -d "$d" ] && { readlink -f "$d"; return 0; }; done; echo "$1"; }
DOCS=$(pick "$ROOT/docs" ${SESSION_DOCS_DIR:+"$ROOT/$SESSION_DOCS_DIR"})
SCRIPTS=$(pick "$ROOT/scripts" ${SESSION_SCRIPTS_DIR:+"$ROOT/$SESSION_SCRIPTS_DIR"})
git -C "$ROOT" log --since='7 days ago' --oneline
git -C "$ROOT" diff --stat "$(git -C "$ROOT" rev-list -1 --before='7 days ago' HEAD)" HEAD
```
- Each step below needs a specific file or script: absent -> skip it with one line of output
- Nothing present at all -> project keeps no bookkeeping; offer `~/.claude/bin/session-init.sh` and stop

## Step 1: BACKLOG status-drift audit — needs `$DOCS/BACKLOG.md`
- Markers lag reality: work gets done and nobody flips the status
- From recent commits and `CHRONICLE.md`, list the cards actually worked on
- Open BOTH places per card: the slim index line, and the card file's `## Status`
- Do NOT trust the marker — verify against `git log`, `CHRONICLE`, and ground truth (shipped? verified?)
- Fully done -> close in BOTH (index: state + date + commit; `## Status`: detail)
- Partially done -> update that sub-item only, never mark the whole card shipped
- Targeted edits. Create no new cards — status only

## Step 2: Documentation-sync — needs `$DOCS`
- `ls "$DOCS"` for the actual composition; never hardcode a file list
- From `git diff --stat` over the period, pick the areas touched
- `grep -lR "<keyword>" "$DOCS"` per area -> candidates
- Classify each: needs-update / already-accurate / out-of-scope. Minimal targeted edits, no rewrites
- Stale for reasons OUTSIDE this period -> record as debt in the handoff, do not silently fix
- `/freeze` or a "don't touch the docs" instruction -> skip, mention in one line
- Create no new `*.md` without asking

## Step 3: Prune `PENDING_LEDGER` — needs `$SCRIPTS/prune_pending_ledger.py`
```bash
python3 "$SCRIPTS/prune_pending_ledger.py" --dry-run   # what would move
python3 "$SCRIPTS/prune_pending_ledger.py"             # apply (default 3d; --days N)
```
- Moves closed `[x]` older than N days to an archive; asserts the open count is unchanged
- Script absent -> skip. Do NOT prune by hand: bulk-rewriting the ledger is how open items disappear
- "nothing to prune" -> no-op

## Step 4: Disk reclaim — needs `$SCRIPTS/prune_home_caches.sh`
```bash
"$SCRIPTS/prune_home_caches.sh"            # plan
"$SCRIPTS/prune_home_caches.sh" --apply    # delete
```
- ALWAYS dry-run first, show the plan, `--apply` only after an explicit "go"
- Do NOT delete tool versions by hand and do NOT "simplify" the script to "keep the newest":
  a live session runs its OWN binary under `versions/<v>`, often not the one the symlink points at.
  Deleting it does not kill the current process (open inode) but breaks spawning subagents with an
  ENOENT far from the cause
- Scratchpads are cut by AGE, not by liveness, and at session level, not project level
- Some scratchpad files belong to root (a container wrote them): a user `rm -rf` guts the tree and
  reports success. The script marks those `SUDO`, excludes them, and prints the command — the
  operator runs it, the script never calls sudo
- Transcripts and history are not caches: not touched without an explicit opt-in
- This step produces no git changes — its result goes in the report, not the commit

## Step 5: Commit
- Show `git diff` of touched bookkeeping files read-only
- Stage ONLY those; foreign dirty files -> flag and ask
```
docs: hygiene — <what was audited: cards / docs / prune result>

<1-3 line summary>
```
- Trailers (`Co-Authored-By`, `Claude-Session`) come from the current session prompt — never hardcode here
- `git status --short` -> confirm clean-in-scope

## Don't
- Do NOT `git push` or `/clear` yourself
- Do NOT create new cards or docs without asking
- Do NOT bulk-rewrite `PENDING_LEDGER` — only its prune script
- Do NOT clean disk by hand — only the project's prune script, except the `sudo` lines it printed
- Do NOT duplicate `/handoff` work (lede / what-shipped / ledger append / CHRONICLE) — that is its zone
- Do NOT edit `CLAUDE.md`
