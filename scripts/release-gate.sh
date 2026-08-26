#!/usr/bin/env bash
#
# Assert this tree is ready to merge into release.
#
# No `set -e`: every check runs to the end, so one red line never hides the
# next. The exit status comes from the failure count.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

# --- harness ----------------------------------------------------------------

C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf "%s[PASS]%s %s\n" "${C_GREEN}" "${C_RESET}" "${1}"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
}

fail() {
  printf "%s[FAIL]%s %s\n" "${C_RED}" "${C_RESET}" "${1}"
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
}

# Every check below builds a pattern or a tag name out of this string, so a
# malformed file has to stop here. It cannot reach awk or grep as garbage.
VERSION="$(cat VERSION 2>/dev/null)"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "VERSION is not a three-part version: '${VERSION}'"
  printf "\n0 passed, 1 failed of 1.\n"
  exit 1
fi

TAG="v${VERSION}"
# The dots are literal in every grep below.
ESCAPED="${VERSION//./\\.}"

# --- 1. VERSION agrees with the renderer ------------------------------------

if out="$(make -s version-check 2>&1)"; then
  pass "${out}"
else
  fail "${out}"
fi

# --- 2. VERSION is above the release branch ---------------------------------

# origin/release is the shipped truth and is never force-pushed, so the gate
# always fetches it instead of trusting a local ref.
released=""
if git fetch --no-tags --quiet origin release 2>/dev/null; then
  released="$(git show FETCH_HEAD:VERSION 2>/dev/null)"
fi

if [[ -z "${released}" ]]; then
  fail "cannot read VERSION from origin/release"
elif [[ "${VERSION}" == "${released}" ]]; then
  fail "VERSION is still ${released}: bump it before releasing"
else
  highest="$(printf '%s\n%s\n' "${released}" "${VERSION}" | sort -V | tail -1)"
  if [[ "${highest}" != "${VERSION}" ]]; then
    fail "VERSION ${VERSION} is not above released ${released}"
  else
    pass "version ${released} -> ${VERSION}"
  fi
fi

# --- 3. Any pushed tag for this version belongs to this history -------------

# Tagging before the release merge is the normal order, so an existing tag is
# not a failure by itself. A tag on a commit this branch does not contain is:
# that number is spent on other work, and a pushed tag never moves.
# An unreachable origin is a failure, not an absent tag: empty output from a
# broken ls-remote would otherwise read as "unused" and pass on its own error.
if ! remote_tag="$(git ls-remote --tags origin "refs/tags/${TAG}" 2>/dev/null)"; then
  fail "cannot reach origin to look up ${TAG}"
elif [[ -z "${remote_tag}" ]]; then
  pass "${TAG} is unused on origin"
else
  git fetch --force --quiet origin "refs/tags/${TAG}:refs/tags/${TAG}" 2>/dev/null
  if git merge-base --is-ancestor "${TAG}^{commit}" HEAD 2>/dev/null; then
    pass "${TAG} points into this history"
  else
    fail "${TAG} is already pushed on another commit: roll forward instead"
  fi
fi

# --- 4. The CHANGELOG has a dated heading for this version ------------------

if grep -Eq "^## \[${ESCAPED}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md; then
  pass "CHANGELOG has a dated [${VERSION}] heading"
else
  fail "CHANGELOG.md has no dated '## [${VERSION}]' heading"
fi

# --- 5. That section carries real notes -------------------------------------

# Take the lines between this heading and the next one. A heading with nothing
# under it passes every pattern check and still ships an empty release note.
# The match is literal: awk -v mangles a backslash escape differently across
# awk implementations, so no regex reaches it.
notes="$(awk -v head="## [${VERSION}] - " '
  inside && index($0, "## ") == 1 { exit }
  inside { print }
  index($0, head) == 1 { inside = 1 }
' CHANGELOG.md)"

if grep -Eq '^- ' <<< "${notes}"; then
  pass "the [${VERSION}] section has notes"
else
  fail "the [${VERSION}] section has no '- ' notes"
fi

# --- 6. The link reference targets this tag ---------------------------------

# The line gets copied from the release above it, so a stale target survives a
# plain "does the line exist" check.
link="$(grep -E "^\[${ESCAPED}\]: " CHANGELOG.md | head -1)"
if [[ -z "${link}" ]]; then
  fail "CHANGELOG.md has no '[${VERSION}]:' link reference"
elif [[ "${link}" == *"/releases/tag/${TAG}" ]]; then
  pass "the [${VERSION}] link targets ${TAG}"
else
  fail "the [${VERSION}] link does not end in /releases/tag/${TAG}"
fi

# --- summary ----------------------------------------------------------------

TOTAL=$(( PASS_COUNT + FAIL_COUNT ))
printf "\n%d passed, %d failed of %d.\n" "${PASS_COUNT}" "${FAIL_COUNT}" "${TOTAL}"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
