#!/usr/bin/env bash
#
# Test atomic installation with shimmed curl and wget.
#
set -euo pipefail

# --- setup ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

INSTALL_SCRIPT="${REPO_ROOT}/install.sh"
STATUSLINE_NAME="urda-com-forged-statusline.sh"

if [[ ! -r "${INSTALL_SCRIPT}" ]]; then
  echo "error: install script not found or unreadable: ${INSTALL_SCRIPT}" >&2
  exit 1
fi

# Shim behavior is selected through FSL_TEST_*_MODE.
BASH_BIN="$(command -v bash)"
SHIM_DIR="$(mktemp -d)"
WGET_JAIL="$(mktemp -d)"
NODL_JAIL="$(mktemp -d)"
cleanup() {
  rm -rf "${SHIM_DIR}" "${WGET_JAIL}" "${NODL_JAIL}"
}
trap cleanup EXIT

cat > "${SHIM_DIR}/curl" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

# Exact argv shape, release URL included: a URL typo must not ship behind a
# green suite, and a decoy option operand must not masquerade as the URL.
if [[ $# -ne 4 || "${1}" != "-fsSL" \
   || "${2}" != "https://raw.githubusercontent.com/urda/forged-statusline/release/urda-com-forged-statusline.sh" \
   || "${3}" != "-o" || -z "${4}" ]]; then
  printf 'curl shim: unexpected argv: %s\n' "$*" >&2
  exit 22
fi
OUT="${4}"

case "${FSL_TEST_CURL_MODE:-good}" in
  partial)
    printf '#!/usr/bin/env bash\necho "incomple' > "${OUT}"
    exit 28
    ;;
  garbage)
    printf '<html><body>404 Not Found</body></html>\n' > "${OUT}"
    exit 0
    ;;
  wrong-script)
    printf '#!/usr/bin/env bash\necho this-is-not-the-renderer\n' > "${OUT}"
    exit 0
    ;;
  wrong-404)
    printf '404 Not Found\n' > "${OUT}"
    exit 0
    ;;
  marker-in-comment)
    printf '#!/usr/bin/env bash\n# see URDA_AI_FORGED_STATUS_LINE_VERSION= in the real renderer\necho this-is-not-the-renderer-either\n' > "${OUT}"
    exit 0
    ;;
  self-file)
    cat "${FSL_SELF_FILE}" > "${OUT}"
    exit 0
    ;;
  truncated)
    # Every anchor present, but cut short before the renderer's closing line.
    printf '#!/usr/bin/env bash\nURDA_AI_FORGED_STATUS_LINE_VERSION="1.0.0"\nupdate_check() {\n  :\n}\necho "shimmed ok"\n' > "${OUT}"
    exit 0
    ;;
  good)
    printf '#!/usr/bin/env bash\nURDA_AI_FORGED_STATUS_LINE_VERSION="1.0.0"\nupdate_check() {\n  :\n}\necho "shimmed ok"\nexit 0\n' > "${OUT}"
    exit 0
    ;;
  *)
    printf 'curl shim: unknown FSL_TEST_CURL_MODE=%s\n' "${FSL_TEST_CURL_MODE:-}" >&2
    exit 1
    ;;
esac
SHIM
chmod +x "${SHIM_DIR}/curl"

# The curl-free jail uses POSIX sh because it has no env/bash.
for tool in bash mktemp head tail grep chmod mv rm cat; do
  ln -s "$(command -v "${tool}")" "${WGET_JAIL}/${tool}"
  ln -s "$(command -v "${tool}")" "${NODL_JAIL}/${tool}"
done

cat > "${WGET_JAIL}/wget" <<'WGET_SHIM'
#!/bin/sh
# Exact argv shape, release URL included: a URL typo must not ship behind a
# green suite, and a decoy option operand must not masquerade as the URL.
if [ "$#" -ne 3 ] || [ "$1" != "-qO" ] || [ -z "$2" ] \
   || [ "$3" != "https://raw.githubusercontent.com/urda/forged-statusline/release/urda-com-forged-statusline.sh" ]; then
  printf 'wget shim: unexpected argv: %s\n' "$*" >&2
  exit 8
fi
OUT="${2}"

case "${FSL_TEST_WGET_MODE:-good}" in
  partial)
    printf '#!/usr/bin/env bash\necho "incomple' > "${OUT}"
    exit 4
    ;;
  good)
    printf '#!/usr/bin/env bash\nURDA_AI_FORGED_STATUS_LINE_VERSION="1.0.0"\nupdate_check() {\n  :\n}\necho "shimmed ok"\nexit 0\n' > "${OUT}"
    exit 0
    ;;
  *)
    printf 'wget shim: unknown FSL_TEST_WGET_MODE=%s\n' "${FSL_TEST_WGET_MODE:-}" >&2
    exit 1
    ;;
esac
WGET_SHIM
chmod +x "${WGET_JAIL}/wget"

# --- harness -------------------------------------------------------------

C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'

PASS_COUNT=0
FAIL_COUNT=0

run_case() {
  #   run_case <label> <curl|wget> <mode> <expect-success> [<expect-stderr>]
  local LABEL="${1}"
  local DOWNLOADER="${2}"
  local MODE="${3}"
  local EXPECT_SUCCESS="${4}"
  local EXPECT_STDERR="${5:-}"

  local TEST_HOME DEST_DIR DEST BACKUP ERR_FILE
  ERR_FILE="$(mktemp)"
  TEST_HOME="$(mktemp -d)"
  DEST_DIR="${TEST_HOME}/.claude"
  mkdir -p "${DEST_DIR}"
  DEST="${DEST_DIR}/${STATUSLINE_NAME}"

  printf '#!/usr/bin/env bash\necho "pre-existing good copy"\n' > "${DEST}"
  chmod +x "${DEST}"

  BACKUP="$(mktemp)"
  cp "${DEST}" "${BACKUP}"

  local FAILED="false"
  local REASON=""

  # Guard expected failures from the suite's set -e.
  local EXIT_CODE
  if [[ "${DOWNLOADER}" == "wget" ]]; then
    if PATH="${WGET_JAIL}" HOME="${TEST_HOME}" FSL_TEST_WGET_MODE="${MODE}" \
        "${BASH_BIN}" "${INSTALL_SCRIPT}" >/dev/null 2>"${ERR_FILE}"; then
      EXIT_CODE=0
    else
      EXIT_CODE=$?
    fi
  elif [[ "${DOWNLOADER}" == "none" ]]; then
    if PATH="${NODL_JAIL}" HOME="${TEST_HOME}" \
        "${BASH_BIN}" "${INSTALL_SCRIPT}" >/dev/null 2>"${ERR_FILE}"; then
      EXIT_CODE=0
    else
      EXIT_CODE=$?
    fi
  else
    if PATH="${SHIM_DIR}:${PATH}" HOME="${TEST_HOME}" FSL_TEST_CURL_MODE="${MODE}" \
        FSL_SELF_FILE="${SCRIPT_DIR}/test-install.sh" \
        bash "${INSTALL_SCRIPT}" >/dev/null 2>"${ERR_FILE}"; then
      EXIT_CODE=0
    else
      EXIT_CODE=$?
    fi
  fi

  if [[ "${EXPECT_SUCCESS}" == "true" && "${EXIT_CODE}" -ne 0 ]]; then
    FAILED="true"
    REASON="expected install.sh to exit 0, got ${EXIT_CODE}"
  elif [[ "${EXPECT_SUCCESS}" == "false" && "${EXIT_CODE}" -eq 0 ]]; then
    FAILED="true"
    REASON="expected install.sh to exit non-zero, got 0"
  fi

  if [[ "${FAILED}" == "false" ]]; then
    if [[ "${EXPECT_SUCCESS}" == "true" ]]; then
      if cmp -s "${DEST}" "${BACKUP}"; then
        FAILED="true"
        REASON="DEST was not replaced (still matches the pre-existing copy)"
      elif ! grep -q 'shimmed ok' "${DEST}"; then
        FAILED="true"
        REASON="DEST does not contain the expected shimmed content"
      fi
    else
      if ! cmp -s "${DEST}" "${BACKUP}"; then
        FAILED="true"
        REASON="DEST was modified; expected it untouched after a failed download"
      fi
    fi
  fi

  # A silent failure leaves the user with no idea what went wrong.
  if [[ "${FAILED}" == "false" && -n "${EXPECT_STDERR}" ]]; then
    if ! grep -qF "${EXPECT_STDERR}" "${ERR_FILE}"; then
      FAILED="true"
      REASON="expected stderr to mention \"${EXPECT_STDERR}\", got: $(tr '\n' ' ' < "${ERR_FILE}")"
    fi
  fi

  if [[ "${FAILED}" == "false" ]]; then
    local LEFTOVERS
    shopt -s nullglob
    LEFTOVERS=("${DEST_DIR}"/."${STATUSLINE_NAME}".*)
    shopt -u nullglob
    if [[ ${#LEFTOVERS[@]} -ne 0 ]]; then
      FAILED="true"
      REASON="temp file(s) left behind: ${LEFTOVERS[*]}"
    fi
  fi

  if [[ "${FAILED}" == "true" ]]; then
    printf '%s[FAIL]%s %s - %s\n' "${C_RED}" "${C_RESET}" "${LABEL}" "${REASON}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    printf '%s[PASS]%s %s\n' "${C_GREEN}" "${C_RESET}" "${LABEL}"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi

  rm -rf "${TEST_HOME}"
  rm -f "${BACKUP}" "${ERR_FILE}"
}

host_case() {
  #   host_case <label> <dest-subdir> <expect-success> [<expect-stderr>] [<flag>...]
  # Clean install into a host directory: no pre-existing copy, so success
  # also asserts the installed file exists and is executable. An empty
  # subdir skips creating the host directory to test the missing-host abort.
  local LABEL="${1}" SUBDIR="${2}" EXPECT_SUCCESS="${3}" EXPECT_STDERR="${4:-}"
  shift 4 || shift $#

  local TEST_HOME DEST ERR_FILE OUT_FILE EXPECT_FILE EXIT_CODE
  local FAILED="false" REASON=""
  ERR_FILE="$(mktemp)"
  OUT_FILE="$(mktemp)"
  EXPECT_FILE="$(mktemp)"
  TEST_HOME="$(mktemp -d)"
  if [[ -n "${SUBDIR}" ]]; then
    mkdir -p "${TEST_HOME}/${SUBDIR}"
  fi
  DEST="${TEST_HOME}/${SUBDIR}/${STATUSLINE_NAME}"

  if PATH="${SHIM_DIR}:${PATH}" HOME="${TEST_HOME}" FSL_TEST_CURL_MODE="good" \
      bash "${INSTALL_SCRIPT}" "$@" >"${OUT_FILE}" 2>"${ERR_FILE}"; then
    EXIT_CODE=0
  else
    EXIT_CODE=$?
  fi

  if [[ "${EXPECT_SUCCESS}" == "true" ]]; then
    if [[ "${EXIT_CODE}" -ne 0 ]]; then
      FAILED="true"
      REASON="expected install.sh to exit 0, got ${EXIT_CODE}: $(tr '\n' ' ' < "${ERR_FILE}")"
    elif [[ ! -f "${DEST}" ]]; then
      FAILED="true"
      REASON="expected ${DEST} to exist after a clean install"
    elif [[ ! -x "${DEST}" ]]; then
      FAILED="true"
      REASON="installed file is not executable"
    elif ! grep -q 'shimmed ok' "${DEST}"; then
      FAILED="true"
      REASON="installed file does not contain the expected shimmed content"
    else
      # Exact stdout: the printed snippet is the manual enable step.
      local EXPECT_OUT
      if [[ "${SUBDIR}" == ".claude" ]]; then
        EXPECT_OUT="Installed ${STATUSLINE_NAME} -> ${DEST}

Add this to ~/${SUBDIR}/settings.json to enable it:

  \"statusLine\": {
    \"command\": \"~/${SUBDIR}/${STATUSLINE_NAME}\",
    \"padding\": 0,
    \"refreshInterval\": 20,
    \"type\": \"command\"
  }"
      else
        EXPECT_OUT="Installed ${STATUSLINE_NAME} -> ${DEST}

Add this to ~/${SUBDIR}/settings.json to enable it:

  \"statusLine\": {
    \"type\": \"command\",
    \"command\": \"~/${SUBDIR}/${STATUSLINE_NAME}\"
  }"
      fi
      # printf '%s\n' restores the terminal newline cat's $() would eat.
      printf '%s\n' "${EXPECT_OUT}" > "${EXPECT_FILE}"
      if ! cmp -s "${OUT_FILE}" "${EXPECT_FILE}"; then
        FAILED="true"
        REASON="stdout does not byte-exactly match the expected ${SUBDIR} install output"
      fi
    fi
  else
    if [[ "${EXIT_CODE}" -eq 0 ]]; then
      FAILED="true"
      REASON="expected install.sh to exit non-zero, got 0"
    elif [[ -e "${DEST}" ]]; then
      FAILED="true"
      REASON="rejected install still created ${DEST}"
    fi
  fi

  if [[ "${FAILED}" == "false" && -n "${EXPECT_STDERR}" ]]; then
    if ! grep -qF "${EXPECT_STDERR}" "${ERR_FILE}"; then
      FAILED="true"
      REASON="expected stderr to mention \"${EXPECT_STDERR}\", got: $(tr '\n' ' ' < "${ERR_FILE}")"
    fi
  fi

  if [[ "${FAILED}" == "true" ]]; then
    printf '%s[FAIL]%s %s - %s\n' "${C_RED}" "${C_RESET}" "${LABEL}" "${REASON}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    printf '%s[PASS]%s %s\n' "${C_GREEN}" "${C_RESET}" "${LABEL}"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi

  rm -rf "${TEST_HOME}"
  rm -f "${ERR_FILE}" "${OUT_FILE}" "${EXPECT_FILE}"
}

# --- cases -------------------------------------------------------------------

run_case "curl interruption preserves destination" \
  "curl" "partial" "false"

run_case "HTML response preserves destination" \
  "curl" "garbage" "false"

run_case "unrelated Bash preserves destination" \
  "curl" "wrong-script" "false"

run_case "bare 404 preserves destination" \
  "curl" "wrong-404" "false"

run_case "commented marker preserves destination" \
  "curl" "marker-in-comment" "false"

run_case "unanchored marker preserves destination" \
  "curl" "self-file" "false"

run_case "truncated renderer preserves destination" \
  "curl" "truncated" "false"

run_case "curl success replaces destination" \
  "curl" "good" "true"

run_case "wget success replaces destination" \
  "wget" "good" "true"

run_case "wget interruption preserves destination and reports why" \
  "wget" "partial" "false" "failed to download"

run_case "no downloader aborts and preserves destination" \
  "none" "none" "false" "need curl or wget"

host_case "clean install works with no prior copy" \
  ".claude" "true" ""
host_case "--agy installs into the Antigravity CLI home" \
  ".gemini/antigravity-cli" "true" "" --agy
host_case "--copilot installs into the Copilot home" \
  ".copilot" "true" "" --copilot
host_case "unknown flag is rejected" \
  ".claude" "false" "unknown option" --bogus
host_case "two host flags are rejected" \
  ".claude" "false" "too many arguments" --agy --copilot
host_case "missing host directory aborts before downloading" \
  "" "false" "not found" --agy

mvfail_case() {
  #   mvfail_case <label>
  # Fault-inject the final swap: with mv failing, only a truly atomic
  # replacement leaves the pre-existing executable copy untouched.
  local LABEL="${1}"
  local TEST_HOME DEST_DIR DEST BACKUP MV_JAIL EXIT_CODE
  local FAILED="false" REASON=""
  TEST_HOME="$(mktemp -d)"
  DEST_DIR="${TEST_HOME}/.claude"
  mkdir -p "${DEST_DIR}"
  DEST="${DEST_DIR}/${STATUSLINE_NAME}"
  printf '#!/usr/bin/env bash\necho "pre-existing good copy"\n' > "${DEST}"
  chmod +x "${DEST}"
  BACKUP="$(mktemp)"
  cp "${DEST}" "${BACKUP}"
  MV_JAIL="$(mktemp -d)"
  printf '#!/bin/sh\nexit 1\n' > "${MV_JAIL}/mv"
  chmod +x "${MV_JAIL}/mv"

  if PATH="${MV_JAIL}:${SHIM_DIR}:${PATH}" HOME="${TEST_HOME}" FSL_TEST_CURL_MODE="good" \
      bash "${INSTALL_SCRIPT}" >/dev/null 2>&1; then
    EXIT_CODE=0
  else
    EXIT_CODE=$?
  fi

  if [[ "${EXIT_CODE}" -eq 0 ]]; then
    FAILED="true"
    REASON="expected install.sh to exit non-zero on a failed mv, got 0"
  elif ! cmp -s "${DEST}" "${BACKUP}"; then
    FAILED="true"
    REASON="DEST changed despite a failed mv; must stay byte-identical"
  elif [[ ! -x "${DEST}" ]]; then
    FAILED="true"
    REASON="DEST lost its execute bit after a failed mv"
  fi

  if [[ "${FAILED}" == "false" ]]; then
    local LEFTOVERS
    shopt -s nullglob
    LEFTOVERS=("${DEST_DIR}"/."${STATUSLINE_NAME}".*)
    shopt -u nullglob
    if [[ ${#LEFTOVERS[@]} -ne 0 ]]; then
      FAILED="true"
      REASON="temp file(s) left behind: ${LEFTOVERS[*]}"
    fi
  fi

  if [[ "${FAILED}" == "true" ]]; then
    printf '%s[FAIL]%s %s - %s\n' "${C_RED}" "${C_RESET}" "${LABEL}" "${REASON}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    printf '%s[PASS]%s %s\n' "${C_GREEN}" "${C_RESET}" "${LABEL}"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi

  rm -rf "${TEST_HOME}" "${MV_JAIL}"
  rm -f "${BACKUP}"
}
mvfail_case "failed swap preserves the installed copy byte-for-byte"

dirdest_case() {
  #   dirdest_case <label>
  # A directory at the destination must be an explicit refusal, never an
  # exit-0 "Installed" that leaves the configured path as a directory.
  local LABEL="${1}"
  local TEST_HOME DEST_DIR DEST EXIT_CODE ERR_FILE
  local FAILED="false" REASON=""
  TEST_HOME="$(mktemp -d)"
  DEST_DIR="${TEST_HOME}/.claude"
  DEST="${DEST_DIR}/${STATUSLINE_NAME}"
  mkdir -p "${DEST}"
  printf 'user data' > "${DEST}/keepsake"
  ERR_FILE="$(mktemp)"

  if PATH="${SHIM_DIR}:${PATH}" HOME="${TEST_HOME}" FSL_TEST_CURL_MODE="good" \
      bash "${INSTALL_SCRIPT}" >/dev/null 2>"${ERR_FILE}"; then
    EXIT_CODE=0
  else
    EXIT_CODE=$?
  fi

  if [[ "${EXIT_CODE}" -eq 0 ]]; then
    FAILED="true"
    REASON="expected install.sh to refuse a directory destination, got exit 0"
  elif ! grep -qF "is a directory" "${ERR_FILE}"; then
    FAILED="true"
    REASON="expected stderr to say the destination is a directory, got: $(tr '\n' ' ' < "${ERR_FILE}")"
  elif [[ ! -d "${DEST}" || "$(cat "${DEST}/keepsake" 2>/dev/null)" != "user data" ]]; then
    FAILED="true"
    REASON="the directory or its contents were touched; refusal must not modify anything"
  elif [[ -n "$(find "${DEST_DIR}" -name ".${STATUSLINE_NAME}.*" 2>/dev/null)" ]]; then
    FAILED="true"
    REASON="temp download left behind despite the refusal"
  fi

  if [[ "${FAILED}" == "true" ]]; then
    printf '%s[FAIL]%s %s - %s\n' "${C_RED}" "${C_RESET}" "${LABEL}" "${REASON}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    printf '%s[PASS]%s %s\n' "${C_GREEN}" "${C_RESET}" "${LABEL}"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi

  rm -rf "${TEST_HOME}"
  rm -f "${ERR_FILE}"
}
dirdest_case "directory at the destination is refused untouched"

# --- summary -------------------------------------------------------------

printf '\n%d passed, %d failed\n' "${PASS_COUNT}" "${FAIL_COUNT}"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
