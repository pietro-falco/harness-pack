#!/usr/bin/env bash
# gate_adr_contract.sh -- CONTRACT gate for ADR additions (ADR-009).
#
# RULE. No threshold, no count, no dependency on any status: field.
#   A change that ADDS a file on the ADR surface is REJECTED unless the same
#   change also touches at least one file on the MEASURED surface.
#   A change that only MODIFIES an existing ADR file is not touched by the rule.
#
# MEASURED is not "anything that is not an ADR". It is the surface this repo's
# own linters read, declared in scripts/measured_surface.conf as the same globs
# tests/run_tests.sh hands to shellcheck and py_compile. Without that the rule
# is satisfied by touching a README, and the gate is decoration.
#
# The declaration is data and this file is its reader. Parity between the
# declaration and run_tests.sh, and between this matcher and the shell's own
# expansion, is asserted by tests/gate_adr_contract_fixture.sh. A gate that
# re-derives its own reference set certifies nothing.
#
# GLOB FORM: <dir>/<pattern>, dir literal, pattern free of '/'. That is what a
# shell glob means and it is NOT what `case` means -- `case scripts/lib/x.sh in
# scripts/*.sh)` matches, while `echo scripts/*.sh` never lists that file. Any
# other form is refused rather than silently mis-modelled.
#
# DECLARED RESIDUE, each with a named fixture case:
#   R1 an ADR addition riding with a comment-only edit to a measured file passes.
#      This gate reads paths, not diffs.
#   R2 a commit with more than one parent is out of scope in --commit mode.
#   R3 a rename or copy whose DESTINATION lands on the ADR surface counts as an
#      addition. A deletion never does.
#   R4 the linters expand their globs over the WORKING TREE, so an untracked file
#      can be linted and is still not on this surface. --list-measured reports
#      tracked files only, on purpose: a declaration that moves with an untracked
#      file is not a declaration.
#
# USAGE
#   gate_adr_contract.sh --staged
#   gate_adr_contract.sh --commit <rev>
#   gate_adr_contract.sh --list-measured
#   ADR_GATE_CONF=<path>  overrides the declaration
#
# EXIT  0 accepted (rule silent or satisfied) · 1 contract violation
#       2 usage error, or declaration missing / malformed / empty
#
# NEVER read this gate through a pipe. `gate | tail; echo $?` reports tail's
# exit: measured EXIT=0 through a pipe against GATE_EXIT=2 without one.
#
# An error detector, not a boundary: a local hook inherits the sandbox of the
# session that launches it. The boundary is pre-receive or CI.

set -u

PROG=${0##*/}
CONF_DEFAULT="scripts/measured_surface.conf"

die2() { printf '%s: %s\n' "$PROG" "$1" >&2; exit 2; }

mode=""
rev=""
case "${1-}" in
  --staged)        [ $# -eq 1 ] || die2 "usage: $PROG --staged"; mode=staged ;;
  --commit)        [ $# -eq 2 ] || die2 "usage: $PROG --commit <rev>"; mode=commit; rev=$2 ;;
  --list-measured) [ $# -eq 1 ] || die2 "usage: $PROG --list-measured"; mode=list ;;
  *) die2 "usage: $PROG --staged | --commit <rev> | --list-measured" ;;
esac

: # MUT-ACCEPT

root=$(git rev-parse --show-toplevel 2>/dev/null) || die2 "not inside a git work tree"
[ -n "$root" ] || die2 "not inside a git work tree"

conf=${ADR_GATE_CONF:-$CONF_DEFAULT}
case "$conf" in /*) : ;; *) conf="$root/$conf" ;; esac
[ -f "$conf" ] || die2 "declaration not found: $conf"

version=""
adr_prefix=""
GDIR=()
GPAT=()
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  key=${line%% *}
  val=${line#"$key"}
  while [ "${val# }" != "$val" ]; do val=${val# }; done
  case "$key" in
    VERSION)    version=$val ;;
    ADR_PREFIX) adr_prefix=$val ;;
    GLOB)
      [ -n "$val" ] || die2 "empty GLOB entry in $conf"
      case "$val" in */*) : ;; *) die2 "GLOB must be <dir>/<pattern>: $val" ;; esac
      gdir=${val%/*}
      gpat=${val##*/}
      [ -n "$gpat" ] || die2 "GLOB has an empty pattern: $val"
      case "$gdir" in *[*?[]*) die2 "GLOB directory part must be literal: $val" ;; esac
      GDIR[${#GDIR[@]}]=$gdir
      GPAT[${#GPAT[@]}]=$gpat
      ;;
    *) : ;;
  esac
done < "$conf"

[ "$version" = "1" ] || die2 "declaration VERSION must be 1, got '${version:-<none>}'"
[ -n "$adr_prefix" ] || die2 "declaration has no ADR_PREFIX"
case "$adr_prefix" in */) : ;; *) die2 "ADR_PREFIX must end with '/': $adr_prefix" ;; esac
[ "${#GDIR[@]}" -gt 0 ] || die2 "declared MEASURED surface is empty"  # MUT-EMPTY

on_surface() {
  local p=$1 i pdir pbase
  case "$p" in
    */*) pdir=${p%/*}; pbase=${p##*/} ;;
    *)   pdir="."; pbase=$p ;;
  esac
  i=0
  while [ "$i" -lt "${#GDIR[@]}" ]; do
    if [ "$pdir" = "${GDIR[$i]}" ]; then  # MUT-DIRBLIND
      # shellcheck disable=SC2254  # the declared pattern IS the glob; quoting it would kill the match
      case "$pbase" in ${GPAT[$i]}) return 0 ;; esac
    fi
    i=$((i + 1))
  done
  return 1  # MUT-MEASURED
}

tmp=$(mktemp "${TMPDIR:-/tmp}/adrgate.XXXXXX") || die2 "mktemp failed"
trap 'rm -f "$tmp"' EXIT INT TERM

if [ "$mode" = list ]; then
  git -C "$root" ls-files > "$tmp" || die2 "git ls-files failed"
  while IFS= read -r f || [ -n "$f" ]; do
    [ -n "$f" ] || continue
    if on_surface "$f"; then printf '%s\n' "$f"; fi
  done < "$tmp"
  exit 0
fi

if [ "$mode" = staged ]; then
  git -C "$root" diff --cached -M --no-ext-diff --name-status -z > "$tmp"
  rc=$?
else
  parents=$(git -C "$root" rev-list -n 1 --parents "$rev" --) || die2 "unknown rev: $rev"
  rest=${parents#* }
  if [ "$rest" != "$parents" ] && [ "${rest#* }" != "$rest" ]; then
    exit 0
  fi
  git -C "$root" diff-tree --no-commit-id -r -M --root --name-status -z "$rev" > "$tmp"
  rc=$?
fi
[ "$rc" -eq 0 ] || die2 "git failed while reading the change (exit $rc)"

added_adr=0
touched_measured=0
while IFS= read -r -d '' st; do
  IFS= read -r -d '' p1 || die2 "truncated name-status stream"
  p2=""
  case "$st" in
    R*|C*) IFS= read -r -d '' p2 || die2 "truncated name-status stream" ;;
  esac
  dest=$p1
  if [ -n "$p2" ]; then dest=$p2; fi
  is_add=0
  case "$st" in
    A*)    is_add=1 ;;  # MUT-A
    R*|C*) is_add=1 ;;  # MUT-R
    M*)    is_add=0 ;;  # MUT-M
  esac
  if [ "$is_add" -eq 1 ]; then
    case "$dest" in "$adr_prefix"*) added_adr=1 ;; esac
  fi
  if on_surface "$p1"; then touched_measured=1; fi
  if [ -n "$p2" ] && on_surface "$p2"; then touched_measured=1; fi
done < "$tmp"

if [ "$added_adr" -eq 0 ]; then exit 0; fi
if [ "$touched_measured" -eq 1 ]; then exit 0; fi

printf '%s: rejected: adds a file under %s and touches no file on the measured surface declared in %s\n' \
  "$PROG" "$adr_prefix" "$conf" >&2
exit 1
