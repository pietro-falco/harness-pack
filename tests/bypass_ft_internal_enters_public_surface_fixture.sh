#!/usr/bin/env bash
# internal-enters-public-surface -- the separation between the internal and the
# public surface must not depend on anyone remembering it. The subject is
# scripts/statement_lint.py --surface: given a scratch repository with a
# published baseline ref and a set of tracked files added on top of it, the
# boundary MUST refuse any added file that carries a private class (a home
# path, the vault name, a model id, a private repo name) unless that file
# carries one of exactly two machine-checkable exemption reasons:
#
#   RULE    the file is a transformation rule that names what it replaces --
#           every class hit inside it lies inside its own `pattern` or
#           `replacement` value. The rule that removes the string must state
#           the string; that is the whole reason this reason exists.
#   PINNED  the file is evidence fixed by a digest -- its sha256 appears
#           verbatim in some other tracked file, so rewriting it breaks the
#           pin. Machine facts inside evidence cannot be edited away without
#           destroying what fixes them.
#
# A file in neither is not an exemption. There is no third reason and no path
# list: a hand-written exclusion is exactly the defect this fixture exists to
# refuse (the four pathspec exclusions in .verity/claims.json carry the entire
# already-published exposure, and nothing verifies that any of them is
# entitled to be an exclusion).
#
# ELEVEN ARMS, one scratch repository per arm:
#   A. added file carries a home path, no exemption      -> want refusal (1)
#   B. added file is a rule naming its own pattern       -> want accept  (0)
#   C. added file is a rule carrying the string OUTSIDE
#      its own pattern/replacement                       -> want refusal (1)
#   D. added evidence whose sha256 is pinned elsewhere   -> want accept  (0)
#   E. the same evidence with the pin removed            -> want refusal (1)
#   F. baseline class count declared wrong by one        -> want refusal (1)
#   G. added files carry nothing at all                  -> want accept  (0)
#   H. the file that NAMES the classes, carrying each
#      of them exactly and nothing wider                  -> want accept  (0)
#   I. the same file also carrying a fact about THIS
#      machine, which no declaration can name             -> want refusal (1)
#   J. internal material in a repository with NO REMOTE   -> want accept  (0)
#   K. the very same tree, once it gains a remote         -> want refusal (1)
#
# G is the positive control: without it, A/C/E/F would pass for a boundary that
# refuses everything it is shown, which measures nothing. B and D are the
# controls for the two exemption reasons: without them, a boundary that
# recognises no exemption at all would look identical to a correct one. H and I
# are the pair that matters most: the file declaring the classes cannot avoid
# carrying them, so it is exempt exactly where each occurrence IS a declared
# literal -- and a class computed from the running machine, which no
# declaration can name, is never exempt there. I is what stops the declaration
# from becoming the hand-written exclusion this fixture exists to refuse.
#
# J and K are the separation itself, and they are one repository measured
# twice: nothing in the tree changes between them, only whether it can be
# pushed. A repository with no remote has no public surface -- that is a fact
# read from the repository, not a promise anyone made about it, which is the
# whole difference between a separation and a habit. K is the failure this
# fixture exists for: the moment the internal surface gains somewhere to go,
# the same claim stops being satisfied by emptiness and names what would
# travel.
#
# STATES. RED (exit 1): any arm's outcome differs from what it wants -- the
# boundary either let internal material onto the public surface or refused a
# file that carries a stated, checkable reason. GREEN (exit 0): all eleven
# match. UNMEASURED (exit 2): python3, git, or the boundary itself is absent,
# or the boundary does not implement --surface. That is not a pass and not a
# fail: the arm never reached its own question.
set -u

LINT="${STATEMENT_LINT:-$(cd "$(dirname "$0")/.." && pwd)/scripts/statement_lint.py}"
command -v python3 >/dev/null 2>&1 || { echo "UNMEASURED: python3 absent" >&2; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "UNMEASURED: git absent" >&2; exit 2; }
[ -f "$LINT" ] || { echo "UNMEASURED: boundary not found at $LINT" >&2; exit 2; }

# The home-path token is ASSEMBLED, NOT SPELLED, for the same reason
# scripts/statement_lint.py assembles it (see LITERAL_USERS there): this
# fixture is itself a tracked file on the public surface, and a control that
# had to spell the thing it guards would be an instance of what it refuses.
# The planted path is also NOT this operator's home -- arm I is the one that
# uses the real one, in a scratch repository deleted on exit.
U="/""Users""/"
HOMEPATH="${U}nobody/Code/thing"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft_surface.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAILS=0

# new_repo NAME -- a repository with one clean baseline commit and a
# `baseline` ref pointing at it. Every arm adds its files on top.
new_repo() {
  local d="$WORK/$1"
  mkdir -p "$d"
  git -C "$d" init -q 2>/dev/null || return 1
  git -C "$d" config user.email f@example.invalid
  git -C "$d" config user.name  fixture
  git -C "$d" config commit.gpgsign false
  printf 'a harness, and nothing private in it\n' > "$d/README.md"
  git -C "$d" add -- README.md
  git -C "$d" commit -q -m baseline
  git -C "$d" branch -f baseline HEAD
  git -C "$d" remote add origin https://example.invalid/x.git
  printf '%s' "$d"
}

# commit_added DIR -- stage everything the arm wrote and commit it, so the
# added files are TRACKED (the public surface is the tracked set).
commit_added() {
  git -C "$1" add -A -- .
  git -C "$1" commit -q -m added 2>/dev/null || true
}

# run_arm LABEL DIR WANT_RC [extra args...]
run_arm() {
  local label="$1" dir="$2" want="$3"; shift 3
  local out rc
  out="$(python3 "$LINT" --surface --repo "$dir" --baseline baseline \
           --class "userpath=F:${U}" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "UNMEASURED: arm $label could not run: $out" >&2
    exit 2
  fi
  if [ "$rc" -ne "$want" ]; then
    printf 'FAIL arm %s: wanted exit %s, got %s\n' "$label" "$want" "$rc"
    printf '%s\n' "$out" | sed 's/^/    /'
    FAILS=$((FAILS + 1))
  else
    printf 'ok   arm %s: exit %s as wanted\n' "$label" "$rc"
  fi
}

# --- A. a plain added file carrying a home path -----------------------------
D="$(new_repo A)" || { echo "UNMEASURED: git init failed" >&2; exit 2; }
mkdir -p "$D/runs"
printf 'the run wrote into %s/out\n' "$HOMEPATH" > "$D/runs/note.md"
commit_added "$D"
run_arm A "$D" 1

# --- B. a transformation rule that names what it replaces -------------------
D="$(new_repo B)"
mkdir -p "$D/scripts"
printf '{"id":"path-transform/v1","pattern":"%s","replacement":"<LOCAL_ROOT>"}' \
  "$HOMEPATH" > "$D/scripts/rule.json"
commit_added "$D"
run_arm B "$D" 0

# --- C. a rule carrying the string outside its own pattern/replacement ------
D="$(new_repo C)"
mkdir -p "$D/scripts"
printf '{"id":"path-transform/v1","pattern":"%ssomebodyelse","replacement":"<LOCAL_ROOT>","note":"observed at %s"}' \
  "$U" \
  "$HOMEPATH" > "$D/scripts/rule.json"
commit_added "$D"
run_arm C "$D" 1

# --- D. evidence fixed by a digest ------------------------------------------
D="$(new_repo D)"
mkdir -p "$D/runs"
printf 'ps row: 4711 1 8192 00:03 %s/bin/worker\n' "$HOMEPATH" > "$D/runs/stream.jsonl"
SHA="$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$D/runs/stream.jsonl")"
printf '{"subject":[{"name":"stream.jsonl","digest":{"sha256":"%s"}}]}\n' "$SHA" > "$D/runs/record.json"
commit_added "$D"
run_arm D "$D" 0

# --- E. the same evidence, unpinned -----------------------------------------
D="$(new_repo E)"
mkdir -p "$D/runs"
printf 'ps row: 4711 1 8192 00:03 %s/bin/worker\n' "$HOMEPATH" > "$D/runs/stream.jsonl"
printf '{"subject":[{"name":"stream.jsonl","digest":{"sha256":"%s"}}]}\n' \
  "0000000000000000000000000000000000000000000000000000000000000000" > "$D/runs/record.json"
commit_added "$D"
run_arm E "$D" 1

# --- F. the baseline count declared wrong by one ----------------------------
# The baseline itself carries one occurrence; the declaration says two. The
# already-public surface must be declared EXACTLY, not at most.
D="$(new_repo F)"
printf 'the census ran under %s\n' "$HOMEPATH" >> "$D/README.md"
git -C "$D" add -- README.md
git -C "$D" commit -q -m "baseline carries one"
git -C "$D" branch -f baseline HEAD
printf 'nothing private here\n' > "$D/other.md"
commit_added "$D"
run_arm F "$D" 1 --declare userpath=1:2

# --- G. positive control: an added file that carries nothing -----------------
D="$(new_repo G)"
mkdir -p "$D/docs"
printf 'a document about the boundary, naming nothing\n' > "$D/docs/x.md"
commit_added "$D"
run_arm G "$D" 0

# --- H. the declaration itself, carrying each class exactly ------------------
D="$(new_repo H)"
printf '{"run":"git grep -F %s"}\n' "$U" > "$D/claims.json"
commit_added "$D"
run_arm H "$D" 0 --declaration claims.json

# --- I. the declaration carrying a fact about THIS machine ------------------
# $HOME is a computed class: no declaration can name it, so the exemption that
# covered H cannot cover this. The scratch repository is deleted on exit.
D="$(new_repo I)"
printf '{"run":"git grep -F %s","seen":"%s/out"}\n' "$U" "$HOME" > "$D/claims.json"
commit_added "$D"
run_arm I "$D" 1 --declaration claims.json

# --- J/K. the separation, as one tree measured twice -------------------------
D="$(new_repo JK)"
mkdir -p "$D/runs"
printf 'the run wrote into %s/out\n' "$HOMEPATH" > "$D/runs/note.md"
commit_added "$D"
git -C "$D" remote remove origin
run_arm J "$D" 0
git -C "$D" remote add origin https://example.invalid/x.git
run_arm K "$D" 1

if [ "$FAILS" -ne 0 ]; then
  printf 'RED: %s arm(s) did not match\n' "$FAILS"
  exit 1
fi
printf 'GREEN: eleven arms, each as wanted\n'
exit 0
