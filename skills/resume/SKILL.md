---
name: resume
description: Reorient at the start of a fresh session — reads SESSION_HANDOFF, PROJECT_STATE invariants, the CHRONICLE tail and open PENDING_LEDGER items, and surfaces where you left off / what is live / pending / do-not-touch / first step in 5-10 lines. Works in any git repository: paths resolve from the repo root, and optional pieces (snapshot script, ledger, project state) activate only when present. Live facts come from the project's snapshot script when it has one, never hand-gathered. Use after /clear or at the start of any session in a project that keeps a handoff. Missing structure -> `~/.claude/bin/session-init.sh`.
---

# Resume — 30-second reorientation

## Goal
- Operator learns where you left off / what is live / what is pending / what not to touch / first step
- Without reading 500 lines, and without you re-deriving facts a script already produces

## Step 0: Resolve project
```bash
ROOT=$(git rev-parse --show-toplevel) || { echo "not a git repo"; exit 1; }
# readlink -f, not echo: the dir may be a symlink, and git refuses paths that live
# beyond one ("beyond a symbolic link"). SESSION_DOCS_DIR / SESSION_SCRIPTS_DIR name a
# nested layout (e.g. "sub/docs") when a project keeps one; unset = plain docs/, scripts/.
pick() { for d in "$@"; do [ -d "$d" ] && { readlink -f "$d"; return 0; }; done; echo "$1"; }
DOCS=$(pick "$ROOT/docs" ${SESSION_DOCS_DIR:+"$ROOT/$SESSION_DOCS_DIR"})
SCRIPTS=$(pick "$ROOT/scripts" ${SESSION_SCRIPTS_DIR:+"$ROOT/$SESSION_SCRIPTS_DIR"})
ls -d "$ROOT"/{SESSION_HANDOFF,CHRONICLE}.md "$DOCS"/{PENDING_LEDGER,PROJECT_STATE}.md \
      "$SCRIPTS"/session-snapshot.sh 2>/dev/null
```
- Search order is fixed, not guessed: plain layout first, the configured nested layout second
- No `SESSION_HANDOFF.md` and no `CHRONICLE.md` -> project keeps no handoff: say so, run
  `~/.claude/bin/session-init.sh --dry-run`, offer it, then orient from `git log` and `README`
- Every other file is OPTIONAL: absent -> its line is omitted, not faked

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
- `SESSION_HANDOFF.md` — in full; it is already slim
- `PROJECT_STATE.md` — in full; invariants, do-not-touch, environment quirks
- `CHRONICLE.md` — last 30 ENTRIES, headers only
- `PENDING_LEDGER.md` — ALL open `- [ ]`, headers only
```bash
grep -E '^- \*\*[0-9]{4}-' CHRONICLE.md | head -30 | LC_ALL=C.UTF-8 sed -E 's/^(.{280}).*/\1 …/'
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
