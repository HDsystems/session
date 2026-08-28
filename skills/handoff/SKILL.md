---
name: handoff
description: Prepare a fresh session to resume — writes a SLIM SESSION_HANDOFF.md (lede + what-was-done + next-actions only), appends CHRONICLE entries for shipped changes, syncs the append-only PENDING_LEDGER, and commits. Works in any git repository and in a linked worktree: paths resolve through `session-facts.sh --paths`, which also decides whether writing to the main worktree is safe, and optional pieces (snapshot script, ledger, project state, derived-artifact drift) activate only when present. Facts come from the snapshot script when the project has one. Stable invariants live in PROJECT_STATE.md (referenced, never rewritten). Heavy hygiene is the separate /hygiene skill. Use at end of any non-trivial session before /clear. Missing structure -> `~/.claude/bin/session-init.sh`.
---

# Session Handoff — slim derived view

## Model
- Append-only records are the source of truth: `CHRONICLE.md` = history, `PENDING_LEDGER.md` = pending
- `SESSION_HANDOFF.md` is a DERIVED view (lede + what was done + what is next), rewritten each session
- Stable invariants live in `PROJECT_STATE.md` — REFERENCE it, never re-emit it
- Live facts come from the snapshot script when the project has one, never hand-gathered

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
  books kept OUT of git — ignored or excluded, the usual choice for maintainer notes —
  exist in the main worktree alone
- `BOOKS_WRITE` is the ONLY gate on writing, and it is decided here, once:
  - `direct` — books are in this worktree; proceed normally
  - `fallback-untracked` — books are in `$MAIN` and untracked there: write them, say in one
    line where they went. Nothing is stageable, so Step 9 commits none of them
  - `fallback-tracked` — books are in `$MAIN` AND tracked there: STOP and ask. Writing dirties
    a checkout that may be mid-work on another branch. Offer to re-run `/handoff` from `$MAIN`
- `HAVE_CHRONICLE=no` AND `HAVE_HANDOFF=no` -> this project keeps no bookkeeping yet: bootstrap it (below), do not improvise
- Every other file is OPTIONAL: `no` -> its step is skipped with one output line

## Step 1: Facts, one call
- `$SCRIPTS/session-snapshot.sh` exists -> run it; it is the SSOT of live facts, and you do
  NOT re-run `git`/`df` and whatever else it covers by hand afterwards
- Absent -> `~/.claude/bin/session-facts.sh` — git plus the state of the bookkeeping files.
  It is NOT an SSOT and says so: no service, disk or derived-artifact facts in it
- Either way it is ONE call. Do not hand-gather what the output already contains
- The snapshot is also where a project keeps its own checks; writing one is the "Authoring
  contract" in this repo's README (it replaces the fallback, fails soft, flags with `⚠`)

## Step 2: Synthesize what shipped
- Base = `@{upstream}` if set, else the first commit of today's work; never assume `origin/main`
- Group commits into 2–5 themes: theme · concrete files/services · live-verify result · Status
- Status ∈ `Success | Pending | Failed | Reverted`
- Produce a 2–3 line lede
- Ask a clarifying question ONLY if ≥3 commits across ≥2 themes AND the lead is unclear

## Step 3: Write SLIM `SESSION_HANDOFF.md`
Rewrite the file with ONLY these sections (target 60–90 lines, not 200):
```markdown
# SESSION_HANDOFF — YYYY-MM-DD (one-line theme)

> 2-3 line lede: what is closed, what is pending, the key decision.

## Commits this session
<git log block, newest first + ahead/on-upstream note>

## What was done
### <Theme 1> … (2-4 sentences + concrete files + live-verify)

## What was NOT done — priority
### Top-1 … (effort + concrete next steps)

## Next session start
1. Read this handoff. 2. <snapshot script, if any>. 3. CHRONICLE tail.
4. Priority: <…>. 5. Estimate Effort before starting.

## Key files for git diff
<paths grouped by area>
```
- Live-state tables -> snapshot output; do-not-touch / kill-switches / quick-orient -> `PROJECT_STATE.md`
- Reference those files in one line; never copy their content here

## Step 4: `PROJECT_STATE.md` — only if an invariant changed
- Exists AND the session introduced/removed a kill-switch, a do-not-touch, a policy or a per-tenant fact -> targeted `Edit`
- Otherwise do not touch it: one fact, one source

## Step 5: `PENDING_LEDGER.md` — append-only
- Absent -> skip; say once that pending items live only in the handoff and get overwritten next session
- Contract lives in the file's own header — read it before editing
- Close: each open `- [ ]` actually shipped this session -> targeted `Edit` to `[x]` + date, one line
- Append: each "What was NOT done" item not already open -> `- [ ] (YYYY-MM-DD) …` under today's date
- Item alive 2+ sessions AND `BACKLOG.md` exists -> propose a card, close the line with a reference
- Never delete, never bulk-rewrite

## Step 6: `CHRONICLE.md` — append the history
- Facts script flagged `⚠` on the chronicle format -> fix the format FIRST, do not append:
  a canonical line on top of a non-canonical file makes the tail unreadable and the history invisible
- One entry per logical change shipped this session and not already there (check by date + theme)
- Prepend after the file's title block:
```
- **YYYY-MM-DD**: [Type] in <area>. Description: <2-6 sentences: what, why, key files>. Status: Success|Pending|Failed|Reverted.
```
- Type ∈ `Feature | Bugfix | Refactor | Infra | Security | Docs | Engineering Quality | Engineering QA | Migration`
- Docs-only commit already covered by a feature entry -> skip, no duplicates
- Reading the tail: grep the entry lines, never `head` the file — it grows past a context window
```bash
grep -E '^- \*\*[0-9]{4}-' "$BOOKS/CHRONICLE.md" | head -30 | LC_ALL=C.UTF-8 sed -E 's/^(.{280}).*/\1 …/'
```

## Step 7: Derived artifacts flagged by the snapshot
- Snapshot reported drift on a committed derived file (e.g. a generated `*.lock` or `*.generated.yaml`) -> stage it in this commit
- Derived artifact, not hand-edited: regenerate rather than patch

## Step 8: Hygiene nag — do NOT run hygiene here
- Nag ONLY when the snapshot reported closed items past the archive window
- One line: "recommend `/hygiene`"
- Do NOT nag on open-item count: open items shrink by doing tasks, not by a script

## Step 9: Show diff, then commit (auto by default)
- Show `git diff` of touched files read-only: handoff, chronicle, ledger, state, drifted artifacts
- Stage ONLY those files; foreign dirty files -> flag and ask, never sweep them in
- Commit message:
```
docs: SESSION_HANDOFF + CHRONICLE — <one-line theme>

<3-5 line summary>

Prepared for /clear — the next session starts from this handoff.
```
- Trailers (`Co-Authored-By`, `Claude-Session`) come from the current session prompt — never hardcode here
- `git status --short` -> confirm clean-in-scope
- NOTHING staged after that -> do NOT commit, and do NOT reach for `git add -f`. Books can be
  unstageable for good reasons: a repo that deliberately keeps its own notes out of itself,
  or `fallback-untracked` books living in `$MAIN`. Report where they were written and stop —
  an empty commit records nothing, and forcing the add publishes what someone excluded
- Skip auto-commit and ask (A commit / B leave / C revert) ONLY on: a secret/PII in the diff, foreign dirty files, or operator typed `dry-run`

## Bootstrap — project has no bookkeeping yet
```bash
~/.claude/bin/session-init.sh --dry-run    # plan
~/.claude/bin/session-init.sh              # create what is missing
~/.claude/bin/session-init.sh --minimal    # only the two root files
```
- Idempotent: existing files are never touched, only missing ones are created
- Show the dry-run plan and get a "go" before creating: a project may deliberately keep only two files
- Refuses outside a git repo — bookkeeping is anchored to the repo root, or the next session cannot find it
- In a linked worktree (`$MAIN` != `$ROOT`) ask WHERE before creating, the answer is not guessable:
  tracked bookkeeping belongs here and is committed on this branch; local-only bookkeeping belongs
  in the main worktree — `session-init.sh --root "$MAIN"` — or it vanishes with the worktree

## Output (one line)
- Auto: "Session handoff committed (auto). Working tree clean in scope. Ready for `/clear`."
- B: "Handoff updated, not committed." · C: "Handoff reverted, files restored."

## Don't
- Do NOT `/clear` or `git push` yourself
- Do NOT delete `CHRONICLE` entries or bulk-rewrite `PENDING_LEDGER`
- Do NOT run heavy hygiene (card-drift / doc-sync / prune) — that is `/hygiene`
- Do NOT duplicate what `PROJECT_STATE.md` or the snapshot already says — reference it
- Do NOT commit foreign files or edit `CLAUDE.md`
