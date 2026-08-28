#!/usr/bin/env bash
# sweep-map.sh — which areas of a project have been swept, and at which commit.
#
# Reads "$DOCS/SWEEP_MAP.md", the coverage map the /sweep skill keeps. Reports only;
# the map is written by /sweep, never by this script.
#
#   sweep-map.sh              per area: swept sha, commits and files since, verdict, exempt
#   sweep-map.sh --stale      only the area names needing a sweep, one per line
#   sweep-map.sh --areas      detected areas and their language markers, to seed a map
#   sweep-map.sh --root DIR   explicit root instead of the git root
#
# Staleness is counted from a COMMIT, not from a date: an area nobody has edited since its
# last sweep has nothing new to find, and a date rule would send the operator back into
# untouched code every month. The report prints both how many commits touched the area and
# how many files they changed.
#
# Area discovery derives from git and from canonical ecosystem markers (a directory holding
# go.mod, package.json, pyproject.toml …), never from a list of dead-code tools: which
# detector to run is the project's business and lives in its sweep-tools.sh. Override the
# marker set with SWEEP_MARKERS="go.mod package.json …".
#
# GENERATED trees are auto-exempt, and that is not a judgement call: an area git ignores, or
# that .gitattributes marks linguist-generated, is where per-tenant and vendored code lives.
# It is near-identical by construction, so every duplication detector floods on it. Nobody
# should have to remember a row for each one.
#
# Writes nothing under $ROOT and makes no network call; it uses one temporary file. Exits 0
# when the answer is "nothing to report" — no map, no data rows and no stale area are all
# normal states, not failures.
set -euo pipefail

MODE=report
ROOT_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --stale) MODE=stale ;;
        --areas) MODE=areas ;;
        --root)
            ROOT_ARG="${2:-}"
            [ -n "$ROOT_ARG" ] || { echo "--root needs a directory" >&2; exit 2; }
            shift ;;
        -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

fail() { echo "sweep-map: $1" >&2; exit 1; }

# --- layout ------------------------------------------------------------------
# session-facts.sh --paths is the single source of truth for ROOT/MAIN/BOOKS/DOCS/SCRIPTS;
# re-deriving them here is exactly the divergence this repo already paid to remove. Prefer
# the installed copy, fall back to the sibling in this clone so a bare checkout works too.
FACTS="${CLAUDE_HOME:-$HOME/.claude}/bin/session-facts.sh"
SIBLING="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-facts.sh"
[ -x "$FACTS" ] || FACTS="$SIBLING"
[ -x "$FACTS" ] || fail "cannot find session-facts.sh — reinstall with install.sh."
# Cleared before the eval, never after: an inherited SWEEPMAP from the caller's environment
# would otherwise survive an older installed session-facts.sh that does not emit it, and this
# script would then report confidently on some other project's map.
unset ROOT MAIN BOOKS DOCS SCRIPTS SWEEPMAP SWEEPTOOLS
eval "$("$FACTS" --paths ${ROOT_ARG:+--root "$ROOT_ARG"} 2>/dev/null || true)"
# An installed copy too old to know --paths is, in effect, an absent one: it answers
# "unknown argument" and leaves us with no layout. Retry against this clone's own before
# giving up, so a checkout that is ahead of the install still reports.
if [ -z "${ROOT:-}" ] && [ "$FACTS" != "$SIBLING" ] && [ -x "$SIBLING" ]; then
    eval "$("$SIBLING" --paths ${ROOT_ARG:+--root "$ROOT_ARG"} 2>/dev/null || true)"
fi
[ -n "${ROOT:-}" ] || fail "layout unresolved: ${SESSION_FACTS_ERROR:-$FACTS knows no --paths}"

# SWEEPMAP comes from --paths once session-facts knows it; the fallback keeps this script
# usable against an older installed copy without teaching it the path a second time.
SWEEPMAP="${SWEEPMAP:-$DOCS/SWEEP_MAP.md}"
MAP_REL="${SWEEPMAP#"$BOOKS"/}"

# The one place a marker is named. It is a set of ECOSYSTEM manifests — the file a language
# puts at the root of a unit of code — not a set of tools, and a project that needs another
# one exports SWEEP_MARKERS rather than editing this script.
MARKERS="${SWEEP_MARKERS:-go.mod package.json pyproject.toml setup.py Cargo.toml
    pom.xml build.gradle build.gradle.kts Gemfile composer.json CMakeLists.txt mix.exs}"

LSFILES=$(mktemp) || fail "cannot create a temporary file"
trap 'rm -f "$LSFILES"' EXIT
git -C "$ROOT" ls-files 2>/dev/null >"$LSFILES" || true

# git already knows what is generated; asking it beats keeping a list of directory names that
# would be wrong in the next repository. check-ignore covers the common case (the tree is
# ignored), check-attr the declared one.
is_generated() {
    # --no-index on purpose: without it check-ignore stays silent for a path already in
    # the index, and a generated tree committed before someone ignored it is exactly the
    # case that must not slip through.
    if git -C "$ROOT" check-ignore --no-index -q -- "$1" 2>/dev/null; then return 0; fi
    if git -C "$ROOT" check-attr linguist-generated -- "$1" 2>/dev/null | grep -q ': set$'; then return 0; fi
    return 1
}

# Bookkeeping is /hygiene's ground, not /sweep's. Excluding it here keeps the model from
# offering to hunt dead code in the very files that record the hunt.
is_bookkeeping() {
    case "$1" in
        "${DOCS#"$ROOT"/}"|"${DOCS#"$ROOT"/}"/*|"${SCRIPTS#"$ROOT"/}"|"${SCRIPTS#"$ROOT"/}"/*) return 0 ;;
        *) return 1 ;;
    esac
}

# --- the map -----------------------------------------------------------------
# Column POSITIONS are read from the header row, not assumed: the map is edited by hand and
# by an agent, and a reordered or extra column must not silently shift every value by one.
# Emits one record per data row: area, sha, date, verdict, exempt. The field separator is
# US, not a tab: `read` treats tabs as IFS whitespace and would collapse the empty cells of
# a row that records only an exemption, shifting its reason into the commit column.
MAPSEP=$'\037'
read_map() {
    [ -f "$SWEEPMAP" ] || return 0
    awk -F'|' -v OFS="$MAPSEP" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function cell(i) { return (i > 0 && i <= n) ? c[i] : "" }
        /^[ \t]*\|/ {
            n = 0; split("", c)
            for (i = 2; i <= NF; i++) c[++n] = trim($i)
            if (n > 0 && c[n] == "") n--          # trailing pipe leaves an empty cell
            if (n == 0) next
            sep = 1
            for (i = 1; i <= n; i++) if (c[i] !~ /^:?-+:?$/) { sep = 0; break }
            if (sep) next                          # |---|---| under the header
            if (!hdr) {
                split("", col)
                for (i = 1; i <= n; i++) col[tolower(c[i])] = i
                if ("area" in col) { hdr = 1; hdrn = n; next }
                next                               # a table before the map table
            }
            # A stray pipe inside a cell shifts every value right and would quietly land a
            # verdict in the Exempt column, turning a stale area into a permanent exemption.
            # Report the row instead of reading it.
            if (n != hdrn) { print "!MALFORMED", NR, $0, "", ""; next }
            area = cell(col["area"])
            if (area == "") next                   # a spacer row carries no area
            ex = cell(col["exempt"])
            if (ex ~ /^[-—–]*$/) ex = ""           # a dash is a placeholder, not a reason
            print area, cell(col["swept at"]), cell(col["date"]), cell(col["verdict"]), ex
        }
    ' "$SWEEPMAP" 2>/dev/null || true
}

# An Exempt row may name a glob: one `generated/**` row must cover every tenant, or a repo
# with four hundred of them needs four hundred hand-written rows and gets none.
EXEMPT_GLOBS=""
collect_exempt_globs() {
    while IFS="$MAPSEP" read -r a _ _ _ ex; do
        case "$a" in *[*?[]*) [ -n "$ex" ] && EXEMPT_GLOBS="$EXEMPT_GLOBS$a"$'\n' ;; esac
    done
}
glob_exempt() {   # is this area covered by some glob row?
    local area="$1" g
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        # shellcheck disable=SC2254 — the pattern is the point
        case "$area" in $g) return 0 ;; esac
    done <<<"$EXEMPT_GLOBS"
    return 1
}

# --- area discovery ----------------------------------------------------------
# A directory holding an ecosystem marker is an area. Everything else is derived from it:
# the siblings of those areas (walking the root and the marker dirs' ancestors) are areas
# too, and with no marker anywhere in the repo that walk degenerates to the top-level
# source directories git knows about — which is the wanted answer for a single-tree project.
marker_rows() {
    awk -v markers="$MARKERS" -F/ '
        BEGIN { n = split(markers, m, " "); for (i = 1; i <= n; i++) want[m[i]] = 1 }
        {
            if (!($NF in want)) next
            print ((NF == 1) ? "." : substr($0, 1, length($0) - length($NF) - 1)) "\t" $NF
        }
    ' "$LSFILES" | sort -u
}

discover_areas() {
    local rows markdirs ancestors cands
    rows="$1"
    markdirs=$(printf '%s\n' "$rows" | cut -f1 | sed '/^$/d' | sort -u)
    # The root is ALWAYS an ancestor, including when it is itself a marker directory. A repo
    # whose manifest sits at the top is the single-package case /sweep most often meets, and
    # dropping "." here collapsed it to one un-sweepable area covering the whole tree.
    ancestors=$(printf '%s\n.\n' "$markdirs" | awk -F/ '
        $0 == "" { next }
        $0 == "." { print "."; next }
        { p = ""; for (i = 1; i < NF; i++) { p = (p == "" ? $i : p "/" $i); print p } print "." }
    ' | sort -u)
    cands=$(awk -F/ '
        NF > 1 {
            parent = "."; path = ""
            for (i = 1; i < NF; i++) { path = (path == "" ? $i : path "/" $i); print parent "\t" path; parent = path }
        }
    ' "$LSFILES" | sort -u | awk -F'\t' -v anc="$ancestors" -v mk="$markdirs" '
        BEGIN {
            n = split(anc, a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") A[a[i]] = 1
            n = split(mk,  b, "\n"); for (i = 1; i <= n; i++) if (b[i] != "") M[b[i]] = 1
        }
        ($1 in A) && !($2 in M) && !($2 in A) { print $2 }
    ' | sort -u)
    # "." earns a row only when nothing finer exists: with real children it would overlap
    # every one of them, and an area that contains the others cannot be swept on its own.
    if [ -n "$cands" ]; then
        markdirs=$(printf '%s\n' "$markdirs" | sed '/^\.$/d')
    fi
    printf '%s\n%s\n' "$markdirs" "$cands" | sed '/^$/d' | sort -u
}

area_exts() {   # top three tracked file extensions in an area — its language marker
    local pre=""
    [ "$1" = "." ] || pre="$1/"
    awk -v pre="$pre" '
        pre == "" || index($0, pre) == 1 {
            base = $0; sub(/^.*\//, "", base)
            if (base ~ /\./) { e = base; sub(/^.*\./, "", e); print e }
        }
    ' "$LSFILES" | sort | uniq -c | sort -rn | head -3 \
        | awk '{ printf "%s.%s x%s", sep, $2, $1; sep = " " } END { print "" }'
}

plural() { [ "$1" = 1 ] && printf '%s' "$2" || printf '%s' "$3"; }

# --- modes -------------------------------------------------------------------
if [ "$MODE" = areas ]; then
    ROWS=$(marker_rows)
    AREAS=$(discover_areas "$ROWS")
    if [ -z "$AREAS" ]; then
        echo "AREAS  none detected — git tracks no files under $ROOT yet."
        exit 0
    fi
    MAPPED=$(read_map | cut -d"$MAPSEP" -f1 | sort -u)
    WIDTH=$(printf '%s\n' "$AREAS" | awk 'length > m { m = length } END { print (m < 12 ? 12 : m) }')
    echo "AREAS  detected from git — marker directories first, then their siblings"
    while IFS= read -r area; do
        [ -n "$area" ] || continue
        MK=$(printf '%s\n' "$ROWS" | awk -F'\t' -v d="$area" '$1 == d { printf "%s%s", sep, $2; sep = "," } END { print "" }')
        [ -n "$MK" ] || MK="-"
        TAG=""
        if is_generated "$area"; then TAG="  auto-exempt (generated)"
        elif is_bookkeeping "$area"; then TAG="  bookkeeping — /hygiene, not /sweep"
        elif printf '%s\n' "$MAPPED" | grep -qxF "$area"; then TAG="  (in map)"
        fi
        printf "       %-${WIDTH}s %-16s %s%s\n" "$area" "$MK" "$(area_exts "$area")" "$TAG"
    done <<<"$AREAS"
    echo "SCAN   markers, override with SWEEP_MARKERS:"
    # Unquoted on purpose: the set is a whitespace-separated string, and xargs re-flows it
    # onto lines that fit the report.
    printf '%s\n' $MARKERS | xargs -n 6 | sed 's/^/       /'
    echo "       A detected area is a candidate for the map, not a decision. An auto-exempt"
    echo "       row needs no map entry; parked or vendored code needs one, with its reason."
    exit 0
fi

MAP_ROWS=$(read_map)
collect_exempt_globs <<<"$MAP_ROWS"

if [ "$MODE" != stale ]; then
    if [ ! -f "$SWEEPMAP" ]; then
        echo "MAP    none — $MAP_REL does not exist, so no area has been swept."
        echo "       Create it with session-init.sh --with-sweep; sweep-map.sh --areas"
        echo "       lists what this repository would be swept by area."
        exit 0
    fi
    if [ -z "$MAP_ROWS" ]; then
        echo "MAP    $MAP_REL — no areas recorded yet."
        echo "       That is the state right after --with-sweep: rows come from a real sweep."
        exit 0
    fi
    echo "MAP    $MAP_REL"
fi

TOTAL=0
STALE=0
EXEMPT=0
CURRENT=0
VANISHED=0
MALFORMED=0

while IFS="$MAPSEP" read -r AREA SHA DATE VERDICT EX; do
    [ -n "$AREA" ] || continue

    if [ "$AREA" = "!MALFORMED" ]; then
        MALFORMED=$((MALFORMED + 1))
        [ "$MODE" = stale ] && continue
        echo "AREA   ⚠ line $SHA of the map has the wrong number of columns — an unescaped"
        echo "       pipe inside a cell. Fix the row; it is being ignored, not guessed at."
        continue
    fi

    TOTAL=$((TOTAL + 1))

    if [ -z "$EX" ] && glob_exempt "$AREA"; then EX="covered by a glob row in the map"; fi
    if [ -z "$EX" ] && is_generated "$AREA"; then EX="generated — git ignores it or marks it generated"; fi

    if [ -n "$EX" ]; then
        EXEMPT=$((EXEMPT + 1))
        [ "$MODE" = stale ] && continue
        echo "AREA   $AREA"
        echo "       exempt: $EX"
        continue
    fi

    # An area that no longer exists needs a map edit, not a sweep: keeping it out of --stale
    # is the difference between a fixable row and a name no operator can act on.
    GONE=0
    [ -e "$ROOT/$AREA" ] || GONE=1

    REASON=""
    COMMITS=""
    FILES=""
    if [ -z "$SHA" ]; then
        REASON="no commit recorded in the map"
    elif ! git -C "$ROOT" rev-parse --verify --quiet "${SHA}^{commit}" >/dev/null 2>&1; then
        REASON="swept-at commit $SHA is not in this repository (rebased, or a typo)"
    elif CHANGED=$(git -C "$ROOT" diff --name-only "$SHA..HEAD" -- "$AREA" 2>/dev/null); then
        FILES=$(printf '%s' "$CHANGED" | grep -c . || true)
        COMMITS=$(git -C "$ROOT" rev-list --count "$SHA..HEAD" -- "$AREA" 2>/dev/null || echo 0)
    else
        REASON="git could not diff $SHA..HEAD over this area"
    fi

    NEEDS=0
    if [ -n "$REASON" ]; then
        NEEDS=1
    elif [ "$FILES" != 0 ]; then
        NEEDS=1
    fi
    [ "$GONE" = 1 ] && NEEDS=0

    if [ "$GONE" = 1 ]; then VANISHED=$((VANISHED + 1))
    elif [ "$NEEDS" = 1 ]; then STALE=$((STALE + 1))
    else CURRENT=$((CURRENT + 1)); fi

    if [ "$MODE" = stale ]; then
        [ "$NEEDS" = 1 ] && echo "$AREA"
        continue
    fi

    echo "AREA   $AREA"
    printf '       swept at %s%s%s\n' \
        "${SHA:-<none>}" \
        "${DATE:+ ($DATE)}" \
        "${VERDICT:+, verdict: $VERDICT}"
    if [ "$GONE" = 1 ]; then
        echo "       ⚠ path does not exist under $ROOT — the row outlived the code, fix the map"
    elif [ -n "$REASON" ]; then
        echo "       ⚠ $REASON -> NEEDS A SWEEP"
    elif [ "$FILES" = 0 ]; then
        echo "       unchanged since -> current"
    else
        echo "       $COMMITS $(plural "$COMMITS" commit commits) touching it since, $FILES $(plural "$FILES" file files) changed -> NEEDS A SWEEP"
    fi
done <<<"$MAP_ROWS"

[ "$MODE" = stale ] && exit 0

echo "SWEEP  $TOTAL $(plural "$TOTAL" area areas) mapped — $STALE $(plural "$STALE" needs need) a sweep, $CURRENT current, $EXEMPT exempt."
[ "$MALFORMED" != 0 ] && echo "       ⚠ $MALFORMED malformed $(plural "$MALFORMED" row rows) ignored — see above"
[ "$VANISHED" != 0 ] && echo "       ⚠ $VANISHED mapped $(plural "$VANISHED" area areas) no longer $(plural "$VANISHED" exists exist) — $(plural "$VANISHED" 'that row wants' 'those rows want') an edit, not a sweep"
[ "$STALE" -gt 0 ] && echo "       Names alone, for scripting: sweep-map.sh --stale"

# Auto-exempt and bookkeeping areas are not "missing from the map": nagging the operator to
# write a row for a tree that must never be swept is how the nag gets ignored entirely.
UNMAPPED=0
while IFS= read -r a; do
    [ -n "$a" ] || continue
    is_generated "$a" && continue
    is_bookkeeping "$a" && continue
    glob_exempt "$a" && continue
    UNMAPPED=$((UNMAPPED + 1))
done < <(comm -23 <(discover_areas "$(marker_rows)") <(printf '%s\n' "$MAP_ROWS" | cut -d"$MAPSEP" -f1 | sed '/^$/d' | sort -u))
[ "$UNMAPPED" != 0 ] && echo "       $UNMAPPED detected $(plural "$UNMAPPED" area areas) $(plural "$UNMAPPED" is are) absent from the map — sweep-map.sh --areas"
exit 0
