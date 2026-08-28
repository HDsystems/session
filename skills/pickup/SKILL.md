---
name: pickup
description: Reorient at the start of a fresh session — reads SESSION_HANDOFF, PROJECT_STATE invariants, the CHRONICLE tail and open PENDING_LEDGER items, and surfaces where you left off / what is live / pending / do-not-touch / first step in 5-10 lines. Works in any git repository and in a linked worktree: paths resolve through `session-facts.sh --paths`, which finds the books in the main worktree when the worktree has none, and optional pieces (snapshot script, ledger, project state) activate only when present. Live facts come from the project's snapshot script when it has one, never hand-gathered. Use after /clear or at the start of any session in a project that keeps a handoff. Missing structure -> `~/.claude/bin/session-init.sh`.
---

# Pickup — 30-second reorientation

## Goal
- Operator learns where you left off / what is live / what is pending / what not to touch / first step
- Without reading 500 lines, and without you re-deriving facts a script already produces

## Step 0: Resolve project
```bash
FACTS="${CLAUDE_HOME:-$HOME/.claude}/bin/session-facts.sh"
eval "$("$FACTS" --paths)"   # ROOT MAIN BOOKS DOCS SCRIPTS BOOKS_SOURCE BOOKS_WRITE HAVE_*
[ -n "${ROOT:-}" ] || { echo "layout unresolved: ${SESSION_FACTS_ERROR:-$FACTS missing — reinstall}"; exit 1; }
echo "BOOKS $BOOKS ($BOOKS_SOURCE, write:$BOOKS_WRITE)"
echo "handoff=$HAVE_HANDOFF chronicle=$HAVE_CHRONICLE ledger=$HAVE_LEDGER \
state=$HAVE_STATE backlog=$HAVE_BACKLOG snapshot=$HAVE_SNAPSHOT"
```
- ONE call and it EXITS 0 even when every optional file is missing: absence is the normal,
  documented case, never a failure. Do NOT probe with `ls` — it exits 2 on the first missing
  path, which turns a healthy project into "failed to resolve the layout"
- `--paths` is the single source of truth for the layout: search order, `SESSION_DOCS_DIR` /
  `SESSION_SCRIPTS_DIR`, symlink resolution and the worktree rule live there, not here
- Bookkeeping lives under `$BOOKS`, NOT `$ROOT` — in a linked worktree the two differ, and
  `$DOCS` is already resolved against `$BOOKS`. A worktree checks out TRACKED files only, so
  books kept local (`.git/info/exclude`) exist in the main worktree alone
- `BOOKS_SOURCE=main-worktree` -> you are in a worktree and the books live in `$MAIN`; say so
  in one line, so the operator knows which files were read
- `HAVE_HANDOFF=no` AND `HAVE_CHRONICLE=no` -> project keeps no handoff: say so, run
  `~/.claude/bin/session-init.sh --dry-run`, offer it, then orient from `git log` and `README`
- Every other file is OPTIONAL: `no` -> its line is omitted, not faked

## Step 1: Facts, one call
- `$SCRIPTS/session-snapshot.sh` exists -> run it; it is the SSOT of live facts, and you do
  NOT re-run `git`/`df` and whatever else it covers by hand afterwards
- Absent -> `~/.claude/bin/session-facts.sh` — git plus the state of the bookkeeping files.
  It is NOT an SSOT and says so: no service, disk or derived-artifact facts in it
- Either way it is ONE call. Do not hand-gather what the output already contains
- Do NOT re-check what the output printed — except an item it marked `⚠`, then verify that one
- The snapshot is also where a project keeps its own checks; writing one is the "Authoring
  contract" in this repo's README (it replaces the fallback, fails soft, flags with `⚠`)

## Step 2: Read context (parallel, slim)
- `$BOOKS/SESSION_HANDOFF.md` — in full; it is already slim
- `$DOCS/PROJECT_STATE.md` — in full; invariants, do-not-touch, environment quirks
- `$BOOKS/CHRONICLE.md` — last 30 ENTRIES, headers only
- `$DOCS/PENDING_LEDGER.md` — ALL open `- [ ]`, headers only
- Read them by their RESOLVED path: `$BOOKS`/`$DOCS`, never a bare relative name — invoked
  from a subdirectory or a worktree the bare name silently matches nothing
```bash
grep -E '^- \*\*[0-9]{4}-' "$BOOKS/CHRONICLE.md" | head -30 | LC_ALL=C.UTF-8 sed -E 's/^(.{280}).*/\1 …/'
grep -E '^- \[ \]' "$DOCS/PENDING_LEDGER.md" | LC_ALL=C.UTF-8 sed -E 's/^(.{220}).*/\1 …/'
```
- Never `head` these two files: an entry is a paragraph, so line counts lie and the read truncates
- Cut the LENGTH of an item, never the NUMBER of them: open items are the priority tail, a sample drops real defects
- `cut -c` is BYTE-based here and splits multibyte text mid-character — use `LC_ALL=C.UTF-8 sed`, not `cut`
- Body of an entry -> targeted `grep` by date or id, only once its header proved relevant
- Do NOT read: `archives/*`, all of `BACKLOG.md` (one card by reference), all of `CHRONICLE.md`

## Step 3: Synthesize (5–10 lines, under 25)
```
## Where you left off
Last: `<HEAD sha + subject>` — <one line from the handoff lede>

## Live now
<from the snapshot, if the project has one; omit the section entirely if it does not>

## ⚠ Health / Disks
<only if the snapshot flagged ⚠>

## Pending — priority
1-2. <from handoff "What was NOT done" + open ledger items missing from it>

## ⚠ Do not touch
<1-2 most relevant from PROJECT_STATE — reference the file, do not copy the list>

## Suggested first action
<from handoff "Next session start", or the explicit first command>
```

## Step 4: Stand by
- Do NOT act. Wait for the operator
- Prompt contained more than the invocation ("…and continue X") -> orient first, then do X

## Don't
- Do NOT `/clear`, commit, push or rebuild — this is orient-only
- Do NOT rewrite `SESSION_HANDOFF.md` — that is `/handoff`
- Do NOT run heavy tests or network probes — local snapshot only
