# session — project bookkeeping between agent sessions

Four skills and three scripts that remember a project's state for you: where you left off,
what is still unfinished, what must not be touched, which code has already been swept. They
work in any git repository.

## Why

An agent session ends, the context is gone. The next one starts from scratch and figures
out what is going on all over again — from the code and `git log`, that is, badly. Worse,
the list of "what we did not finish" lives in your head and does not survive `/clear`.

Here that list lives in files, and the skills write and read them.

## Model

Two files are the **source of truth**; they are appended to and never rewritten:

| File | What it holds |
|---|---|
| `CHRONICLE.md` | history: what changed and when, substantively |
| `PENDING_LEDGER.md` | the tail: what was planned and left unfinished |

One is **derived**, rewritten every session:

| File | What it holds |
|---|---|
| `SESSION_HANDOFF.md` | lede, what was done, what is next — a short 60–90 line summary |

And one holds **invariants**, edited only when something has actually changed:

| File | What it holds |
|---|---|
| `PROJECT_STATE.md` | what not to touch, which safety switches exist, how the environment surprises you |

The split is not cosmetic. `SESSION_HANDOFF.md` is rewritten in full, so a "did not finish"
item that lives only there vanishes the first time the next handoff is generated. The ledger
exists precisely so that does not happen.

## Skills

| Command | When | What it does |
|---|---|---|
| `/pickup` | start of a session | reads all of the above and produces 5–10 lines: where you left off, what is pending, what not to touch, the first step |
| `/handoff` | end of a session, before `/clear` | rewrites the handoff, appends the chronicle, syncs the ledger, commits |
| `/hygiene` | weekly | audits backlog-card drift, syncs docs with commits, prunes the ledger, reclaims disk |
| `/sweep` | when an area goes stale | scans one area for dead code, duplication and stale tests and records the verdict; removal is a separate, gated invocation |

## File layout

Searched in a fixed order, not guessed:

```
<repo root>/SESSION_HANDOFF.md   CHRONICLE.md
<root>/{docs|$SESSION_DOCS_DIR}/PENDING_LEDGER.md   PROJECT_STATE.md   BACKLOG.md   SWEEP_MAP.md
<root>/{scripts|$SESSION_SCRIPTS_DIR}/session-snapshot.sh   sweep-tools.sh
```

The plain `docs/` and `scripts/` layout works out of the box. If your project nests them —
say under `infra/` or `platform/` — export `SESSION_DOCS_DIR` and `SESSION_SCRIPTS_DIR`
(e.g. `SESSION_DOCS_DIR=infra/docs`) and that layout is searched as a fallback; nothing is
hardcoded, and the plain layout always wins when both exist.

The root comes from `git rev-parse --show-toplevel`, not the working directory: an agent may
be launched from a subdirectory, and then the files would land where the next session cannot
find them.

A symlinked directory is resolved to its real path. This is not pedantry: git refuses to work
with paths beyond a symlink — `fatal: pathspec ... is beyond a symbolic link` — and committing
the bookkeeping files would fail.

**In a linked worktree the root is not enough.** A worktree checks out *tracked* files only,
so bookkeeping kept local — `.git/info/exclude`, the usual choice for maintainer notes —
exists in the main worktree alone. Resolving against the worktree root would report "this
project keeps no handoff" and offer to create a second, competing set of files. So when the
worktree has no `SESSION_HANDOFF.md` and no `CHRONICLE.md` but the main worktree does, the
books resolve there (`git worktree list` prints the main worktree first, whatever the `.git`
layout is). Reading from there is always safe; writing is gated:

| The books in the main worktree are | `/handoff` and `/hygiene` |
|---|---|
| untracked | write, and say where. Nothing is stageable, so no commit |
| tracked | stop and ask — writing dirties a checkout that may be mid-work on another branch |

Everything except the first two files is **optional**. No ledger — the step is skipped with a
line of output, not a failure.

## Scripts

**`bin/session-init.sh`** — sets up the structure if it is missing. Idempotent: it never
touches existing files, only fills in the missing ones.

```bash
session-init.sh --dry-run        # plan
session-init.sh                  # create what is missing
session-init.sh --minimal        # only the two root files
session-init.sh --with-backlog   # plus BACKLOG.md and a card directory
session-init.sh --with-sweep     # plus SWEEP_MAP.md, the /sweep coverage map
```

**`bin/session-facts.sh`** — the minimum facts about a repository: branch, HEAD, upstream
sync, changed files, recent commits, which bookkeeping files exist, ledger and chronicle
counts. Called by the skills when a project has no `scripts/session-snapshot.sh` of its own.

It has a second job. `--paths` prints the resolved layout as shell assignments and nothing
else, and every skill `eval`s it in its Step 0 instead of each re-deriving the same paths:

```bash
eval "$(~/.claude/bin/session-facts.sh --paths)"
# ROOT MAIN BOOKS DOCS SCRIPTS SWEEPMAP SWEEPTOOLS BOOKS_SOURCE BOOKS_WRITE HAVE_* …
```

Search order, `SESSION_DOCS_DIR` / `SESSION_SCRIPTS_DIR`, symlink resolution and the worktree
rule above therefore live in one place. It is read-only and **exits 0 even when every optional
file is missing** — absence is the normal case, and a probe that treats it as failure (`ls`
exits 2 on the first missing path) reports a healthy project as a broken one. A hard error
prints an evaluable `SESSION_FACTS_ERROR` instead of leaving the caller with empty output.

It lives next to the skills, not in the project — deliberately. The skills treat a project
snapshot as the source of truth and do not re-check by hand what it printed; a stub that
knows one `git` command would inherit that status over facts it does not collect. So it
states honestly at the end of its output what it does not know.

Separately, the script warns if `CHRONICLE.md` is non-empty but has no canonical-format
entries. That is a silent breakage: `/handoff` would prepend a canonical line, `/pickup`
would read only it and silently skip the whole history.

## Install

```bash
git clone git@github.com:HDsystems/session.git ~/session
~/session/install.sh
```

It links symlinks from `~/.claude/skills/` and `~/.claude/bin/` into the clone, so `git pull`
updates the skills without copying. Use `--copy` instead of symlinks if you prefer. Existing
files are not overwritten without `--force`.

A new project:

```bash
cd <project> && ~/.claude/bin/session-init.sh --dry-run
```

## Your own snapshot

If your project has something to show beyond git — service state, disks, drift of generated
files, the status of an upstream PR you are waiting on — drop in a
`scripts/session-snapshot.sh`. The skills will call it instead of `session-facts.sh` and stop
re-checking by hand what it printed.

This is also **the place for project-specific checks**. Put them here, not in a skill: the
skills stay generic and update from this repo with `git pull`, while whatever is peculiar to
your project lives in your project and survives those updates.

### Authoring contract

Five rules, and the first two are the ones that bite:

- **It REPLACES the fallback, not extends it.** When your snapshot exists, `session-facts.sh`
  is not called at all, so the git and bookkeeping baseline is now yours to produce. Easiest
  is to delegate the baseline and add your own section under it:
  ```bash
  FACTS="${CLAUDE_HOME:-$HOME/.claude}/bin/session-facts.sh"
  [ -x "$FACTS" ] && "$FACTS" --root "$ROOT"
  # ... your project-specific facts below
  ```
- **Fail soft, always exit 0.** The skills treat your output as the source of truth and do not
  re-check it. A snapshot that dies on a missing tool or an offline network takes `/pickup`
  down with it; one that silently omits a section misleads instead. Guard external calls
  (`timeout`, `|| true`, `command -v`) and print what you could not determine, e.g.
  `PR #123: unreachable (offline) — check by hand`.
- **A `⚠` marks what needs attention.** It is the one output convention the skills act on:
  `/pickup` lifts flagged lines into its Health section and re-verifies those items, and only
  those. Flag what changes what the operator would do next; leave routine green state unmarked
  or the signal is worthless.
- **Free format otherwise.** An agent reads the output, not a parser. Short labelled lines
  beat a wall of text; group related facts under a heading of your choosing.
- **No arguments, no side effects.** It is called bare and may run several times a session:
  read-only, no writes, no commits, no network probes heavy enough to be felt.

## Sweeping code

`/handoff` and `/hygiene` are safe to run half-attended because they only ever touch
bookkeeping. Deleting code is not that. A wrong removal destroys work, and the symbol that
looks unreferenced is very often the one that must stay: dispatch through a decorator registry,
a profile looked up by string, a plugin imported by name — every static detector reports those
as dead. So code-level cleanup is a separate skill, with its own gates, a backup branch before
anything is removed, and a map of what it has already looked at.

**`$DOCS/SWEEP_MAP.md`** — one row per area:

```
| Area | Swept at | Date | Verdict | Exempt |
```

`Date` is for the human reading the table. The column that does the work is **`Swept at`**,
the commit the area was swept at, because staleness is measured in **commits, not days**:

```bash
git diff --name-only <sha>..HEAD -- <area>
```

An area nobody has touched since its last sweep has nothing new in it to find. A calendar rule
would send you back into that untouched code every month to re-read the same files and re-reject
the same false positives — which is how a cleanup routine gets abandoned. Zero changed files,
zero reasons to look.

The `Exempt` column closes the other loop. A detector that is wrong about a symbol is wrong
about it on every run, so the operator's decision is recorded once, with its reason —
`permanent — reached by name through the adapter registry` — and that finding stops coming
back. Exempt areas are reported as exempt and never appear in `--stale`.

The map is edited one row at a time and never regenerated, the same rule `PENDING_LEDGER.md`
lives by and for the same reason: a bulk rewrite loses the exemptions, and the exemptions are
the one part of the file nobody can reconstruct from git.

**`bin/sweep-map.sh`** reads it:

```bash
sweep-map.sh              # per area: swept sha, commits and files since, verdict, exempt
sweep-map.sh --stale      # only the names needing a sweep, one per line
sweep-map.sh --areas      # detected areas and their language markers, to bootstrap a map
sweep-map.sh --root DIR   # explicit root, like its siblings
```

Area discovery is derived, not listed: a directory holding an ecosystem manifest — `go.mod`,
`package.json`, `pyproject.toml` and so on — is an area, and so are the siblings of those. A
project whose ecosystem is not covered exports `SWEEP_MARKERS="go.mod deps.edn …"` rather
than editing the script, the same way `SESSION_DOCS_DIR` moves the layout.

Generated trees are **auto-exempt**, and git decides it rather than a list of directory names:
a path git ignores, or one `.gitattributes` marks `linguist-generated`, is reported as
`auto-exempt (generated)` and never offered as a candidate. This matters more than it sounds.
A per-tenant tree holds near-identical generated files by construction, so every duplication
detector floods on it — and an exclusion that depends on the operator remembering is one that
fails on a tired evening. One `generated/**` Exempt row covers a tree of four hundred tenants;
four hundred hand-written rows never get written.

It resolves the layout by eval-ing `session-facts.sh --paths`, like everything else here, writes
nothing, and **exits 0 when it has nothing to report** — `--stale` printing no lines is the
answer "no area needs a sweep", not a failure. A sha the map records that git cannot resolve is
reported as needing a sweep, with the reason; a garbled row must not take the report down.

`--areas` derives areas from the ecosystem markers a repository already carries — a directory
holding `go.mod`, `package.json`, `pyproject.toml`, `Cargo.toml` and the like, and failing that
the repo's own top-level source directories per git. It carries no list of dead-code tools and
never will: which detector is right for your code is your project's business, and that is the
next file.

### Your own detectors

**`scripts/sweep-tools.sh`** — optional, project-owned, called with the area as its single
argument:

```bash
sweep-tools.sh <area>
```

This is the file that keeps the skill honest. The skill itself never greps for "looks unused":
an agent's guess about reachability is precisely the judgment that deletes live code, and
against a registry it is wrong by construction. Evidence has to come from a tool the project
picked, and no such tool can be assumed. One project's lint already flags every unused import
and wants the detector looking somewhere else entirely; the next has eight hundred Python files,
three other languages and no repo-level tooling at all. Absent, the skill says so in one line
and the sweep is manual and narrower — that is a normal outcome, not a broken setup.

The authoring contract is the snapshot's, with one difference: it takes the area as an argument.

- **It REPLACES the built-in behaviour, it does not extend it.** There is no built-in detector
  to fall back on; whatever your script prints is the evidence the sweep gets.
- **Fail soft, always exit 0.** A detector that dies halfway leaves a partial list that reads
  exactly like a complete one. Guard the calls, and print what you could not determine.
- **A `⚠` marks a finding worth acting on.** Same convention the snapshot uses, same discipline:
  flag what changes what the operator does next, or the mark stops meaning anything.
- **Exclude the generated trees yourself.** Per-tenant or code-generated directories are
  near-identical by design, so any duplication detector floods on them. They must be out by
  default, not by luck.
- **Free format otherwise.** An agent reads the output, not a parser.

## License

MIT — see [LICENSE](LICENSE). Copy, adapt and ship these skills freely; keep the copyright
notice.

## Contributing

Issues and pull requests are welcome. By contributing you agree that your contributions are
licensed under the MIT License that covers this repository — inbound matches outbound, and
there is no CLA to sign.

Only send code you have the right to give away: if you wrote it on an employer's time or
equipment, the rights may not be yours to license.
