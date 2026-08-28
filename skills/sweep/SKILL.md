---
name: sweep
description: Code-level cleanup with a coverage map — scans ONE area for dead code, duplication and stale tests, reports, and removes only what a separate, confirmed invocation approves. Works in any git repository and in a linked worktree: paths resolve through `session-facts.sh --paths`, and optional pieces (the project's detector script, the sweep map, the ledger) activate only when present. Evidence comes from the detectors a project declares in its own `sweep-tools.sh`, never from a guess about reachability — symbols dispatched through a registry or a string lookup look unused to every static tool. Coverage is tracked per area in SWEEP_MAP.md, and staleness is measured in COMMITS, not days. This is the dangerous cleanup deliberately split OUT of /hygiene, which touches bookkeeping only. Missing structure -> `~/.claude/bin/session-init.sh --with-sweep`.
---

# Sweep — dead code, duplication, stale tests

## Model
- `/hygiene` is cheap and touches bookkeeping. `/sweep` touches CODE and can destroy work
- SCAN and REMOVE are SEPARATE invocations. A scan never touches CODE or history — but it is
  not inert: it runs the project's detectors and its test suite, and it writes the map row and
  the report file. Say that before running anything, and record `git status --short` first so
  a detector that dirties the tree is visible and not blamed on you
- Evidence is produced by the project's own detectors. You NEVER decide "this looks unused":
  in a registry-driven codebase that guess is wrong by construction (see the hazard below)
- `$DOCS/SWEEP_MAP.md` is the coverage map, one row per area. Staleness is counted in COMMITS:
  an area untouched since its last sweep needs no re-sweep, whatever the date says
- One area per invocation. A whole-repo sweep produces a report nobody can verify line by line

## Step 0: Resolve project
```bash
FACTS="${CLAUDE_HOME:-$HOME/.claude}/bin/session-facts.sh"
eval "$("$FACTS" --paths)"   # ROOT MAIN BOOKS DOCS SCRIPTS BOOKS_SOURCE BOOKS_WRITE HAVE_*
[ -n "${ROOT:-}" ] || { echo "layout unresolved: ${SESSION_FACTS_ERROR:-$FACTS missing — reinstall}"; exit 1; }
echo "BOOKS $BOOKS ($BOOKS_SOURCE, write:$BOOKS_WRITE)"
echo "handoff=$HAVE_HANDOFF chronicle=$HAVE_CHRONICLE ledger=$HAVE_LEDGER \
state=$HAVE_STATE backlog=$HAVE_BACKLOG snapshot=$HAVE_SNAPSHOT"
echo "sweepmap=$HAVE_SWEEPMAP sweeptools=$HAVE_SWEEPTOOLS"
```
- ONE call and it EXITS 0 even when every optional file is missing: absence is the normal,
  documented case, never a failure. Do NOT probe with `ls` — it exits 2 on the first missing
  path, which turns a healthy project into "failed to resolve the layout"
- `--paths` is the single source of truth for the layout: search order, `SESSION_DOCS_DIR` /
  `SESSION_SCRIPTS_DIR`, symlink resolution and the worktree rule live there, not here
- Bookkeeping lives under `$BOOKS`, NOT `$ROOT` — in a linked worktree the two differ, and
  `$DOCS` is already resolved against `$BOOKS`. The CODE you sweep is under `$ROOT`; the map
  that records the sweep is under `$DOCS`, and in a worktree those are two different trees
- `$SWEEPMAP` and `$SWEEPTOOLS` come from the same call — do NOT re-derive either path
- `BOOKS_WRITE=fallback-tracked` -> the map is tracked in `$MAIN`: scan and report from here,
  but ask the operator to re-run `/sweep` from `$MAIN` before a row is written
- `HAVE_STATE=yes` -> read `$DOCS/PROJECT_STATE.md` FIRST. Do-not-touch entries outrank every
  finding below, and a sweep is exactly the operation they exist to stop

## Step 1: Pick the area
```bash
SWEEP="${CLAUDE_HOME:-$HOME/.claude}/bin/sweep-map.sh"
"$SWEEP"            # per area: swept sha, files changed since, verdict, exempt
"$SWEEP" --stale    # only the areas needing a sweep, one per line
"$SWEEP" --areas    # detected areas + language markers, for bootstrapping a map
```
- `HAVE_SWEEPMAP=no` FIRST -> no map yet: show `--areas`, let the operator pick, and create the
  file with `~/.claude/bin/session-init.sh --with-sweep --root "$BOOKS"`. Rows come only from a
  real sweep, never from the bootstrap. `--root "$BOOKS"` because in a linked worktree the plain
  form writes a map into a tree this skill will never read again
- `BOOKS_WRITE=fallback-tracked` -> the bootstrap is the operator's job from `$MAIN`, not yours
- ONLY THEN: `HAVE_SWEEPMAP=yes` and `--stale` prints nothing -> nothing is stale, say it and STOP.
  `--stale` is silent in three different states, and "no map at all" is not "clean"
- Areas marked Exempt, and areas the script tags auto-exempt, are NOT candidates
- Operator named an area explicitly -> sweep that one, even if the map calls it fresh. But NEVER
  one the map marks Exempt or the script calls generated: read the exemption's reason back to
  them and ask them to remove the row first. A tired "just sweep the tenants" is not a licence

## Step 2: Evidence — the project's detectors
- `HAVE_SWEEPTOOLS=yes` -> `"$SWEEPTOOLS" <area>`. It is the SSOT of findings for this area:
  which detector runs, and what it excludes, is the project's decision, not yours
- `HAVE_SWEEPTOOLS=no` -> you CANNOT find anything. Say exactly that: "no detectors declared —
  I can verify candidates you name, I cannot find them", and stop looking. This is the common
  case, and it is the branch where a model most wants to substitute its own reading for evidence
- In that state the only admissible candidate is one the OPERATOR nominated by name. You may
  still record an observation ("these two files look alike"), but label it `observation, not a
  finding` — it is never eligible for Step 6 and never enters the report's candidate lists
- Do NOT install, add or run a detector the project has not declared, and do NOT substitute
  your own grep for one
- A class of finding the project's own lint already reports on every commit (unused imports,
  unused locals) is lint noise, not a sweep finding: mention it once, do not itemise it

## Step 3: The registry hazard — the dominant false positive
- Registry dispatch means a symbol is reached BY NAME, not by a call site: a registering
  decorator, a dict of name -> class, a plugin loaded through reflection, a handler named in
  config, a profile or capability table
- Such a symbol has no static caller BY CONSTRUCTION. Every detector reports it as dead. It is not
- Search for the REGISTRATION KEY read off the decorator or registry entry, not only the symbol
  name: `@register("stripe") class StripeAdapter` dispatches on `stripe`, and no variant of
  `StripeAdapter` will ever find it. Search its variants too (snake, kebab, dotted, quoted), and
  in NON-code files — yaml, json, toml, sql, templates, fixtures, config
- Run BOTH commands, every time. `grep` is often shell-aliased to a gitignore-aware tool, and a
  generated tree is exactly what gets ignored — a bare `grep -rn` has been measured returning
  ZERO hits for a key present in five files:
```bash
git -C "$ROOT" grep -n -- "$KEY" || true                                  # tracked files
command grep -rn --binary-files=without-match -- "$KEY" "$ROOT" || true   # everything on disk
```
- **An empty result is NOT proof of deadness.** For live registry code an empty result is the
  EXPECTED output. It downgrades the candidate to "needs someone who knows the dispatch"; it
  never promotes it to removable
- The generated tree is gitignored and absent from disk -> its keys are unsearchable, so dead
  code cannot be established in this repository at all. Report that and propose no deletions
- An import that exists only for its side effect registers everything in that module at import
  time. Removing "the unused import" silently unregisters the lot, and nothing fails until runtime
- A false positive that keeps coming back -> propose an Exempt row with its reason, not a deletion

## Step 4: Classify — three findings, three different gates
**Dead code** — propose only when ALL THREE hold:
1. detector evidence naming file, line and symbol
2. a POSITIVE reachability answer — a detector that understands this project's registries, or
   the operator stating the symbol is unreachable. The Step 3 search only ever REFUTES: a hit
   kills the candidate, an empty result proves nothing and leaves gate 2 unmet
3. the test suite was GREEN before. A red baseline gives no signal: STOP and report that instead

**Duplication** — NEVER merged automatically:
- Output a proposal: the two sites, the proposed target, what each caller would have to change
- The operator decides. A wrong merge couples two things that were only coincidentally alike,
  and the coupling is discovered much later, by a change that needed only one of them
- Generated and per-tenant trees hold near-identical files by design — excluded, see "Never sweep"

**Stale tests** — the strictest gate of the three:
- A test nobody runs may be the only surviving record of a bug someone paid for
- Removal requires the code under test to be GONE (show it), or an explicit operator decision
  naming that test
- `skip` / `xfail` / commented out is evidence someone DEFERRED it, not that it is stale
- Never delete a failing test to make a suite green. Report it as a finding

## Step 5: Report — the scan ends here
```
## Sweep scan — <area> @ <short sha>
Detectors: <sweep-tools.sh | none — manual, narrower>   Baseline tests: <green|red|not run>

### Dead code candidates (N)
- <file:line> <symbol> — detector: <what it said>; reachability: <what was searched, what was found>
### Duplication — proposals only (N)
- <A> ↔ <B> (<n> lines) — proposed target: <…>; risk if merged: <…>
### Stale test candidates (N)
- <test> — code under test: <present | gone since <sha>>
### Exempt, not re-proposed (N)
- <symbol> — <reason, quoted from the map>
```
- Persist it at `$DOCS/sweep/<area-slug>-<short-sha>.md` — Step 6 opens it BY PATH. A report
  that lived only in a chat window cannot be checked by the invocation acting on it
- Then write the map row (Step 7) and STOP. A scan changes no code, ever
- Nothing found -> say "clean", still write the row: a recorded clean sweep is what stops the
  next session from redoing this one

## Step 6: Remove — a SEPARATE invocation
- Only against a scan report the operator has read. A removal that starts with its own scan
  hides every gate above behind one confirmation
- Confirm PER ITEM, not per batch: the operator names which candidates go
- Open the persisted report and check it is still current: `git -C "$ROOT" rev-parse --short HEAD`
  against the sha in its name. Different -> re-run Step 3 for every candidate before touching one
- Backup branch BEFORE the first deletion. This is a GATE with an abort, not a courtesy — a dirty
  tree backs up nothing, and `branch` fails on a name that already exists or is not a valid ref
  (an area of `.` yields one). Chain it so a failure stops the removal:
```bash
SLUG=$(printf '%s' "<area>" | tr '/' '-' | sed 's/^[.-]*//; s/^$/root/')
test -z "$(git -C "$ROOT" status --porcelain)" \
  && git -C "$ROOT" branch "sweep-backup/$SLUG-$(date +%Y-%m-%dT%H%M%S)" \
  || { echo "no backup — aborting, delete nothing"; exit 1; }
```
- One commit per finding class, never one giant commit — a bad hunk must be revertable alone
- Re-run the suite after each commit. Not green -> revert to the backup branch; do NOT fix forward
- A DELETED test can never fail the suite, so green proves nothing about it. Record the collected
  test count before and after, and where the project measures coverage, the delta for the touched
  paths. Coverage that dropped further than the removed source explains is a revert, not a pass
- Deleted, not archived: the backup branch and git history ARE the archive

## Step 7: Record it
- `$SWEEPMAP` — contract lives in the file's own header; read it before editing
- One row per area swept, targeted `Edit`, never a bulk rewrite
- "Swept at" is the SHA the scan ran at (`git -C "$ROOT" rev-parse --short HEAD`), not the date
- Verdict wording follows the vocabulary the map's own header defines — do not invent a second one
- "Exempt" is written ONLY on an explicit operator decision and ALWAYS carries its reason,
  e.g. `permanent — reached by name through the adapter registry`. Never on your own judgement
- Removal happened -> prepend one `CHRONICLE.md` entry after the title block, Type `Refactor`:
  `- **YYYY-MM-DD**: [Refactor] in <area>. Description: <what was removed, why, key files>. Status: Success.`
  A scan is not history; it produces no entry
- Area left unfinished, or a candidate the operator deferred -> append `- [ ] (YYYY-MM-DD) …` to
  `$DOCS/PENDING_LEDGER.md` under today's date. Never delete, never bulk-rewrite

## Never sweep
- Generated, per-tenant and vendored trees. `sweep-map.sh` tags them `auto-exempt (generated)`
  from git itself — an ignored path, or one `.gitattributes` marks generated — so this holds with
  no map and no `sweep-tools.sh`. But git only knows what git was told: BEFORE reporting any
  finding in an area, name which mechanism excludes the generated trees here — the auto-exempt
  tag, a glob Exempt row such as `generated/**`, or `sweep-tools.sh`. NONE of the three ->
  STOP and ask for the Exempt row. Do not scan on the strength of remembering
- A directory where the project parks deprecated code on purpose: parked is a decision, not rot
- Areas the map marks Exempt
- Anything reachable through a registry, reflection or a string lookup
- Files listed as do-not-touch in `PROJECT_STATE.md`, or under a `/freeze`

## Don't
- Do NOT grep for "looks unused" and call it evidence — that is the detector's job
- Do NOT scan and remove in one invocation
- Do NOT merge duplicates yourself, however obvious the target looks
- Do NOT delete a test to make a suite green, and do NOT delete one whose subject still exists
- Do NOT install or configure tooling the project has not declared
- Do NOT bulk-rewrite `SWEEP_MAP.md`, and do NOT write an Exempt row without the operator
- Do NOT `git push` or `/clear` yourself, and do NOT edit `CLAUDE.md`
