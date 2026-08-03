#!/usr/bin/env bash
#
# Test the renderer with mock JSON and print passing output as a visual catalog.
#
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: ${0##*/} [STATUSLINE_PATH]

  STATUSLINE_PATH   Renderer to test; defaults to this repo's copy.
  -h, --help        Show help.
EOF
}

# --- argument parsing -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STATUSLINE="${REPO_ROOT}/urda-com-forged-statusline.sh"

# Every bar is this many cells wide, for any input. Cardinal, so it is asserted.
BAR_CELLS=8

while [[ $# -gt 0 ]]; do
  case "${1}" in
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option: ${1}" >&2
      usage
      exit 2
      ;;
    *)
      STATUSLINE="${1}"
      shift
      ;;
  esac
done

# --- preflight --------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not found on PATH" >&2
  exit 1
fi

if [[ ! -r "${STATUSLINE}" ]]; then
  echo "error: status line script not found or unreadable: ${STATUSLINE}" >&2
  exit 1
fi

# --- test harness -----------------------------------------------------------

C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'
C_DIM=$'\033[2m'

PASS_COUNT=0
FAIL_COUNT=0

strip_ansi() {
  # Match visible text instead of embedded SGR bytes.
  local ESC=$'\033'
  sed -E "s/${ESC}\[[0-9;]*m//g"
}

remove_jail() {
  #   remove_jail <dir>...
  # A detached writer recreates its state directory with mkdir -p, which can
  # land between rm's directory scan and its final rmdir. Retry instead of
  # letting one ENOTEMPTY trip the suite's set -e and kill the whole run.
  local dir i
  for dir in "$@"; do
    i=0
    while (( i < 40 )); do
      # Guard the retry itself from set -e: a losing rm is the expected case.
      rm -rf "${dir}" 2>/dev/null || true
      if [[ ! -e "${dir}" ]]; then
        break
      fi
      sleep 0.05
      i=$(( i + 1 ))
    done
  done
  return 0
}

run_case() {
  #   run_case <label> <expected> <json> [<forbidden>]
  local LABEL="${1}"
  local EXPECT="${2}"
  local JSON="${3//__HOME__/${HOME}}"
  local FORBID="${4:-}"

  # HIDE_JQ uses a minimal PATH so merged /bin systems cannot expose jq.
  local OUTPUT EXIT_CODE RENDER_PATH="${PATH}" JAIL="" BASH_BIN="bash"
  if [[ -n "${HIDE_JQ:-}" ]]; then
    JAIL="$(mktemp -d)"
    ln -s "$(command -v cat)" "${JAIL}/cat"
    ln -s "$(command -v date)" "${JAIL}/date"
    RENDER_PATH="${JAIL}"
    BASH_BIN="$(command -v bash)"
  fi
  if OUTPUT="$(printf '%s' "${JSON}" | PATH="${RENDER_PATH}" "${BASH_BIN}" "${STATUSLINE}")"; then
    EXIT_CODE=0
  else
    EXIT_CODE=$?
  fi
  if [[ -n "${JAIL}" ]]; then
    rm -rf "${JAIL}"
  fi

  local PLAIN
  PLAIN="$(printf '%s' "${OUTPUT}" | strip_ansi)"

  local FAILED="false"
  local REASON=""
  if [[ "${EXIT_CODE}" -ne 0 ]]; then
    FAILED="true"
    REASON="exited ${EXIT_CODE} (a non-zero exit blanks the real status line)"
  elif [[ -z "${OUTPUT}" ]]; then
    FAILED="true"
    REASON="produced no output (an empty line blanks the real status line)"
  elif [[ "${PLAIN}" != *"${EXPECT}"* ]]; then
    FAILED="true"
    REASON="expected output to contain \"${EXPECT}\""
  elif [[ -n "${FORBID}" && "${PLAIN}" == *"${FORBID}"* ]]; then
    FAILED="true"
    REASON="expected output NOT to contain \"${FORBID}\""
  fi

  # Avoid `(( x++ ))`: its initial status 1 would trip set -e.
  if [[ "${FAILED}" == "true" ]]; then
    printf "%s[FAIL]%s %s\n" "${C_RED}" "${C_RESET}" "${LABEL}"
    printf "       %s%s%s\n" "${C_DIM}" "${REASON}" "${C_RESET}"
    printf "       %sgot:%s\n%s\n" "${C_DIM}" "${C_RESET}" "${PLAIN}"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  else
    printf "%s[PASS]%s %s\n" "${C_GREEN}" "${C_RESET}" "${LABEL}"
    printf "       %srender:%s\n%s\n" "${C_DIM}" "${C_RESET}" "${OUTPUT}"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  fi

  printf '\n'
}

section() {
  printf "\n%s== %s ==%s\n" "${C_DIM}" "${1}" "${C_RESET}"
}

run_icon_override() {
  #   run_icon_override <label> <env_var> <override> <default_glyph> <json>
  local label="${1}" var="${2}" override="${3}" default="${4}" json="${5}"
  export "${var}=${override}"
  run_case "${label}" "${override}" "${json}" "${default}"
  unset "${var}"
}

run_theme_case() {
  #   run_theme_case <label> <theme> <needle> <forbid> <json>
  local label="${1}" theme="${2}" needle="${3}" forbid="${4}" json="${5//__HOME__/${HOME}}"

  if [[ -n "${theme}" ]]; then
    export URDA_AI_FORGED_STATUS_LINE_THEME="${theme}"
  fi

  local output exit_code
  if output="$(printf '%s' "${json}" | bash "${STATUSLINE}")"; then
    exit_code=0
  else
    exit_code=$?
  fi

  if [[ -n "${theme}" ]]; then
    unset URDA_AI_FORGED_STATUS_LINE_THEME
  fi

  local failed="false" reason=""
  if [[ "${exit_code}" -ne 0 ]]; then
    failed="true"
    reason="exited ${exit_code} (a non-zero exit blanks the real status line)"
  elif [[ -z "${output}" ]]; then
    failed="true"
    reason="produced no output (an empty line blanks the real status line)"
  elif [[ "${output}" != *"${needle}"* ]]; then
    failed="true"
    reason="expected raw output to contain the needle color bytes"
  elif [[ -n "${forbid}" && "${output}" == *"${forbid}"* ]]; then
    failed="true"
    reason="expected raw output NOT to contain the forbidden color bytes"
  fi

  if [[ "${failed}" == "true" ]]; then
    printf "%s[FAIL]%s %s\n" "${C_RED}" "${C_RESET}" "${label}"
    printf "       %s%s%s\n" "${C_DIM}" "${reason}" "${C_RESET}"
    printf "       %sgot:%s\n%s\n" "${C_DIM}" "${C_RESET}" "${output}"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  else
    printf "%s[PASS]%s %s\n" "${C_GREEN}" "${C_RESET}" "${label}"
    printf "       %srender:%s\n%s\n" "${C_DIM}" "${C_RESET}" "${output}"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  fi

  printf '\n'
}

bar_cells_case() {
  #   bar_cells_case <label> <bars> <json>
  # Measure the glyphs between the brackets: a needle cannot see a narrow bar.
  local label="${1}" want="${2}" json="${3//__HOME__/${HOME}}"
  local output got expect="${BAR_CELLS}" i failed="false" reason=""

  for (( i = 1; i < want; i++ )); do
    expect="${expect},${BAR_CELLS}"
  done

  output="$(printf '%s' "${json}" | bash "${STATUSLINE}" 2>/dev/null)"
  # The context-size badge is not built from bar glyphs, so it never matches.
  got="$(printf '%s' "${output}" | strip_ansi | perl -CS -ne '
    while (/\[([\x{2588}-\x{258F} ]+)\]/g) { push @w, length($1) }
    END { print scalar(@w) == 0 ? "none" : join(",", @w) }')"

  if [[ "${got}" != "${expect}" ]]; then
    failed="true"
    reason="bar cells are ${got}, want ${expect}"
  fi

  cache_report "${label}" "${failed}" "${reason}"
}

poisoned_env_case() {
  #   poisoned_env_case <label> <json>
  # A total parse failure must land on the seeded defaults: render with every
  # parser destination poisoned in the environment, then require exactly two
  # rows, the documented fallbacks, and no trace of any poisoned value.
  local label="${1}" json="${2}"
  local output plain rows failed="false" reason="" sentinel

  output="$(printf '%s' "${json}" | \
    HOST='EVIL-HOST' MODEL=$'EVIL-MODEL\nEVIL-ROW' CURRENT_DIR='EVIL-DIR' \
    EFFORT='EVIL-EFFORT' THINKING='true' PERCENT='77' \
    POOL='EVIL-POOL' \
    RATE_5H='97' RATE_7D='98' RESET_5H='9999999999' RESET_7D='9999999998' \
    CTX_SIZE='123456' CACHE_5H_PCT='96' CACHE_7D_PCT='95' \
    bash "${STATUSLINE}")"
  plain="$(printf '%s' "${output}" | strip_ansi)"
  rows="$(printf '%s\n' "${output}" | wc -l | tr -d ' ')"

  if [[ "${rows}" != "2" ]]; then
    failed="true"
    reason="rendered ${rows} rows, want exactly 2"
  elif [[ "${plain}" != *"(Missing Model)"* ]] || \
       [[ "${plain}" != *"(Missing Directory)"* ]] || \
       [[ "${plain}" != *"???%"* ]]; then
    failed="true"
    reason="a documented fallback is missing"
  else
    for sentinel in 'EVIL' '77%' '97%' '98%'; do
      if [[ "${plain}" == *"${sentinel}"* ]]; then
        failed="true"
        reason="poisoned \"${sentinel}\" leaked into the render"
        break
      fi
    done
  fi

  cache_report "${label}" "${failed}" "${reason}"
}

structural_case() {
  #   structural_case <label> <json> <row1> <row2>
  # Exact two-row contract, ANSI-stripped and byte-exact through files:
  # command substitution would eat trailing newlines and hide extra rows.
  local label="${1}" json="${2}" row1="${3}" row2="${4}"
  local dir rows failed="false" reason=""
  dir="$(mktemp -d)"

  printf '%s' "${json}" | \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1700000000 \
    bash "${STATUSLINE}" | strip_ansi > "${dir}/got"
  printf '%s\n%s\n' "${row1}" "${row2}" > "${dir}/want"
  rows="$(wc -l < "${dir}/got" | tr -d ' ')"

  if [[ "${rows}" != "2" ]]; then
    failed="true"
    reason="rendered ${rows} physical lines, want exactly 2"
  elif ! cmp -s "${dir}/got" "${dir}/want"; then
    failed="true"
    reason="byte-exact mismatch: got
$(cat "${dir}/got")
want
$(cat "${dir}/want")"
  fi

  rm -rf "${dir}"
  cache_report "${label}" "${failed}" "${reason}"
}

seed_completeness_case() {
  #   seed_completeness_case <label>
  # Every destination in the parser's assignment allowlist must appear in
  # the seed block: an unseeded name rides in from the caller's environment
  # whenever jq fails outright.
  local label="${1}" failed="false" reason=""
  local allowlist seeds name

  allowlist="$(sed -n 's/^ *\(HOST|[A-Z0-9_|]*\)) ;;$/\1/p' "${STATUSLINE}" | tr '|' ' ')"
  seeds="$(awk '/^# Seed every destination/,/^# Parse allowlisted/' "${STATUSLINE}")"

  if [[ -z "${allowlist}" ]]; then
    failed="true" reason="could not extract the parser allowlist"
  elif [[ -z "${seeds}" ]]; then
    failed="true" reason="could not extract the seed block"
  else
    for name in ${allowlist}; do
      if ! grep -qE "(^| )${name}=" <<<"${seeds}"; then
        failed="true" reason="parser destination ${name} is not seeded before the parse"
        break
      fi
    done
  fi

  cache_report "${label}" "${failed}" "${reason}"
}

# --- cache-writer harness ---------------------------------------------------
# Detached work settles through render_settled's inherited FIFO.

RENDER_BASH="$(command -v bash)"

render_settled() {
  #   render_settled <json> <var=val>...
  # Render with an inherited FIFO fd: the detached children inherit fd 9, so
  # the cat returns only when the renderer and every child have exited.
  # State on disk is final the moment this returns; no polling, no sleeps.
  local __json="${1}"; shift
  local __dir __pipe
  __dir="$(mktemp -d)"
  __pipe="${__dir}/settled"
  mkfifo "${__pipe}"
  env "$@" "${RENDER_BASH}" "${STATUSLINE}" <<<"${__json}" 9>"${__pipe}" >/dev/null 2>&1 &
  cat "${__pipe}" >/dev/null
  wait "$!" 2>/dev/null || true
  rm -rf "${__dir}"
}

cache_report() {
  local label="${1}" failed="${2}" reason="${3}"
  if [[ "${failed}" == "true" ]]; then
    printf "%s[FAIL]%s %s\n" "${C_RED}" "${C_RESET}" "${label}"
    printf "       %s%s%s\n\n" "${C_DIM}" "${reason}" "${C_RESET}"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  else
    printf "%s[PASS]%s %s\n\n" "${C_GREEN}" "${C_RESET}" "${label}"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  fi
}

perm_case() {
  #   perm_case <label> <file>
  # State files must land private (0600). Probe GNU stat before BSD: the BSD
  # form "succeeds" on GNU as filesystem status, so a BSD-first chain
  # captures noise on Linux, while GNU -c fails cleanly on BSD.
  local label="${1}" file="${2}" mode failed="false" reason=""
  mode="$(stat -c %a "${file}" 2>/dev/null || stat -f %Lp "${file}" 2>/dev/null)"
  if [[ ! "${mode}" =~ ^[0-7]+$ ]]; then
    failed="true"
    reason="stat probe returned no clean mode: ${mode:-<empty>}"
  elif [[ "${mode}" != "600" ]]; then
    failed="true"
    reason="mode ${mode}, want 600"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

cache_write_case() {
  #   cache_write_case <label> <now> <basename> <json> <pair>...
  local label="${1}" now="${2}" base="${3}" json="${4//__HOME__/${HOME}}"
  shift 4
  local jail file got pair filter expect failed="false" reason=""
  jail="$(mktemp -d)"
  render_settled "${json}" \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW="${now}"
  file="${jail}/${base}"
  if [[ -f "${file}" ]]; then
    for pair in "$@"; do
      filter="${pair%%=*}"
      expect="${pair#*=}"
      got="$(jq -r "${filter}" "${file}" 2>/dev/null)" || got="<jq-error>"
      if [[ "${got}" != "${expect}" ]]; then
        failed="true"
        reason="${filter} expected ${expect}, got ${got}"
        break
      fi
    done
  else
    failed="true"
    reason="cache file ${base} never appeared"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

cache_nowrite_case() {
  #   cache_nowrite_case <label> <gate> <json>
  local label="${1}" gate="${2}" json="${3//__HOME__/${HOME}}"
  local jail failed="false" reason=""
  jail="$(mktemp -d)"
  if [[ -n "${gate}" ]]; then
    render_settled "${json}" \
      URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE="${gate}" \
      URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}"
  else
    render_settled "${json}" \
      URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}"
  fi
  if [[ -n "$(ls -A "${jail}" 2>/dev/null)" ]]; then
    failed="true"
    reason="expected no cache file written, jail is non-empty"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

cache_fidelity_case() {
  #   cache_fidelity_case <label> <json>
  local label="${1}" json="${2//__HOME__/${HOME}}"
  local jail on off failed="false" reason=""
  jail="$(mktemp -d)"
  off="$(URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1000000000 bash "${STATUSLINE}" <<<"${json}")"
  on="$(URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1000000000 bash "${STATUSLINE}" <<<"${json}")"
  remove_jail "${jail}"
  if [[ "${on}" != "${off}" ]]; then
    failed="true"
    reason="gate-on stdout differs from gate-off stdout"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

cache_monotonic_case() {
  #   cache_monotonic_case <label>
  local label="${1}"
  local jail file failed="false" reason="" got_reset got_pct
  jail="$(mktemp -d)"
  file="${jail}/cache-claude.json"
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1789448400}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":99,"resets_at":1789000000}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  got_reset="$(jq -r '.rate_5h_reset' "${file}" 2>/dev/null)" || got_reset="<jq-error>"
  got_pct="$(jq -r '.rate_5h_pct' "${file}" 2>/dev/null)" || got_pct="<jq-error>"
  if [[ "${got_reset}" != "1789448400" || "${got_pct}" != "40" ]]; then
    failed="true"
    reason="stale write regressed the window: reset=${got_reset} pct=${got_pct} (want 1789448400 / 40)"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

cache_second_case() {
  #   cache_second_case <label> <json1> <json2> <filter> <expect>
  # Render twice into one jail and judge the surviving cache with a jq filter.
  local label="${1}" json1="${2}" json2="${3}" filter="${4}" expect="${5}"
  local jail file failed="false" reason="" got
  jail="$(mktemp -d)"
  file="${jail}/cache-claude.json"
  render_settled "${json1}" \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  render_settled "${json2}" \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  got="$(jq -r "${filter}" "${file}" 2>/dev/null)" || got="<jq-error>"
  if [[ "${got}" != "${expect}" ]]; then
    failed="true"
    reason="${filter} is ${got}, want ${expect}"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

cache_seeded_reader_case() {
  #   cache_seeded_reader_case <label> <seed_json> <json> <filter> <expect>
  # Seed the cache file directly with values the writer could never produce,
  # then render once: the reader's bounds decide what survives.
  local label="${1}" seed="${2}" json="${3}" filter="${4}" expect="${5}"
  local jail file failed="false" reason="" got
  jail="$(mktemp -d)"
  file="${jail}/cache-claude.json"
  printf '%s' "${seed}" > "${file}"
  render_settled "${json}" \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  got="$(jq -r "${filter}" "${file}" 2>/dev/null)" || got="<jq-error>"
  if [[ "${got}" != "${expect}" ]]; then
    failed="true"
    reason="${filter} is ${got}, want ${expect}"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

agy_pool_case() {
  #   agy_pool_case <label>
  # A model switch must land each pool in its own file, and returning to the
  # earlier-reset pool must still write: the shared slot froze exactly here,
  # its monotonic guard siding with whichever pool reset later.
  local label="${1}" jail failed="false" reason=""
  local g_pct g_reset p_pct p_reset
  jail="$(mktemp -d)"
  render_settled '{"product":"antigravity","model":{"display_name":"Gemini 3.1 Pro"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"quota":{"gemini-5h":{"remaining_fraction":0.5,"reset_time":"2026-07-14T06:00:00Z"}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1700000000
  render_settled '{"product":"antigravity","model":{"display_name":"Claude Opus 4.6"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"quota":{"3p-5h":{"remaining_fraction":0.75,"reset_time":"2026-07-14T07:00:00Z"}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1700000000
  render_settled '{"product":"antigravity","model":{"display_name":"Gemini 3.1 Pro"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"quota":{"gemini-5h":{"remaining_fraction":0.25,"reset_time":"2026-07-14T06:00:00Z"}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1700000000

  g_pct="$(jq -r '.rate_5h_pct' "${jail}/cache-agy-gemini.json" 2>/dev/null)" || g_pct="<jq-error>"
  g_reset="$(jq -r '.rate_5h_reset' "${jail}/cache-agy-gemini.json" 2>/dev/null)" || g_reset="<jq-error>"
  p_pct="$(jq -r '.rate_5h_pct' "${jail}/cache-agy-3p.json" 2>/dev/null)" || p_pct="<jq-error>"
  p_reset="$(jq -r '.rate_5h_reset' "${jail}/cache-agy-3p.json" 2>/dev/null)" || p_reset="<jq-error>"

  if [[ "${g_pct}" != "75" || "${g_reset}" != "1784008800" ]]; then
    failed="true"
    reason="gemini pool is ${g_pct}/${g_reset}, want 75/1784008800; the return write was lost"
  elif [[ "${p_pct}" != "25" || "${p_reset}" != "1784012400" ]]; then
    failed="true"
    reason="3p pool is ${p_pct}/${p_reset}, want 25/1784012400; the switch clobbered it"
  fi

  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

cache_preserve_case() {
  #   cache_preserve_case <label>
  local label="${1}"
  local jail file failed="false" reason="" got_reset got_pct
  jail="$(mktemp -d)"
  file="${jail}/cache-claude.json"
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1789448400}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"resets_at":1789450000}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  got_reset="$(jq -r '.rate_5h_reset' "${file}" 2>/dev/null)" || got_reset="<jq-error>"
  got_pct="$(jq -r '.rate_5h_pct' "${file}" 2>/dev/null)" || got_pct="<jq-error>"
  if [[ "${got_reset}" != "1789448400" || "${got_pct}" != "40" ]]; then
    failed="true"
    reason="half-window write clobbered the cached pair: reset=${got_reset} pct=${got_pct} (want 1789448400 / 40)"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

cache_selfheal_case() {
  #   cache_selfheal_case <label> <corrupt_body>
  # Valid JSON that is not the cache schema wedges the writer just as hard as
  # unparseable bytes, so every shape gets a case.
  local label="${1}" body="${2}"
  local jail file got_pct failed="false" reason=""
  jail="$(mktemp -d)"
  file="${jail}/cache-claude.json"
  printf '%s' "${body}" > "${file}"
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1789448400}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  got_pct="$(jq -r '.rate_5h_pct' "${file}" 2>/dev/null)" || got_pct="<jq-error>"
  if [[ "${got_pct}" != "40" ]]; then
    failed="true"
    reason="corrupt cache wedged the writer: rate_5h_pct=${got_pct} (want 40)"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

cache_discard_case() {
  #   cache_discard_case <label> <corrupt_body> [<json>]
  # A file the reader rejects, met by input that cannot replace it, must be
  # removed rather than left behind for good. The default input carries a
  # half window; pass a rate-free payload to cover the no-input path.
  local label="${1}" body="${2}" json="${3:-}"
  # Braces in a ${3:-...} default end the expansion early, so default here.
  if [[ -z "${json}" ]]; then
    json='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":42}}}'
  fi
  local jail file failed="false" reason=""
  jail="$(mktemp -d)"
  file="${jail}/cache-claude.json"
  printf '%s' "${body}" > "${file}"
  render_settled "${json}" \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  if [[ -e "${file}" ]]; then
    failed="true"
    reason="unreadable cache survived: $(cat "${file}" 2>/dev/null)"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

cache_keep_case() {
  #   cache_keep_case <label> <seed_body> <json>
  # A readable cache met by input with nothing to add stays byte-identical.
  local label="${1}" body="${2}" json="${3}"
  local jail file failed="false" reason=""
  jail="$(mktemp -d)"
  file="${jail}/cache-claude.json"
  printf '%s' "${body}" > "${file}"
  render_settled "${json}" \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  if [[ "$(cat "${file}" 2>/dev/null)" != "${body}" ]]; then
    failed="true"
    reason="readable cache was altered or removed: $(cat "${file}" 2>/dev/null || echo '(gone)')"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

cache_normalize_case() {
  #   cache_normalize_case <label> <corrupt_body> <filter> <expect>
  # A cached window the reader accepts must be normalized, never carried
  # through in a form the Bash comparisons cannot handle.
  local label="${1}" body="${2}" filter="${3}" expect="${4}"
  local jail file got failed="false" reason=""
  jail="$(mktemp -d)"
  file="${jail}/cache-claude.json"
  printf '%s' "${body}" > "${file}"
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1789448400}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  got="$(jq -r "${filter}" "${file}" 2>/dev/null)" || got="<jq-error>"
  if [[ "${got}" != "${expect}" ]]; then
    failed="true"
    reason="${filter} is ${got}, want ${expect}"
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

# --- update-checker harness --------------------------------------------------
# Detached work settles through render_settled's inherited FIFO.

touch_epoch() {
  #   touch_epoch <path> <epoch>
  local path="${1}" epoch="${2}" ts
  ts="$(date -d "@${epoch}" '+%Y%m%d%H%M.%S' 2>/dev/null || date -r "${epoch}" '+%Y%m%d%H%M.%S')"
  touch -t "${ts}" "${path}"
}

update_badge_case() {
  #   update_badge_case <label> <remote_version> <local_version_override> <gate> <expect> <forbid> <json>
  local label="${1}" remote="${2}" local_ver="${3}" gate="${4}" expect="${5}" forbid="${6}" json="${7//__HOME__/${HOME}}"
  local jail
  jail="$(mktemp -d)"
  if [[ -n "${remote}" ]]; then
    printf '%s' "${remote}" > "${jail}/remote_version"
  fi
  export URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail}"
  export URDA_AI_FORGED_STATUS_LINE_VERSION_URL="file://${jail}/does-not-exist"
  [[ -n "${local_ver}" ]] && export URDA_AI_FORGED_STATUS_LINE_VERSION="${local_ver}"
  # Empty gate means on; restore the hermetic default afterward.
  export URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK="${gate:-1}"
  run_case "${label}" "${expect}" "${json}" "${forbid}"
  unset URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR URDA_AI_FORGED_STATUS_LINE_VERSION_URL
  [[ -n "${local_ver}" ]] && unset URDA_AI_FORGED_STATUS_LINE_VERSION
  export URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=0
  remove_jail "${jail}"
}

update_dispatch_case() {
  #   update_dispatch_case <label> <now> <mode: ok|fail|body> <expect_remote> [<pre_lock_age>] [<body>]
  local label="${1}" now="${2}" mode="${3}" expect_remote="${4}" pre_lock_age="${5:-}" body="${6:-}"
  local jail fixture_dir url failed="false" reason="" got
  jail="$(mktemp -d)"
  fixture_dir="$(mktemp -d)"

  if [[ "${mode}" == "ok" ]]; then
    printf '9.9.9' > "${fixture_dir}/VERSION"
    url="file://${fixture_dir}/VERSION"
  elif [[ "${mode}" == "body" ]]; then
    printf '%s' "${body}" > "${fixture_dir}/VERSION"
    url="file://${fixture_dir}/VERSION"
  else
    url="file://${fixture_dir}/does-not-exist"
  fi

  if [[ -n "${pre_lock_age}" ]]; then
    mkdir "${jail}/update-check.lock"
    touch_epoch "${jail}/update-check.lock" "$(( now - pre_lock_age ))"
  fi

  # Override the hermetic default so the check can dispatch.
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}' \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail}" \
    URDA_AI_FORGED_STATUS_LINE_VERSION_URL="${url}" \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW="${now}"

  if [[ -f "${jail}/last_check" ]]; then
    got="$(<"${jail}/last_check")"
    if [[ "${got}" != "${now}" ]]; then
      failed="true"
      reason="last_check=${got}, want ${now}"
    elif [[ -n "${expect_remote}" && ! -f "${jail}/remote_version" ]]; then
      failed="true"
      reason="remote_version never appeared"
    elif [[ -n "${expect_remote}" && "$(<"${jail}/remote_version")" != "${expect_remote}" ]]; then
      failed="true"
      reason="remote_version=$(<"${jail}/remote_version"), want ${expect_remote}"
    elif [[ -z "${expect_remote}" && -f "${jail}/remote_version" ]]; then
      failed="true"
      reason="remote_version written on a clean failure; must stay untouched"
    elif [[ -d "${jail}/update-check.lock" ]]; then
      failed="true"
      reason="lock directory was not cleaned up after the check completed"
    fi
  else
    failed="true"
    reason="last_check never appeared (expected a dispatch)"
  fi

  remove_jail "${jail}" "${fixture_dir}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_no_dispatch_case() {
  #   update_no_dispatch_case <label> <now> <pre_last_check> <pre_lock_age>
  local label="${1}" now="${2}" pre_last_check="${3:-}" pre_lock_age="${4:-}"
  local jail failed="false" reason="" got
  jail="$(mktemp -d)"

  if [[ -n "${pre_last_check}" ]]; then
    printf '%s' "${pre_last_check}" > "${jail}/last_check"
  fi
  if [[ -n "${pre_lock_age}" ]]; then
    mkdir "${jail}/update-check.lock"
    touch_epoch "${jail}/update-check.lock" "$(( now - pre_lock_age ))"
  fi

  # Enable checks so the throttle or lock is the only blocker.
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}' \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail}" \
    URDA_AI_FORGED_STATUS_LINE_VERSION_URL="file://${jail}/does-not-exist" \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW="${now}"

  if [[ -n "${pre_last_check}" ]]; then
    got="$(<"${jail}/last_check")"
    if [[ "${got}" != "${pre_last_check}" ]]; then
      failed="true"
      reason="last_check changed from ${pre_last_check} to ${got}; expected no dispatch"
    fi
  elif [[ -f "${jail}/last_check" ]]; then
    failed="true"
    reason="last_check appeared; expected no dispatch"
  fi

  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_interval_fire_case() {
  #   update_interval_fire_case <label> <now> <age>
  # Seed last_check exactly <age> seconds old; the throttle must re-arm.
  local label="${1}" now="${2}" age="${3}"
  local jail fixture_dir failed="false" reason="" got
  jail="$(mktemp -d)"
  fixture_dir="$(mktemp -d)"
  printf '9.9.9' > "${fixture_dir}/VERSION"
  printf '%s' "$(( now - age ))" > "${jail}/last_check"

  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}' \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail}" \
    URDA_AI_FORGED_STATUS_LINE_VERSION_URL="file://${fixture_dir}/VERSION" \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW="${now}"

  got="$(<"${jail}/last_check")"
  if [[ "${got}" != "${now}" ]]; then
    failed="true"
    reason="last_check=${got}, want ${now}; expected the throttle to re-arm at age ${age}"
  fi

  remove_jail "${jail}" "${fixture_dir}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_fidelity_case() {
  #   update_fidelity_case <label> <json>
  local label="${1}" json="${2//__HOME__/${HOME}}"
  local jail_on jail_off on off failed="false" reason=""
  jail_on="$(mktemp -d)"; jail_off="$(mktemp -d)"
  off="$(URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=0 URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail_off}" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1000000000 bash "${STATUSLINE}" <<<"${json}")"
  on="$(URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail_on}" URDA_AI_FORGED_STATUS_LINE_VERSION_URL="file://${jail_on}/does-not-exist" URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1000000000 bash "${STATUSLINE}" <<<"${json}")"
  remove_jail "${jail_on}" "${jail_off}"
  if [[ "${on}" != "${off}" ]]; then
    failed="true"
    reason="gate-on stdout differs from gate-off stdout"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

stat_order_case() {
  # Every stat fallback chain must probe GNU (-c) before BSD (-f). GNU stat
  # treats -f as filesystem status: it emits noise on stdout while exiting
  # nonzero, so a BSD-first chain captures garbage on Linux and the bug only
  # surfaces in CI. Static check, so either platform catches it at author
  # time.
  local label="portability: stat fallbacks probe GNU before BSD"
  local hits failed="false" reason=""
  hits="$(grep -nE 'stat -f [^|]*\|\|[^|]*stat -c' \
    "${STATUSLINE}" "${BASH_SOURCE[0]}" 2>/dev/null)" || :
  if [[ -n "${hits}" ]]; then
    failed="true"
    reason="BSD-first stat chain found; swap to stat -c || stat -f:
${hits}"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

grep_pipe_case() {
  # The suite must not pipe into grep -q: under pipefail, grep -q exits at
  # the first match, the producer can die with SIGPIPE, and the pipeline
  # "fails" although the match succeeded. A rare, timing-dependent flake;
  # use a herestring instead. The bracketed [|] keeps this checker from
  # matching itself.
  local label="hygiene: no pipelines into grep -q (SIGPIPE flake)"
  local hits failed="false" reason=""
  hits="$(grep -nE '[|] *grep -q' "${BASH_SOURCE[0]}" 2>/dev/null)" || :
  if [[ -n "${hits}" ]]; then
    failed="true"
    reason="pipe into grep -q found; use grep -q ... <<<\"input\" instead:
${hits}"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

version_file_case() {
  # Published VERSION must match the renderer's compiled default.
  local label="update-checker: VERSION file matches the in-script default"
  local declared file_ver failed="false" reason=""
  declared="$(grep -oE 'VERSION:-[0-9]+\.[0-9]+\.[0-9]+' "${STATUSLINE}" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  file_ver="$(<"${REPO_ROOT}/VERSION")"
  file_ver="${file_ver//[[:space:]]/}"
  if [[ -z "${declared}" ]]; then
    failed="true"
    reason="could not find the version declaration line in ${STATUSLINE}"
  elif [[ "${declared}" != "${file_ver}" ]]; then
    failed="true"
    reason="VERSION file says ${file_ver}, script default says ${declared}"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

url_default_case() {
  # Pin both shipped default URLs: exactly one active assignment each, on
  # the non-redirecting raw host. Comments are excluded so a parked copy
  # of the correct URL cannot shadow a wrong live default.
  local label="update-checker: default VERSION_URL and UPDATE_URL are the release raw URLs"
  local failed="false" reason=""
  local active update_refs version_refs
  active="$(grep -v '^[[:space:]]*#' "${STATUSLINE}")"
  update_refs="$(printf '%s\n' "${active}" | grep -c 'URDA_AI_FORGED_STATUS_LINE_UPDATE_URL:-' || true)"
  version_refs="$(printf '%s\n' "${active}" | grep -c 'URDA_AI_FORGED_STATUS_LINE_VERSION_URL:-' || true)"

  if [[ "${version_refs}" != "1" ]]; then
    failed="true"
    reason="want exactly one active VERSION_URL default, found ${version_refs}"
  elif [[ "${update_refs}" != "1" ]]; then
    failed="true"
    reason="want exactly one active UPDATE_URL default, found ${update_refs}"
  elif ! grep -qF 'URDA_AI_FORGED_STATUS_LINE_VERSION_URL:-https://raw.githubusercontent.com/urda/forged-statusline/release/VERSION}' <<<"${active}"; then
    failed="true"
    reason="active VERSION_URL default is not the exact release VERSION raw URL"
  elif ! grep -qF 'URDA_AI_FORGED_STATUS_LINE_UPDATE_URL:-https://raw.githubusercontent.com/urda/forged-statusline/release/urda-com-forged-statusline.sh}' <<<"${active}"; then
    failed="true"
    reason="active UPDATE_URL default is not the exact release renderer raw URL"
  elif grep -q 'github\.com/urda/forged-statusline/raw/' <<<"${active}"; then
    failed="true"
    reason="found an active github.com/.../raw/ redirect URL; curl -fs (no -L) would drop it"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

injection_case() {
  #   injection_case <label> <field: model|dir|effort>
  local label="${1}" field="${2}"
  local dir marker payload json output rc rows failed="false" reason=""
  dir="$(mktemp -d)"
  marker="${dir}/pwned"
  # Bash 3.2-compatible octal escapes supply real control bytes.
  payload=$'/tmp/x\nINJECTED[$(touch '"${marker}"$')]\037rest\033Z'
  case "${field}" in
    model)  json="$(jq -n --arg v "${payload}" '{model:{display_name:$v},workspace:{current_dir:"/tmp/x"},context_window:{used_percentage:20}}')" ;;
    dir)    json="$(jq -n --arg v "${payload}" '{model:{display_name:"Opus"},workspace:{current_dir:$v},context_window:{used_percentage:20}}')" ;;
    effort) json="$(jq -n --arg v "${payload}" '{model:{display_name:"Opus"},workspace:{current_dir:"/tmp/x"},context_window:{used_percentage:20},effort:{level:$v}}')" ;;
  esac

  # Settle via inherited fd 9 so a (mis)dispatched child cannot outrun the
  # marker assertion; stdout is captured to a file alongside.
  local settle_dir
  settle_dir="$(mktemp -d)"
  mkfifo "${settle_dir}/settled"
  printf '%s' "${json}" | bash "${STATUSLINE}" 9>"${settle_dir}/settled" >"${settle_dir}/out" &
  cat "${settle_dir}/settled" >/dev/null
  if wait "$!"; then
    rc=0
  else
    rc=$?
  fi
  output="$(<"${settle_dir}/out")"
  rm -rf "${settle_dir}"
  rows="$(printf '%s\n' "${output}" | grep -c '^')"

  if [[ -f "${marker}" ]]; then
    failed="true"
    reason="INJECTION EXECUTED: the forged \$(touch) ran and created the marker"
  elif [[ "${rc}" -ne 0 ]]; then
    failed="true"
    reason="exited ${rc} (a non-zero exit blanks the real status line)"
  elif [[ -z "${output}" ]]; then
    failed="true"
    reason="produced no output"
  elif [[ "${rows}" -ne 2 ]]; then
    failed="true"
    reason="expected exactly two rows, got ${rows} (a smuggled newline leaked into the render)"
  fi
  rm -rf "${dir}"
  cache_report "${label}" "${failed}" "${reason}"
}

thinking_forge_case() {
  #   thinking_forge_case <label> <forged_name> <forged_value> <expect> <forbid>
  local label="${1}" fname="${2}" fval="${3}" expect="${4}" forbid="${5}"
  local us nl payload json output rc rows plain failed="false" reason=""
  us=$'\037'; nl=$'\n'
  # A vulnerable parser treats the injected newline as another record.
  payload="false${nl}${fname}${us}${fval}"
  json="$(jq -n --arg t "${payload}" '{model:{display_name:"Opus"},workspace:{current_dir:"/tmp/x"},context_window:{used_percentage:20},thinking:{enabled:$t}}')"

  if output="$(printf '%s' "${json}" | bash "${STATUSLINE}")"; then
    rc=0
  else
    rc=$?
  fi
  rows="$(printf '%s\n' "${output}" | grep -c '^')"
  plain="$(printf '%s' "${output}" | strip_ansi)"

  if [[ "${rc}" -ne 0 ]]; then
    failed="true"
    reason="exited ${rc} (a non-zero exit blanks the real status line)"
  elif [[ -z "${output}" ]]; then
    failed="true"
    reason="produced no output"
  elif [[ "${rows}" -ne 2 ]]; then
    failed="true"
    reason="expected exactly two rows, got ${rows} (a smuggled newline leaked into the render)"
  elif [[ -n "${forbid}" && "${plain}" == *"${forbid}"* ]]; then
    failed="true"
    reason="FORGE LANDED: the injected value \"${forbid}\" reached the render"
  elif [[ -n "${expect}" && "${plain}" != *"${expect}"* ]]; then
    failed="true"
    reason="expected the untouched value \"${expect}\" to remain in the render"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

update_nocurl_case() {
  #   update_nocurl_case <label> <now>
  local label="${1}" now="${2}"
  local jail bindir tool src first second failed="false" reason="" json
  jail="$(mktemp -d)"
  bindir="$(mktemp -d)"
  # Omit curl and wget so the status=127 branch runs.
  for tool in jq mkdir rmdir stat mv rm date sort tail sed cat ls mktemp; do
    src="$(command -v "${tool}" 2>/dev/null)" && ln -s "${src}" "${bindir}/${tool}"
  done
  json='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}'

  # Override the suite's default-off update checker.
  render_settled "${json}" PATH="${bindir}" \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail}" \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW="${now}"

  if [[ -f "${jail}/last_check" ]]; then
    first="$(<"${jail}/last_check")"
    render_settled "${json}" PATH="${bindir}" \
      URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
      URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail}" \
      URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW="${now}"
    second="$(<"${jail}/last_check")"
    # fetched must survive set -u, and the EXIT trap must clear the lock.
    if [[ "${first}" != "${now}" ]]; then
      failed="true"
      reason="first render did not write last_check==${now} (got '${first}'); a downloader-less host would redispatch every render"
    elif [[ "${second}" != "${now}" ]]; then
      failed="true"
      reason="second render changed last_check to '${second}'; the throttle did not hold"
    elif [[ -d "${jail}/update-check.lock" ]]; then
      failed="true"
      reason="update-check.lock was left behind; the downloader-less child did not tear down cleanly"
    fi
  else
    failed="true"
    reason="last_check never appeared; the downloader-less dispatch failed to advance the throttle"
  fi
  remove_jail "${jail}" "${bindir}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_wget_case() {
  #   update_wget_case <label> <now>
  local label="${1}" now="${2}"
  local jail bindir tool src failed="false" reason="" json
  jail="$(mktemp -d)"
  bindir="$(mktemp -d)"
  for tool in jq mkdir rmdir stat mv rm date sort tail sed cat ls mktemp; do
    src="$(command -v "${tool}" 2>/dev/null)" && ln -s "${src}" "${bindir}/${tool}"
  done
  cat > "${bindir}/wget" <<'WGET_SHIM'
#!/bin/sh
# Exact argv shape, --max-redirect=0 (H1 redirect guard) and the release URL
# included: a decoy option operand must not be able to masquerade as the URL.
if [ "$#" -ne 5 ] || [ "$1" != "--max-redirect=0" ] || [ "$2" != "--timeout=5" ] \
   || [ "$3" != "--tries=1" ] || [ "$4" != "-qO-" ] \
   || [ "$5" != "https://raw.githubusercontent.com/urda/forged-statusline/release/VERSION" ]; then
  echo "wget shim: unexpected argv: $*" >&2
  exit 3
fi
printf '%s\n' "${FSL_TEST_WGET_BODY:-9.9.9}"
WGET_SHIM
  chmod +x "${bindir}/wget"
  json='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}'

  render_settled "${json}" PATH="${bindir}" \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail}" \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW="${now}"

  if [[ -f "${jail}/last_check" ]]; then
    if [[ "$(<"${jail}/last_check")" != "${now}" ]]; then
      failed="true"
      reason="last_check != ${now}; the wget attempt did not advance the throttle"
    elif [[ ! -f "${jail}/remote_version" ]]; then
      failed="true"
      reason="remote_version not written; the wget fallback did not fetch (or the H1 flag assert fired)"
    elif [[ "$(<"${jail}/remote_version")" != "9.9.9" ]]; then
      failed="true"
      reason="remote_version=$(<"${jail}/remote_version"), want 9.9.9"
    elif [[ -d "${jail}/update-check.lock" ]]; then
      failed="true"
      reason="update-check.lock left behind; the wget child did not tear down cleanly"
    fi
  else
    failed="true"
    reason="last_check never appeared; the wget dispatch did not run"
  fi
  remove_jail "${jail}" "${bindir}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_curl_case() {
  #   update_curl_case <label> <now>
  # The curl twin of update_wget_case: pins the preferred branch's exact argv.
  local label="${1}" now="${2}"
  local jail bindir tool src failed="false" reason="" json
  jail="$(mktemp -d)"
  bindir="$(mktemp -d)"
  for tool in jq mkdir rmdir stat mv rm date sort tail sed cat ls mktemp; do
    src="$(command -v "${tool}" 2>/dev/null)" && ln -s "${src}" "${bindir}/${tool}"
  done
  cat > "${bindir}/curl" <<'CURL_SHIM'
#!/bin/sh
# Exact argv shape, release URL included: a decoy option operand must not be
# able to masquerade as the URL.
if [ "$#" -ne 4 ] || [ "$1" != "-fs" ] || [ "$2" != "-m" ] || [ "$3" != "5" ] \
   || [ "$4" != "https://raw.githubusercontent.com/urda/forged-statusline/release/VERSION" ]; then
  echo "curl shim: unexpected argv: $*" >&2
  exit 3
fi
printf '%s\n' "${FSL_TEST_CURL_BODY:-9.9.9}"
CURL_SHIM
  chmod +x "${bindir}/curl"
  json='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}'

  render_settled "${json}" PATH="${bindir}" \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail}" \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW="${now}"

  if [[ -f "${jail}/last_check" ]]; then
    if [[ "$(<"${jail}/last_check")" != "${now}" ]]; then
      failed="true"
      reason="last_check != ${now}; the curl attempt did not advance the throttle"
    elif [[ ! -f "${jail}/remote_version" ]]; then
      failed="true"
      reason="remote_version not written; the curl branch did not fetch (or the argv assert fired)"
    elif [[ "$(<"${jail}/remote_version")" != "9.9.9" ]]; then
      failed="true"
      reason="remote_version=$(<"${jail}/remote_version"), want 9.9.9"
    elif [[ -d "${jail}/update-check.lock" ]]; then
      failed="true"
      reason="update-check.lock left behind; the curl child did not tear down cleanly"
    fi
  else
    failed="true"
    reason="last_check never appeared; the curl dispatch did not run"
  fi
  remove_jail "${jail}" "${bindir}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_self_case() {
  #   update_self_case <label> <mode: good|junk|wrong-identity> <expect_swapped>
  local label="${1}" mode="${2}" expect_swapped="${3}"
  local work installed backup fixture rc failed="false" reason=""
  work="$(mktemp -d)"
  installed="${work}/urda-com-forged-statusline.sh"
  cp "${STATUSLINE}" "${installed}"
  chmod +x "${installed}"
  backup="${work}/backup.sh"
  cp "${installed}" "${backup}"

  fixture="${work}/new.sh"
  case "${mode}" in
    good)
      # Minimal body that passes bash -n and every identity anchor.
      printf '#!/usr/bin/env bash\nURDA_AI_FORGED_STATUS_LINE_VERSION="9.9.9"\nupdate_check() { :; }\necho updated-fixture\nexit 0\n' > "${fixture}" ;;
    truncated)
      # Every anchor present, but cut short before the closing line.
      printf '#!/usr/bin/env bash\nURDA_AI_FORGED_STATUS_LINE_VERSION="9.9.9"\nupdate_check() { :; }\necho updated-fixture\n' > "${fixture}" ;;
    junk)
      # Not valid bash: bash -n rejects it before any swap.
      printf '<html><body>404 Not Found</body></html>\n' > "${fixture}" ;;
    wrong-identity)
      # Valid bash but missing the renderer anchors.
      printf '#!/usr/bin/env bash\necho this-is-not-the-renderer\n' > "${fixture}" ;;
  esac

  # A file:// URL exercises the real curl download path against a local fixture.
  if URDA_AI_FORGED_STATUS_LINE_UPDATE_URL="file://${fixture}" \
      bash "${installed}" --update >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi

  if [[ "${expect_swapped}" == "true" ]]; then
    if [[ "${rc}" -ne 0 ]]; then
      failed="true"; reason="update exited ${rc}; expected a successful swap"
    elif ! cmp -s "${installed}" "${fixture}"; then
      failed="true"; reason="script was not replaced with the fetched body"
    elif [[ ! -x "${installed}" ]]; then
      failed="true"; reason="swapped-in script is not executable"
    fi
  else
    if [[ "${rc}" -eq 0 ]]; then
      failed="true"; reason="update exited 0 on a body that must be rejected"
    elif ! cmp -s "${installed}" "${backup}"; then
      failed="true"; reason="script changed; a rejected download must leave it byte-identical"
    fi
  fi

  if [[ "${failed}" == "false" ]]; then
    local leftovers
    shopt -s nullglob
    leftovers=("${work}"/.urda-com-forged-statusline.*)
    shopt -u nullglob
    if (( ${#leftovers[@]} != 0 )); then
      failed="true"; reason="temp file(s) left behind: ${leftovers[*]}"
    fi
  fi

  rm -rf "${work}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_self_nodl_case() {
  #   update_self_nodl_case <label>
  local label="${1}"
  local work installed backup bindir bash_bin tool src rc failed="false" reason=""
  work="$(mktemp -d)"
  bindir="$(mktemp -d)"
  bash_bin="$(command -v bash)"
  installed="${work}/urda-com-forged-statusline.sh"
  cp "${STATUSLINE}" "${installed}"
  chmod +x "${installed}"
  backup="${work}/backup.sh"
  cp "${installed}" "${backup}"
  # Only the tools update_self reaches before the downloader check; no curl/wget.
  for tool in dirname basename mktemp rm; do
    src="$(command -v "${tool}" 2>/dev/null)" && ln -s "${src}" "${bindir}/${tool}"
  done

  if PATH="${bindir}" "${bash_bin}" "${installed}" --update >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi

  if [[ "${rc}" -eq 0 ]]; then
    failed="true"; reason="update exited 0 with no downloader; expected failure"
  elif ! cmp -s "${installed}" "${backup}"; then
    failed="true"; reason="script changed with no downloader present"
  fi

  if [[ "${failed}" == "false" ]]; then
    local leftovers
    shopt -s nullglob
    leftovers=("${work}"/.urda-com-forged-statusline.*)
    shopt -u nullglob
    if (( ${#leftovers[@]} != 0 )); then
      failed="true"; reason="temp file(s) left behind: ${leftovers[*]}"
    fi
  fi

  rm -rf "${work}" "${bindir}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_self_chmodfail_case() {
  #   update_self_chmodfail_case <label>
  local label="${1}"
  local work bin installed backup fixture rc failed="false" reason=""
  work="$(mktemp -d)"; bin="$(mktemp -d)"
  installed="${work}/urda-com-forged-statusline.sh"
  cp "${STATUSLINE}" "${installed}"; chmod +x "${installed}"
  backup="${work}/backup.sh"; cp "${installed}" "${backup}"
  fixture="${work}/new.sh"
  printf '#!/usr/bin/env bash\nURDA_AI_FORGED_STATUS_LINE_VERSION="9.9.9"\nupdate_check() { :; }\necho updated-fixture\nexit 0\n' > "${fixture}"
  # Override only chmod with a failing shim; the swap must abort before mv.
  printf '#!/bin/sh\nexit 1\n' > "${bin}/chmod"; chmod +x "${bin}/chmod"

  if PATH="${bin}:${PATH}" URDA_AI_FORGED_STATUS_LINE_UPDATE_URL="file://${fixture}" \
      bash "${installed}" --update >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi

  if [[ "${rc}" -eq 0 ]]; then
    failed="true"; reason="update exited 0 despite a failed chmod; expected an abort before swap"
  elif ! cmp -s "${installed}" "${backup}"; then
    failed="true"; reason="script was swapped after a failed chmod; must stay byte-identical"
  elif [[ ! -x "${installed}" ]]; then
    failed="true"; reason="script lost its execute bit after a failed chmod"
  fi

  if [[ "${failed}" == "false" ]]; then
    local leftovers
    shopt -s nullglob
    leftovers=("${work}"/.urda-com-forged-statusline.*)
    shopt -u nullglob
    if (( ${#leftovers[@]} != 0 )); then
      failed="true"; reason="temp file(s) left behind: ${leftovers[*]}"
    fi
  fi

  rm -rf "${work}" "${bin}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_self_mvfail_case() {
  #   update_self_mvfail_case <label>
  # Fault-inject the final swap: with mv failing, only a truly atomic
  # replacement leaves the byte-identical executable original behind.
  local label="${1}"
  local work bin installed backup fixture rc failed="false" reason=""
  work="$(mktemp -d)"; bin="$(mktemp -d)"
  installed="${work}/urda-com-forged-statusline.sh"
  cp "${STATUSLINE}" "${installed}"; chmod +x "${installed}"
  backup="${work}/backup.sh"; cp "${installed}" "${backup}"
  fixture="${work}/new.sh"
  printf '#!/usr/bin/env bash\nURDA_AI_FORGED_STATUS_LINE_VERSION="9.9.9"\nupdate_check() { :; }\necho updated-fixture\nexit 0\n' > "${fixture}"
  printf '#!/bin/sh\nexit 1\n' > "${bin}/mv"; chmod +x "${bin}/mv"

  if PATH="${bin}:${PATH}" URDA_AI_FORGED_STATUS_LINE_UPDATE_URL="file://${fixture}" \
      bash "${installed}" --update >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi

  if [[ "${rc}" -eq 0 ]]; then
    failed="true"; reason="update exited 0 despite a failed mv swap"
  elif ! cmp -s "${installed}" "${backup}"; then
    failed="true"; reason="script changed despite a failed mv; must stay byte-identical"
  elif [[ ! -x "${installed}" ]]; then
    failed="true"; reason="script lost its execute bit after a failed mv"
  fi

  if [[ "${failed}" == "false" ]]; then
    local leftovers
    shopt -s nullglob
    leftovers=("${work}"/.urda-com-forged-statusline.*)
    shopt -u nullglob
    if (( ${#leftovers[@]} != 0 )); then
      failed="true"; reason="temp file(s) left behind: ${leftovers[*]}"
    fi
  fi

  rm -rf "${work}" "${bin}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_self_curl_case() {
  #   update_self_curl_case <label>
  # The curl twin of update_self_wget_case: pins the preferred branch's argv.
  local label="${1}"
  local work installed backup bindir bash_bin tool src rc failed="false" reason=""
  work="$(mktemp -d)"
  bindir="$(mktemp -d)"
  bash_bin="$(command -v bash)"
  installed="${work}/urda-com-forged-statusline.sh"
  cp "${STATUSLINE}" "${installed}"
  chmod +x "${installed}"
  backup="${work}/backup.sh"
  cp "${installed}" "${backup}"
  for tool in dirname basename mktemp head tail grep chmod mv rm bash; do
    src="$(command -v "${tool}" 2>/dev/null)" && ln -s "${src}" "${bindir}/${tool}"
  done
  # No wget in the jail; the curl shim writes a valid renderer body to -o's target.
  cat > "${bindir}/curl" <<'CURL_SHIM'
#!/bin/sh
# Exact argv shape, release URL included: a decoy option operand must not be
# able to masquerade as the URL.
if [ "$#" -ne 4 ] || [ "$1" != "-fsSL" ] \
   || [ "$2" != "https://raw.githubusercontent.com/urda/forged-statusline/release/urda-com-forged-statusline.sh" ] \
   || [ "$3" != "-o" ] || [ -z "$4" ]; then
  printf 'curl shim: unexpected argv: %s\n' "$*" >&2
  exit 22
fi
printf '#!/usr/bin/env bash\nURDA_AI_FORGED_STATUS_LINE_VERSION="9.9.9"\nupdate_check() { :; }\necho updated-fixture\nexit 0\n' > "$4"
CURL_SHIM
  chmod +x "${bindir}/curl"

  if PATH="${bindir}" "${bash_bin}" "${installed}" --update >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi

  if [[ "${rc}" -ne 0 ]]; then
    failed="true"; reason="curl-branch update exited ${rc}; expected a successful swap"
  elif cmp -s "${installed}" "${backup}"; then
    failed="true"; reason="script unchanged; the curl branch did not swap"
  elif ! grep -q 'updated-fixture' "${installed}"; then
    failed="true"; reason="script does not contain the curl-fetched body"
  fi

  rm -rf "${work}" "${bindir}"
  cache_report "${label}" "${failed}" "${reason}"
}

update_self_wget_case() {
  #   update_self_wget_case <label>
  local label="${1}"
  local work installed backup bindir bash_bin tool src rc failed="false" reason=""
  work="$(mktemp -d)"
  bindir="$(mktemp -d)"
  bash_bin="$(command -v bash)"
  installed="${work}/urda-com-forged-statusline.sh"
  cp "${STATUSLINE}" "${installed}"
  chmod +x "${installed}"
  backup="${work}/backup.sh"
  cp "${installed}" "${backup}"
  for tool in dirname basename mktemp head tail grep chmod mv rm bash; do
    src="$(command -v "${tool}" 2>/dev/null)" && ln -s "${src}" "${bindir}/${tool}"
  done
  # No curl in the jail; the wget shim writes a valid renderer body to -O's target.
  cat > "${bindir}/wget" <<'WGET_SHIM'
#!/bin/sh
# Exact argv shape, release URL included: a decoy option operand must not be
# able to masquerade as the URL.
if [ "$#" -ne 3 ] || [ "$1" != "-qO" ] || [ -z "$2" ] \
   || [ "$3" != "https://raw.githubusercontent.com/urda/forged-statusline/release/urda-com-forged-statusline.sh" ]; then
  printf 'wget shim: unexpected argv: %s\n' "$*" >&2
  exit 8
fi
printf '#!/usr/bin/env bash\nURDA_AI_FORGED_STATUS_LINE_VERSION="9.9.9"\nupdate_check() { :; }\necho updated-fixture\nexit 0\n' > "$2"
WGET_SHIM
  chmod +x "${bindir}/wget"

  if PATH="${bindir}" "${bash_bin}" "${installed}" --update >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi

  if [[ "${rc}" -ne 0 ]]; then
    failed="true"; reason="wget-branch update exited ${rc}; expected a successful swap"
  elif cmp -s "${installed}" "${backup}"; then
    failed="true"; reason="script unchanged; the wget branch did not swap"
  elif ! grep -q 'updated-fixture' "${installed}"; then
    failed="true"; reason="script does not contain the wget-fetched body"
  fi

  rm -rf "${work}" "${bindir}"
  cache_report "${label}" "${failed}" "${reason}"
}

tail_anchor_case() {
  # Both replacement validators anchor completeness on this exact final line.
  local label="renderer: final line is the exit 0 both validators require"
  local last failed="false" reason=""
  last="$(tail -1 "${STATUSLINE}")"
  if [[ "${last}" != 'exit 0' ]]; then
    failed="true"
    reason="last line is '${last}'; install.sh and --update would both reject this renderer"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

flag_case() {
  #   flag_case <label> <arg> <expect> <expect_rows>
  local label="${1}" arg="${2}" expect="${3}" want_rows="${4}"
  local json out rc rows failed="false" reason=""
  json='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}'
  if out="$(bash "${STATUSLINE}" "${arg}" <<<"${json}" 2>/dev/null)"; then
    rc=0
  else
    rc=$?
  fi
  rows="$(printf '%s\n' "${out}" | grep -c '^')"
  if [[ "${rc}" -ne 0 ]]; then
    failed="true"
    reason="exited ${rc} (a non-zero exit blanks the real status line)"
  elif [[ "${out}" != *"${expect}"* ]]; then
    failed="true"
    reason="expected output to contain \"${expect}\""
  elif [[ -n "${want_rows}" && "${rows}" -ne "${want_rows}" ]]; then
    failed="true"
    reason="expected ${want_rows} rows, got ${rows}"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

version_flag_case() {
  # --version must report the renderer's own compiled default.
  local label="flags: --version prints the declared version"
  local declared out rc failed="false" reason=""
  declared="$(grep -oE 'VERSION:-[0-9]+\.[0-9]+\.[0-9]+' "${STATUSLINE}" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  if out="$(bash "${STATUSLINE}" --version 2>/dev/null)"; then
    rc=0
  else
    rc=$?
  fi
  if [[ "${rc}" -ne 0 ]]; then
    failed="true"
    reason="exited ${rc}"
  elif [[ -z "${declared}" ]]; then
    failed="true"
    reason="could not read the declared version from ${STATUSLINE}"
  elif [[ "${out}" != "${declared}" ]]; then
    failed="true"
    reason="--version printed '${out}', want '${declared}'"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}

# --- cases ------------------------------------------------------------------
# __HOME__ marks paths expanded by the harness.

echo "Testing status line: ${STATUSLINE}"

# Test real defaults, not inherited shell settings.
for _var in "${!URDA_AI_FORGED_STATUS_LINE_@}"; do unset "${_var}"; done
unset _var

# Dedicated cases re-enable updates against private fixtures.
export URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=0

section "Percentage thresholds"
run_case "Zero usage (calm, empty bar)" '0%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":0}}'
run_case "Low usage (calm)" '15%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":15}}'
run_case "Warn boundary (exactly 50)" '50%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":50}}'
run_case "Mid usage (warn)" '65%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":65}}'
run_case "Alarm boundary (exactly 80)" '80%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":80}}'
run_case "Near full (alarm)" '95%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":95}}'

section "Bar bounds"
run_case "Full (100%, full bar)" '100%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":100}}'
run_case "Overage clamps to 100%" '100%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":120}}'
run_case "101% clamps to 100%" '100%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":101}}'
# A reading too wide for Bash arithmetic clamps rather than wrapping negative.
run_case "INT64_MAX percentage clamps to 100%" ']100%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":9223372036854775807}}'
run_case "Oversized 5h reading clamps to 100%" '5h [████████]100%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":9223372036854775807}}}'
run_case "Oversized 7d reading clamps to 100%" '7d [████████]100%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":9223372036854775807}}}'

section "Bar width"
# Eight cells for every reading, including the ones that stress the fill math.
bar_cells_case "Three gauges each render eight cells" 3 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":55,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1799999999},"seven_day":{"used_percentage":88,"resets_at":1799999999}}}'
bar_cells_case "Zero reading renders eight cells" 1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":0}}'
bar_cells_case "Full reading renders eight cells" 1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":100}}'
bar_cells_case "Unknown reading renders eight cells" 1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"}}'
bar_cells_case "Sub-cell reading renders eight cells" 1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":1}}'
bar_cells_case "Fractional reading renders eight cells" 1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":85.4}}'
bar_cells_case "Clamped oversized reading renders eight cells" 1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":9223372036854775807}}'

section "Fractional input"
run_case "85.4 floors to 85%" '85%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":85.4}}'

section "Missing-field fallbacks"
run_case "Missing model -> (Missing Model)" '(Missing Model)' \
  '{"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":10}}'
run_case "Missing directory -> (Missing Directory)" '(Missing Directory)' \
  '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10}}'
run_case "Missing context_window -> ???%" '???%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"}}'
run_case "Real 0% shows 0%, not ???" '0%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":0}}' \
  '?'
run_case "Empty object -> fallbacks" '(Missing Model)' '{}'
run_case "Malformed JSON falls back" '(Missing Model)' 'not valid json'
poisoned_env_case "Poisoned environment cannot leak through a failed parse" \
  'not valid json'
seed_completeness_case "Every parser destination is seeded before the parse"

section "Structural contract"
structural_case "Full render matches the exact two-row contract" \
  '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"thinking":{"enabled":false},"workspace":{"current_dir":"/srv/forge"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1700005400},"seven_day":{"used_percentage":66,"resets_at":1700090000}}}' \
  '🔮 Opus [200K] 🦾 high 🚫 Thinking: OFF | 💾 /srv/forge' \
  '🧠 [█▌      ] 20% | ⏳ 5h [███▎    ] 42% (1h30m) | 🟡 7d [█████▎  ] 66% (1d01h)'

section "Missing jq"
# Missing jq must be explicit and nonfatal.
HIDE_JQ=1
run_case "Missing jq is explicit" 'jq not found' \
  '{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":28}}' \
  '(Missing Model)'
export URDA_AI_FORGED_STATUS_LINE_ICONS=0
run_case "Missing jq respects icons-off" 'jq not found' \
  '{"model":{"display_name":"Opus 4.8"}}' \
  '🔴'
unset URDA_AI_FORGED_STATUS_LINE_ICONS
unset HIDE_JQ

section "Directory"
# The expected ~ is output text, not a path.
# shellcheck disable=SC2088
run_case "Home dir collapses to ~" '~/dev/urda/forged-statusline' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":30}}'

section "Home collapse boundary"
# Do not collapse HOME sibling prefixes.
# shellcheck disable=SC2088
run_case "current_dir == \$HOME collapses to a bare ~" '💾 ~' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__"},"context_window":{"used_percentage":20}}' \
  '~/'
# shellcheck disable=SC2088
run_case "\$HOME/sub collapses to ~/sub" '~/deep/nest' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/deep/nest"},"context_window":{"used_percentage":20}}'
run_case "HOME sibling is not collapsed" '-other/x' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__-other/x"},"context_window":{"used_percentage":20}}' \
  '~'

section "Control-character injection"
injection_case "Directory injection is inert" dir
injection_case "Model injection is inert" model
injection_case "Effort injection is inert" effort
# Preserve ordinary multibyte display text.
run_case "Multibyte directory is preserved" 'café/项目' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/café/项目"},"context_window":{"used_percentage":20}}'
run_case "Multibyte model is preserved" 'Gémini → x' \
  '{"model":{"display_name":"Gémini → x"},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20}}'

section "Thinking field injection"
thinking_forge_case "String thinking cannot forge MODEL" \
  MODEL PWNED 'Opus' 'PWNED'
thinking_forge_case "String thinking cannot forge ICON_MODEL" \
  ICON_MODEL FORGED '🔮' 'FORGED'
thinking_forge_case "String thinking cannot forge PATH" \
  PATH /nonexistent '' '/nonexistent'
# Non-booleans must not enable the thinking flag.
run_case "Non-boolean thinking is ignored" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20},"thinking":{"enabled":"maybe"}}' \
  'Thinking'

section "Non-string display fields"
run_case "Object current_dir falls back" '(Missing Directory)' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":{}},"context_window":{"used_percentage":20}}'
run_case "Object current_dir preserves context" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":{}},"context_window":{"used_percentage":20}}' \
  '???%'
run_case "Object display_name preserves context" '20%' \
  '{"model":{"display_name":{}},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20}}' \
  '???%'
run_case "Array display_name preserves context" '20%' \
  '{"model":{"display_name":[]},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20}}' \
  '???%'
run_case "Numeric display_name preserves context" '20%' \
  '{"model":{"display_name":5},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20}}' \
  '???%'
run_case "Boolean display_name preserves context" '20%' \
  '{"model":{"display_name":true},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20}}' \
  '???%'
run_case "Non-string display_name falls back" '(Missing Model)' \
  '{"model":{"display_name":true},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20}}'
run_case "Null display_name preserves context" '20%' \
  '{"model":{"display_name":null},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20}}' \
  '???%'
run_case "Non-string product preserves context" '20%' \
  '{"product":{},"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20}}' \
  '???%'

section "Scalar parent fields"
run_case "Boolean model preserves directory" '/tmp/keepme' \
  '{"model":true,"workspace":{"current_dir":"/tmp/keepme"},"context_window":{"used_percentage":20}}' \
  '(Missing Directory)'
run_case "Boolean model preserves context" '20%' \
  '{"model":true,"workspace":{"current_dir":"/tmp/keepme"},"context_window":{"used_percentage":20}}' \
  '???%'
run_case "Numeric workspace preserves context" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":5,"context_window":{"used_percentage":20}}' \
  '???%'
run_case "Boolean context preserves rate gauge" '5h' \
  '{"model":{"display_name":"Opus"},"context_window":true,"rate_limits":{"five_hour":{"used_percentage":42}}}'
run_case "Boolean rate limits preserve context badge" '200K' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20,"context_window_size":200000},"rate_limits":true}'
run_case "Boolean thinking parent preserves context" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20},"thinking":true}' \
  '???%'
run_case "Boolean effort parent preserves context" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":20},"effort":true}' \
  '???%'
run_case "Boolean agy quota preserves context badge" '200K' \
  '{"product":"antigravity","model":{"display_name":"Gemini"},"context_window":{"context_window_size":200000},"quota":true}'

section "Numeric type guards"
run_case "String context percentage is unknown" '???%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":"20"}}'
run_case "String rate percentage hides gauge" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":"20"}}}' \
  '5h'
export URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1000000000
run_case "String reset hides countdown" '35%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":"soon"}}}' \
  '('
unset URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW
# Wrong-typed cache input leaves an incomplete, unwritten pair.
cache_nowrite_case "String percentage is not cached" \
  1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":"20","resets_at":1789448400}}}'

section "Rate-limit bars"
run_case "5h limit renders its bar" '5h' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":23}}}'
run_case "7d limit renders its bar" '7d' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":41}}}'
run_case "Rate percentage floors" '78%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":78.6}}}'
run_case "Both rate windows render" '7d' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":23},"seven_day":{"used_percentage":41}}}'
run_case "Missing rate limits hide gauges" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  '5h'

section "Rate-limit countdowns"
# Pin now for deterministic countdowns, then restore the real clock.
export URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1000000000
run_case "5h reset 3h42m out -> (3h42m)" '(3h42m)' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1000013320}}}'
run_case "5h expired clamps to (0h00m)" '(0h00m)' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":99,"resets_at":999999900}}}'
# An unusable reset hides the countdown, never the gauge that had data.
run_case "Exponent-form reset keeps the gauge" '5h [██▊     ] 35%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1e300}}}' \
  '('
run_case "Oversized reset keeps the gauge" '5h [██▊     ] 35%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1.8446e19}}}' \
  '('
run_case "7d reset 2d04h out stays d/h -> (2d04h)" '(2d04h)' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":41,"resets_at":1000187200}}}'
run_case "7d exactly 24h stays d/h -> (1d00h)" '(1d00h)' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":41,"resets_at":1000086400}}}'
run_case "7d just under 24h flips to h/m -> (23h59m)" '(23h59m)' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":41,"resets_at":1000086399}}}'
run_case "7d single-digit hour stays unpadded -> (9h59m)" '(9h59m)' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":41,"resets_at":1000035940}}}'
run_case "Missing reset hides countdown" '35%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":35}}}' \
  '('
unset URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW

section "Debug clock guards"
# A DEBUG_NOW the arithmetic cannot hold falls through to the real clock.
export URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=08
run_case "Octal-looking DEBUG_NOW still renders" '35%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1789448400}}}'
# An injection-shaped value must fall through, and its payload must never run.
CANARY_DIR="$(mktemp -d)"
export URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW="x[\$(touch ${CANARY_DIR}/canary)]"
run_case "Injection-shaped DEBUG_NOW still renders" '35%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1789448400}}}'
unset URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW
if [[ -e "${CANARY_DIR}/canary" ]]; then
  cache_report "Injection payload never executes" "true" \
    "canary file appeared; arithmetic evaluated the DEBUG_NOW payload"
else
  cache_report "Injection payload never executes" "false" ""
fi
rm -rf "${CANARY_DIR}"
unset CANARY_DIR

section "Agy quota"
# Agy selects a quota pool from the model and inverts remaining to used.
run_case "Agy Claude uses 3p quota" '15%' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6 (Thinking)"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"gemini-5h":{"remaining_fraction":0.40},"3p-5h":{"remaining_fraction":0.85}}}' \
  '60%'
run_case "Agy Gemini uses Gemini quota" '60%' \
  '{"product":"antigravity","model":{"display_name":"Gemini 3.1 Pro (High)"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"gemini-5h":{"remaining_fraction":0.40},"3p-5h":{"remaining_fraction":0.85}}}' \
  '15%'
run_case "Agy weekly quota drives 7d" '41%' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"3p-weekly":{"remaining_fraction":0.59}}}'
# Denoise floating-point dust before flooring.
run_case "Agy inversion denoises" '10%' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"3p-5h":{"remaining_fraction":0.90}}}'
# A genuine 12.7 inversion must floor to 12.
run_case "Agy fractional inversion floors" '12%' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"3p-5h":{"remaining_fraction":0.873}}}' \
  '13%'
# A real 12.99999 reading remains below the denoise tolerance.
run_case "Real fraction below integer floors" '12%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":12.99999,"resets_at":1789448400}}}' \
  '13%'
run_case "Agy full quota renders 0%" '0%' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":23},"quota":{"3p-5h":{"remaining_fraction":1}}}'
run_case "Missing agy quota hides rates" '20%' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  '5h'
run_case "Non-agy product blocks quota" '20%' \
  '{"model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"3p-5h":{"remaining_fraction":0.85}}}' \
  '5h'
# Selector precedence, pinned so reordering cannot silently change behavior.
run_case "Direct rate_limits beat the agy quota fallback" '30%' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":30}},"quota":{"3p-5h":{"remaining_fraction":0.5}}}' \
  '50%'
run_case "model.id selects the pool when display_name is missing" '75%' \
  '{"product":"antigravity","model":{"id":"gemini-2.5-pro"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"gemini-5h":{"remaining_fraction":0.25},"3p-5h":{"remaining_fraction":0.5}}}' \
  '50%'
run_case "display_name outranks model.id for the pool" '50%' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6","id":"gemini-2.5-pro"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"gemini-5h":{"remaining_fraction":0.25},"3p-5h":{"remaining_fraction":0.5}}}' \
  '75%'

# ISO reset_time uses the same countdown path as epoch resets.
export URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1000000000
run_case "Agy reset drives countdown" '(3h42m)' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"3p-5h":{"remaining_fraction":0.5,"reset_time":"2001-09-09T05:28:40Z"}}}'
run_case "Malformed agy reset hides countdown" '50%' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"3p-5h":{"remaining_fraction":0.5,"reset_time":"garbage"}}}' \
  '('
unset URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW

section "GitHub Copilot CLI"
# Copilot's ai_used marker gates its alternate context fields. It has no rate data.
run_case "Copilot context fallback" '26%' \
  '{"model":{"display_name":"Auto → claude-haiku-4.5"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":null,"current_context_used_percentage":26,"displayed_context_limit":128000},"ai_used":{"total_nano_aiu":0,"formatted":"0"}}'
run_case "Copilot window fallback" '[128K]' \
  '{"model":{"display_name":"Auto → claude-haiku-4.5"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":null,"current_context_used_percentage":26,"displayed_context_limit":128000},"ai_used":{"total_nano_aiu":0,"formatted":"0"}}'
run_case "Copilot null model falls back" '(Missing Model)' \
  '{"model":{"id":null,"display_name":null},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":null,"context_window_size":null},"ai_used":{"total_nano_aiu":0,"formatted":"0"}}'
run_case "Copilot missing context is unknown" '???%' \
  '{"model":{"id":null,"display_name":null},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":null,"context_window_size":null},"ai_used":{"total_nano_aiu":0,"formatted":"0"}}'
run_case "Missing Copilot marker blocks fallback" '???%' \
  '{"model":{"display_name":"Auto → claude-haiku-4.5"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":null,"current_context_used_percentage":26,"displayed_context_limit":128000}}' \
  '26%'

section "Mode indicators"
run_case "Effort shown when present" 'xhigh' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"effort":{"level":"xhigh"}}'
run_case "Effort hidden when absent" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  'xhigh'
run_case "Thinking: OFF flag shows when thinking disabled" 'Thinking: OFF' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"thinking":{"enabled":false}}'
run_case "No think flag when thinking enabled" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"thinking":{"enabled":true}}' \
  'Thinking: OFF'

section "Agy model effort"
# Agy lifts Low, Medium, or High model suffixes into effort.
run_case "Agy lifts High effort" 'high' \
  '{"product":"antigravity","model":{"display_name":"Gemini 3.1 Pro (High)"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  'High'
run_case "Agy lifts Medium effort" 'medium' \
  '{"product":"antigravity","model":{"display_name":"GPT-OSS 120B (Medium)"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  '(Medium)'
run_case "Agy lifts Low effort" 'low' \
  '{"product":"antigravity","model":{"display_name":"Gemini 3.5 Flash (Low)"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  '(Low)'
run_case "Agy strips Thinking tag" 'Claude Sonnet 4.6' \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6 (Thinking)"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  '(Thinking)'
run_case "Non-agy effort tag is preserved" 'Foo (High)' \
  '{"model":{"display_name":"Foo (High)"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
run_case "Native agy effort wins" 'xhigh' \
  '{"product":"antigravity","model":{"display_name":"Gemini 3.1 Pro (High)"},"effort":{"level":"xhigh"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'

section "Sub-cell fill and readout width"
# Nonzero values receive at least one eighth-cell; readouts stay three columns.
run_case "1% draws a one-eighth sliver, not an empty bar" '▏' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":1}}'
run_case "Single-digit percent left-pads to three columns" '  2%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":2}}'
run_case "100% readout sits flush against the bracket" ']100%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":100}}'

section "Block icons"
# Every icon must remain present and U+FE0F-free.
run_case "Model icon" '🔮' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
run_case "Context icon" '🧠' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
run_case "Directory icon" '💾' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
run_case "Effort icon rides with the effort segment" '🦾' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"effort":{"level":"high"}}'
run_case "Thinking icon rides with the off flag" '🚫' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"thinking":{"enabled":false}}'
run_case "5h rate icon" '⏳' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":23}}}'
run_case "7d rate icon" '🪔' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":41}}}'
# Octal UTF-8 bytes keep the U+FE0F assertion Bash 3.2-compatible.
run_case "No U+FE0F variation selector anywhere" '🔮' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"effort":{"level":"high"},"thinking":{"enabled":false},"rate_limits":{"five_hour":{"used_percentage":23},"seven_day":{"used_percentage":41}}}' \
  $'\357\270\217'

# The Emoji_Presentation snapshot below is from UCD emoji-data.txt
# (fetched 2026-07-27); re-snapshot when adding an icon Unicode does not know.
EMOJI_PRESENTATION_RANGES='231A-231B,23E9-23EC,23F0-23F0,23F3-23F3,25FD-25FE,2614-2615,2648-2653,267F-267F,2693-2693,26A1-26A1,26AA-26AB,26BD-26BE,26C4-26C5,26CE-26CE,26D4-26D4,26EA-26EA,26F2-26F3,26F5-26F5,26FA-26FA,26FD-26FD,2705-2705,270A-270B,2728-2728,274C-274C,274E-274E,2753-2755,2757-2757,2795-2797,27B0-27B0,27BF-27BF,2B1B-2B1C,2B50-2B50,2B55-2B55,1F004-1F004,1F0CF-1F0CF,1F18E-1F18E,1F191-1F19A,1F1E6-1F1FF,1F201-1F201,1F21A-1F21A,1F22F-1F22F,1F232-1F236,1F238-1F23A,1F250-1F251,1F300-1F30C,1F30D-1F30E,1F30F-1F30F,1F310-1F310,1F311-1F311,1F312-1F312,1F313-1F315,1F316-1F318,1F319-1F319,1F31A-1F31A,1F31B-1F31B,1F31C-1F31C,1F31D-1F31E,1F31F-1F320,1F32D-1F32F,1F330-1F331,1F332-1F333,1F334-1F335,1F337-1F34A,1F34B-1F34B,1F34C-1F34F,1F350-1F350,1F351-1F37B,1F37C-1F37C,1F37E-1F37F,1F380-1F393,1F3A0-1F3C4,1F3C5-1F3C5,1F3C6-1F3C6,1F3C7-1F3C7,1F3C8-1F3C8,1F3C9-1F3C9,1F3CA-1F3CA,1F3CF-1F3D3,1F3E0-1F3E3,1F3E4-1F3E4,1F3E5-1F3F0,1F3F4-1F3F4,1F3F8-1F407,1F408-1F408,1F409-1F40B,1F40C-1F40E,1F40F-1F410,1F411-1F412,1F413-1F413,1F414-1F414,1F415-1F415,1F416-1F416,1F417-1F429,1F42A-1F42A,1F42B-1F43E,1F440-1F440,1F442-1F464,1F465-1F465,1F466-1F46B,1F46C-1F46D,1F46E-1F4AC,1F4AD-1F4AD,1F4AE-1F4B5,1F4B6-1F4B7,1F4B8-1F4EB,1F4EC-1F4ED,1F4EE-1F4EE,1F4EF-1F4EF,1F4F0-1F4F4,1F4F5-1F4F5,1F4F6-1F4F7,1F4F8-1F4F8,1F4F9-1F4FC,1F4FF-1F502,1F503-1F503,1F504-1F507,1F508-1F508,1F509-1F509,1F50A-1F514,1F515-1F515,1F516-1F52B,1F52C-1F52D,1F52E-1F53D,1F54B-1F54E,1F550-1F55B,1F55C-1F567,1F57A-1F57A,1F595-1F596,1F5A4-1F5A4,1F5FB-1F5FF,1F600-1F600,1F601-1F606,1F607-1F608,1F609-1F60D,1F60E-1F60E,1F60F-1F60F,1F610-1F610,1F611-1F611,1F612-1F614,1F615-1F615,1F616-1F616,1F617-1F617,1F618-1F618,1F619-1F619,1F61A-1F61A,1F61B-1F61B,1F61C-1F61E,1F61F-1F61F,1F620-1F625,1F626-1F627,1F628-1F62B,1F62C-1F62C,1F62D-1F62D,1F62E-1F62F,1F630-1F633,1F634-1F634,1F635-1F635,1F636-1F636,1F637-1F640,1F641-1F644,1F645-1F64F,1F680-1F680,1F681-1F682,1F683-1F685,1F686-1F686,1F687-1F687,1F688-1F688,1F689-1F689,1F68A-1F68B,1F68C-1F68C,1F68D-1F68D,1F68E-1F68E,1F68F-1F68F,1F690-1F690,1F691-1F693,1F694-1F694,1F695-1F695,1F696-1F696,1F697-1F697,1F698-1F698,1F699-1F69A,1F69B-1F6A1,1F6A2-1F6A2,1F6A3-1F6A3,1F6A4-1F6A5,1F6A6-1F6A6,1F6A7-1F6AD,1F6AE-1F6B1,1F6B2-1F6B2,1F6B3-1F6B5,1F6B6-1F6B6,1F6B7-1F6B8,1F6B9-1F6BE,1F6BF-1F6BF,1F6C0-1F6C0,1F6C1-1F6C5,1F6CC-1F6CC,1F6D0-1F6D0,1F6D1-1F6D2,1F6D5-1F6D5,1F6D6-1F6D7,1F6D8-1F6D8,1F6DC-1F6DC,1F6DD-1F6DF,1F6EB-1F6EC,1F6F4-1F6F6,1F6F7-1F6F8,1F6F9-1F6F9,1F6FA-1F6FA,1F6FB-1F6FC,1F7E0-1F7EB,1F7F0-1F7F0,1F90C-1F90C,1F90D-1F90F,1F910-1F918,1F919-1F91E,1F91F-1F91F,1F920-1F927,1F928-1F92F,1F930-1F930,1F931-1F932,1F933-1F93A,1F93C-1F93E,1F93F-1F93F,1F940-1F945,1F947-1F94B,1F94C-1F94C,1F94D-1F94F,1F950-1F95E,1F95F-1F96B,1F96C-1F970,1F971-1F971,1F972-1F972,1F973-1F976,1F977-1F978,1F979-1F979,1F97A-1F97A,1F97B-1F97B,1F97C-1F97F,1F980-1F984,1F985-1F991,1F992-1F997,1F998-1F9A2,1F9A3-1F9A4,1F9A5-1F9AA,1F9AB-1F9AD,1F9AE-1F9AF,1F9B0-1F9B9,1F9BA-1F9BF,1F9C0-1F9C0,1F9C1-1F9C2,1F9C3-1F9CA,1F9CB-1F9CB,1F9CC-1F9CC,1F9CD-1F9CF,1F9D0-1F9E6,1F9E7-1F9FF,1FA70-1FA73,1FA74-1FA74,1FA75-1FA77,1FA78-1FA7A,1FA7B-1FA7C,1FA80-1FA82,1FA83-1FA86,1FA87-1FA88,1FA89-1FA89,1FA8A-1FA8A,1FA8E-1FA8E,1FA8F-1FA8F,1FA90-1FA95,1FA96-1FAA8,1FAA9-1FAAC,1FAAD-1FAAF,1FAB0-1FAB6,1FAB7-1FABA,1FABB-1FABD,1FABE-1FABE,1FABF-1FABF,1FAC0-1FAC2,1FAC3-1FAC5,1FAC6-1FAC6,1FAC8-1FAC8,1FACD-1FACD,1FACE-1FACF,1FAD0-1FAD6,1FAD7-1FAD9,1FADA-1FADB,1FADC-1FADC,1FADF-1FADF,1FAE0-1FAE7,1FAE8-1FAE8,1FAE9-1FAE9,1FAEA-1FAEA,1FAEF-1FAEF,1FAF0-1FAF6,1FAF7-1FAF8'

icon_property_case() {
  #   icon_property_case <label>
  # Every default icon must be exactly one code point, emoji-presentation by
  # default, and double-width: astral, or the U+23F3 hourglass, the sole BMP
  # icon, cleared by East_Asian_Width=Wide in the UCD.
  local label="${1}" failed="false" reason=""
  reason="$(EP_RANGES="${EMOJI_PRESENTATION_RANGES}" perl -CSD -ne '
    BEGIN { @ep = map { [map { hex } split /-/] } split /,/, $ENV{EP_RANGES}; }
    next unless /^ICON_([A-Z0-9_]+)="\$\{[A-Z0-9_]+:-(.*)\}"$/;
    $n++;
    my ($name, $glyph) = ($1, $2);
    my @cps = split //, $glyph;
    if (@cps != 1) { print "ICON_$name is not exactly one code point\n"; next }
    my $cp = ord($cps[0]);
    my $is_ep = 0;
    for my $r (@ep) { if ($cp >= $r->[0] && $cp <= $r->[1]) { $is_ep = 1; last } }
    printf "ICON_%s U+%04X is not emoji-presentation-default\n", $name, $cp unless $is_ep;
    if ($cp <= 0xFFFF && $cp != 0x23F3) {
      printf "ICON_%s U+%04X is BMP without a width clearance\n", $name, $cp;
    }
    END { print "expected 10 ICON_ defaults, saw ${\ ($n // 0)}\n" if ($n // 0) != 10 }
  ' "${STATUSLINE}")"
  if [[ -n "${reason}" ]]; then
    failed="true"
    reason="${reason//$'\n'/; }"
  fi
  cache_report "${label}" "${failed}" "${reason}"
}
icon_property_case "Default icons are single wide emoji-presentation code points"

section "Icon escalation"
run_case "Below warn keeps the calm icon (49 -> 🧠)" '🧠' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":49}}' \
  '🟡'
run_case "Warn boundary flips to caution (50 -> 🟡)" '🟡' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":50}}' \
  '🧠'
run_case "Upper warn band still caution (79 -> 🟡)" '🟡' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":79}}'
run_case "Alarm boundary flips to alarm (80 -> 🔴)" '🔴' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":80}}' \
  '🟡'
# One payload exercises all three severity tiers.
run_case "Per-gauge: context alarm 🔴 (90)" '🔴' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":90},"rate_limits":{"five_hour":{"used_percentage":70},"seven_day":{"used_percentage":20}}}'
run_case "Per-gauge: 5h warn 🟡 (70) in the same render" '🟡' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":90},"rate_limits":{"five_hour":{"used_percentage":70},"seven_day":{"used_percentage":20}}}'
run_case "Per-gauge: 7d stays calm 🪔 (20) in the same render" '🪔' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":90},"rate_limits":{"five_hour":{"used_percentage":70},"seven_day":{"used_percentage":20}}}'
# Escalated glyphs follow the same selector rule.
run_case "Escalated icons carry no U+FE0F" '🔴' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":90},"rate_limits":{"five_hour":{"used_percentage":70},"seven_day":{"used_percentage":20}}}' \
  $'\357\270\217'

section "Context startup glyph"
run_case "Unknown context uses startup glyph" '🌀' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"}}' \
  '🧠'
run_case "Real 0% uses context glyph" '🧠' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":0}}' \
  '🌀'
run_case "Unknown context does not warn" '🌀' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"}}' \
  '🟡'
run_case "Startup glyph carries no U+FE0F" '🌀' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"}}' \
  $'\357\270\217'

section "Icon overrides"
# Require each replacement and forbid its default.
run_icon_override "Model icon override" \
  URDA_AI_FORGED_STATUS_LINE_ICON_MODEL '🤖' '🔮' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
run_icon_override "Context icon override (calm)" \
  URDA_AI_FORGED_STATUS_LINE_ICON_CONTEXT '📚' '🧠' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
run_icon_override "Context-unknown icon override (???)" \
  URDA_AI_FORGED_STATUS_LINE_ICON_CONTEXT_UNKNOWN '💤' '🌀' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"}}'
run_icon_override "Directory icon override" \
  URDA_AI_FORGED_STATUS_LINE_ICON_DIR '📁' '💾' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
run_icon_override "Effort icon override" \
  URDA_AI_FORGED_STATUS_LINE_ICON_EFFORT '🔥' '🦾' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"effort":{"level":"high"}}'
run_icon_override "Thinking icon override" \
  URDA_AI_FORGED_STATUS_LINE_ICON_THINKING '🛑' '🚫' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"thinking":{"enabled":false}}'
run_icon_override "5h rate icon override (calm)" \
  URDA_AI_FORGED_STATUS_LINE_ICON_RATE_5H '🕐' '⏳' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":20}}}'
run_icon_override "7d rate icon override (calm)" \
  URDA_AI_FORGED_STATUS_LINE_ICON_RATE_7D '📅' '🪔' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":20}}}'
run_icon_override "Warn icon override (gauge in warn band)" \
  URDA_AI_FORGED_STATUS_LINE_ICON_WARN '🔶' '🟡' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":65}}'
run_icon_override "Alarm icon override (gauge in alarm band)" \
  URDA_AI_FORGED_STATUS_LINE_ICON_ALARM '🟥' '🔴' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":85}}'

section "Threshold overrides"
# Fixed percentages expose valid and invalid threshold overrides.
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN=60
run_case "Raised warn keeps 55% calm" '🧠' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":55}}' \
  '🟡'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_ALARM=65
run_case "Lowered alarm escalates 70%" '🔴' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":70}}' \
  '🟡'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_ALARM
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN=08
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_ALARM=09
run_case "Zero-padded thresholds use decimal values" '🔴' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":9}}'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN URDA_AI_FORGED_STATUS_LINE_THRESHOLD_ALARM
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN=abc
run_case "Non-numeric warn uses defaults" '🟡' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":55}}'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN=999999999999999999999999
run_case "Oversized warn uses defaults" '🧠' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  '🟡'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN=800
run_case "Out-of-range warn uses defaults" '🟡' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":55}}'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN=90
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_ALARM=50
run_case "Out-of-order thresholds use defaults" '🟡' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":55}}'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN URDA_AI_FORGED_STATUS_LINE_THRESHOLD_ALARM

section "Per-gauge thresholds"
# All three gauges sit at 55, so the shared 50/80 pair warns every one of them.
# Rate gauges carry their label next to the icon, and the context gauge opens
# row 2, so each assertion below pins one gauge rather than the whole row.
_TRI_55='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":55},"rate_limits":{"five_hour":{"used_percentage":55},"seven_day":{"used_percentage":55}}}'

run_case "Shared pair warns the context gauge" '🟡 [' "${_TRI_55}"
run_case "Shared pair warns the 5h gauge" '🟡 5h' "${_TRI_55}"
run_case "Shared pair warns the 7d gauge" '🟡 7d' "${_TRI_55}"

export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_WARN=60
run_case "Context override calms context, not 5h" '🧠 [' "${_TRI_55}" '⏳'
run_case "Context override leaves 5h warning" '🟡 5h' "${_TRI_55}"
run_case "Context override leaves 7d warning" '🟡 7d' "${_TRI_55}"
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_WARN

export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN=60
run_case "5h override calms 5h, not context" '⏳ 5h' "${_TRI_55}" '🧠'
run_case "5h override leaves 7d warning" '🟡 7d' "${_TRI_55}"
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN

export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_7D_WARN=60
run_case "7d override calms 7d, not context" '🪔 7d' "${_TRI_55}" '🧠'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_7D_WARN

# A lone alarm override pairs with the shared warn.
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_7D_ALARM=52
run_case "7d alarm override escalates only 7d" '🔴 7d' "${_TRI_55}" '🔴 5h'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_7D_ALARM

# The shared pair still governs every gauge that does not override it.
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN=60
run_case "Shared override alone calms every gauge" '🧠 [' "${_TRI_55}" '🟡'
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN=50
run_case "Per-gauge pair beats the shared pair" '🟡 5h' "${_TRI_55}" '🟡 ['
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN

# An unusable per-gauge pair falls back instead of disabling the bands.
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN=abc
run_case "Non-numeric per-gauge falls back to shared" '🟡 5h' "${_TRI_55}"
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN=800
run_case "Out-of-range per-gauge falls back to shared" '🟡 5h' "${_TRI_55}"
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN=90
run_case "Per-gauge warn above shared alarm falls back" '🟡 5h' "${_TRI_55}"
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_7D_ALARM=50
run_case "Per-gauge pair that is not increasing falls back" '🟡 7d' "${_TRI_55}" '🔴 7d'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_7D_ALARM

# A valid per-gauge pair still applies when the shared override is junk.
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN=abc
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN=10
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_ALARM=20
run_case "Valid per-gauge pair survives a junk shared pair" '🔴 5h' "${_TRI_55}"
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_ALARM

export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN=06
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_ALARM=07
run_case "Zero-padded per-gauge values are decimal" '🔴 5h' "${_TRI_55}"
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_ALARM

# One gauge per band, and each color byte anchored to its gauge's own label,
# so swapping two lookups fails even though all three colors stay present.
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_WARN=10
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_ALARM=20
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN=60
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_ALARM=90
run_theme_case "Context bar takes its own alarm color" '' $'\033[90m[\033[31m' '' "${_TRI_55}"
run_theme_case "5h bar takes its own calm color" '' $'\033[90m5h\033[0m \033[90m[\033[32m' '' "${_TRI_55}"
run_theme_case "7d bar takes the shared warn color" '' $'\033[90m7d\033[0m \033[90m[\033[33m' '' "${_TRI_55}"
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_WARN URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_ALARM
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_ALARM

# Thresholds never turn an unknown reading into a severity.
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_WARN=10
export URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_ALARM=20
run_case "Per-gauge override leaves unknown context unknown" '🌀' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"}}' \
  '🔴'
unset URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_WARN URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_ALARM

section "Icon master switch"
# Icon removal must preserve data, colors, and single-space layout.
export URDA_AI_FORGED_STATUS_LINE_ICONS=0
run_case "Switch off drops the model icon, keeps the model" 'Opus' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  '🔮'
run_case "Switch off drops the context icon, keeps its bar" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  '🧠'
run_case "Icons-off preserves spacing" 'Opus high' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"effort":{"level":"high"}}' \
  '🦾'
run_case "Icons-off keeps thinking text" 'Thinking: OFF' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"thinking":{"enabled":false}}' \
  '🚫'
run_case "Icons-off drops escalated icons" '80%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":80}}' \
  '🔴'
run_case "Switch off drops rate icons, keeps the 5h gauge" '5h' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":23}}}' \
  '⏳'
unset URDA_AI_FORGED_STATUS_LINE_ICONS
export URDA_AI_FORGED_STATUS_LINE_ICONS=banana
run_case "Junk icon switch keeps icons" '🔮' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
unset URDA_AI_FORGED_STATUS_LINE_ICONS

section "Context-size badge"
# Badge only sub-1M windows; strip the legacy 1M suffix without badging it.
run_case "Legacy 1M suffix is stripped" 'Opus 4.8' \
  '{"model":{"display_name":"Opus 4.8 (1M context)"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":1000000}}' \
  '1M'
run_case "Legacy 1M name, size field absent: still no badge" 'Opus 4.8' \
  '{"model":{"display_name":"Opus 4.8 (1M context)"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  '1M'
run_case "Plain name + 1M size: no badge" 'Fable 5' \
  '{"model":{"display_name":"Fable 5"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":1000000}}' \
  '1M'
run_case "200K window gets badge" 'Sonnet 4.6 [200K]' \
  '{"model":{"display_name":"Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":200000}}'
run_case "250K agy window gets badge" 'Claude Opus 4.6 [250K]' \
  '{"model":{"display_name":"Claude Opus 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":250000}}'
run_case "131072 window uses decimal units" 'GPT-OSS 120B [131K]' \
  '{"model":{"display_name":"GPT-OSS 120B"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":131072}}' \
  '128K'
run_case "131500 rounds half-up to 132K" 'GPT-OSS 120B [132K]' \
  '{"model":{"display_name":"GPT-OSS 120B"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":131500}}' \
  '[131K]'
run_case "131499 rounds down to 131K" 'GPT-OSS 120B [131K]' \
  '{"model":{"display_name":"GPT-OSS 120B"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":131499}}' \
  '[132K]'
run_case "agy loading (size 0): no badge, line still renders" '0%' \
  '{"model":{"display_name":"Claude Opus 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":0,"context_window_size":0}}' \
  'K]'
run_case "Future >1M size (2M): still no badge" 'Opus' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":2000000}}' \
  'M]'
run_case "Plain name, size absent: no badge" 'Opus' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}' \
  'K]'
run_case "String window size is ignored" '20%' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":"huge"}}' \
  'K]'
export URDA_AI_FORGED_STATUS_LINE_ICONS=0
run_case "Badge survives icons-off (data, not an icon)" 'Fable 5 [250K]' \
  '{"model":{"display_name":"Fable 5"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20,"context_window_size":250000}}' \
  '🔮'
unset URDA_AI_FORGED_STATUS_LINE_ICONS

section "Theme"
# Judge theme changes on raw color bytes.
run_theme_case "Light retints gray separators (90m -> 240m)" \
  light $'\033[38;5;240m' $'\033[90m' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":20}}'
run_theme_case "Light model name uses default fg (37m -> 39m)" \
  light $'\033[39m' $'\033[37m' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":20}}'
run_theme_case "Default (theme unset) stays dark" \
  '' $'\033[90m' $'\033[38;5;240m' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":20}}'
run_theme_case "Junk theme stays dark" \
  chartreuse $'\033[90m' $'\033[38;5;240m' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":20}}'
run_theme_case "Light retints cyan badges to dark teal (36m -> 38;5;30m)" \
  light $'\033[38;5;30m' $'\033[36m' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":20,"context_window_size":200000},"effort":{"level":"high"}}'
# Light mode and icon removal remain independent.
export URDA_AI_FORGED_STATUS_LINE_ICONS=0
run_theme_case "Light survives icons-off (retint holds, line non-empty)" \
  light $'\033[38;5;240m' '' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/dev/urda/forged-statusline"},"context_window":{"used_percentage":20}}'
unset URDA_AI_FORGED_STATUS_LINE_ICONS

section "Rate-limit cache"
# Cache cases require raw percentages, floored resets, and omitted absent windows.
cache_write_case "Claude cache schema" \
  1789430400 cache-claude.json \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"five_hour":{"used_percentage":32.5,"resets_at":1789448400},"seven_day":{"used_percentage":9.5,"resets_at":1789887600}}}' \
  '.schema=1' '.written_at=1789430400' \
  '.rate_5h_pct=32.5' '.rate_5h_reset=1789448400' \
  '.rate_7d_pct=9.5' '.rate_7d_reset=1789887600'
agy_pool_case "Agy pools cache independently across a model switch"
cache_write_case "Agy cache normalization" \
  1700000000 cache-agy-3p.json \
  '{"product":"antigravity","model":{"display_name":"Claude Sonnet 4.6"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"quota":{"3p-5h":{"remaining_fraction":0.5,"reset_time":"2026-07-14T00:00:00Z"},"3p-weekly":{"remaining_fraction":0.75,"reset_time":"2026-07-20T00:00:00Z"}}}' \
  '.schema=1' '.written_at=1700000000' \
  '.rate_5h_pct=50' '.rate_5h_reset=1783987200' \
  '.rate_7d_pct=25' '.rate_7d_reset=1784505600'
cache_write_case "Partial cache omits absent window" \
  1789430400 cache-claude.json \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":55.5,"resets_at":1789448400}}}' \
  '.rate_5h_pct=55.5' '.rate_5h_reset=1789448400' \
  'has("rate_7d_pct")=false' 'has("rate_7d_reset")=false'
cache_monotonic_case "Stale cache update is rejected"
# Within one window the reset never moves while the percentage climbs, so an
# equal reset must replace, not be mistaken for stale.
cache_second_case "Equal 5h reset still updates the percentage" \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1789448400}}}' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":99,"resets_at":1789448400}}}' \
  '.rate_5h_pct' '99'
cache_second_case "Equal 7d reset still updates the percentage" \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":1789887600}}}' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"seven_day":{"used_percentage":55,"resets_at":1789887600}}}' \
  '.rate_7d_pct' '55'
# The writer's digit fence sits at MAX_SAFE_DIGITS: the widest passing value
# is written raw, one column more is not.
cache_write_case "Fifteen-digit reset is cached" \
  1789430400 cache-claude.json \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":999999999999999}}}' \
  '.rate_5h_pct=40' '.rate_5h_reset=999999999999999'
cache_nowrite_case "Sixteen-digit reset is not cached" \
  1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1000000000000000}}}'
cache_nowrite_case "Exact 2^53 percentage is not cached" \
  1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":9007199254740992,"resets_at":1789448400}}}'
# The reader must reject exactly 2^53 too: a seeded cached reset at the
# ceiling may not outrank fresh, smaller, real data.
cache_seeded_reader_case "Reader rejects a seeded reset of exactly 2^53" \
  '{"schema":1,"written_at":1789430300,"rate_5h_pct":40,"rate_5h_reset":9007199254740992}' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":55,"resets_at":1789448400}}}' \
  '.rate_5h_reset' '1789448400'
cache_nowrite_case "Disabled cache writes nothing" \
  "" \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"five_hour":{"used_percentage":32.5,"resets_at":1789448400}}}'
cache_nowrite_case "Copilot cache writes nothing" \
  1 \
  '{"model":{"display_name":"Auto → claude-haiku-4.5"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":null,"current_context_used_percentage":26,"displayed_context_limit":128000},"ai_used":{"total_nano_aiu":0,"formatted":"0"}}'
cache_nowrite_case "Percentage-only window is not cached" \
  1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"five_hour":{"used_percentage":32.5}}}'
cache_nowrite_case "Reset-only window is not cached" \
  1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"five_hour":{"resets_at":1789448400}}}'
# The writer never publishes a number its own reader would reject.
cache_nowrite_case "Negative percentage is not cached" \
  1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"five_hour":{"used_percentage":-1,"resets_at":1789448400}}}'
cache_nowrite_case "Exponent-form percentage is not cached" \
  1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"five_hour":{"used_percentage":1e20,"resets_at":1789448400}}}'
cache_nowrite_case "Negative 7d percentage is not cached" \
  1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"seven_day":{"used_percentage":-1,"resets_at":1789887600}}}'
cache_nowrite_case "Oversized reset is not cached" \
  1 \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1.8446e19}}}'
cache_write_case "Unfloored percentage survives sanitizing" \
  1789430400 cache-claude.json \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":9.999999999999998,"resets_at":1789448400}}}' \
  '.rate_5h_pct=9.999999999999998' '.rate_5h_reset=1789448400'
cache_preserve_case "Incomplete window preserves cache"
# Nothing usable on disk and nothing usable incoming means the file goes.
cache_discard_case "Unreplaceable half window is discarded" \
  '{"schema":1,"written_at":1,"rate_5h_pct":10}'
cache_discard_case "Unreplaceable junk cache is discarded" \
  'NOT JSON'
# A render with no rate fields at all must also discard, not skip the file.
cache_discard_case "Rate-free render discards unreadable cache" \
  'NOT JSON' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}'
cache_keep_case "Rate-free render leaves a readable cache untouched" \
  '{"schema":1,"written_at":1,"rate_5h_pct":40,"rate_5h_reset":1789448400}' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}'
cache_selfheal_case "Corrupt cache replaced: unparseable bytes" \
  'NOT JSON'
cache_selfheal_case "Corrupt cache replaced: JSON string" \
  '"NOT AN OBJECT"'
cache_selfheal_case "Corrupt cache replaced: JSON array" \
  '[1,2,3]'
cache_selfheal_case "Corrupt cache replaced: JSON number" \
  '123'
cache_selfheal_case "Corrupt cache replaced: off-schema reset" \
  '{"schema":1,"rate_5h_pct":10,"rate_5h_reset":"oops"}'
cache_selfheal_case "Corrupt cache replaced: array reset" \
  '{"schema":1,"rate_5h_pct":10,"rate_5h_reset":[1]}'
cache_selfheal_case "Corrupt cache replaced: reset without its percentage" \
  '{"rate_5h_reset":9999999999}'
cache_selfheal_case "Corrupt cache replaced: percentage without its reset" \
  '{"rate_5h_pct":10}'
cache_selfheal_case "Corrupt cache replaced: out-of-range exponent reset" \
  '{"rate_5h_pct":10,"rate_5h_reset":1e20}'
cache_selfheal_case "Corrupt cache replaced: negative reset" \
  '{"rate_5h_pct":10,"rate_5h_reset":-1}'
# The leading reset is newer than the incoming one and the trailing reset is
# older, so only reading the first can reject the update and keep pct 10.
cache_normalize_case "Concatenated documents: only the first is read" \
  '{"rate_5h_pct":10,"rate_5h_reset":1789500000}{"rate_5h_pct":11,"rate_5h_reset":1700000000}' \
  '.rate_5h_pct' '10'
# A fractional reset must never reach the Bash comparisons.
cache_normalize_case "Fractional cached reset is floored, not carried through" \
  '{"rate_5h_pct":10,"rate_5h_reset":1789449000.5}' \
  '.rate_5h_reset' '1789449000'
cache_fidelity_case "Cache writes preserve render bytes" \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"five_hour":{"used_percentage":32.5,"resets_at":1000013320},"seven_day":{"used_percentage":9.5,"resets_at":1000187200}}}'
# umask 077 plus mktemp keep the written cache private.
PERM_JAIL="$(mktemp -d)"
render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1789448400}}}' \
  URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 \
  URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${PERM_JAIL}" \
  URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
perm_case "Cache file lands private (0600)" "${PERM_JAIL}/cache-claude.json"
remove_jail "${PERM_JAIL}"
unset PERM_JAIL
# The cache writer mirrors the directory stance: empty heals, non-empty
# is refused untouched.
cache_dir_case() {
  #   cache_dir_case <label> <mode: heal|full>
  local label="${1}" mode="${2}" jail failed="false" reason=""
  jail="$(mktemp -d)"
  mkdir "${jail}/cache-claude.json"
  if [[ "${mode}" == "full" ]]; then
    printf 'keep' > "${jail}/cache-claude.json/data"
  fi
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":1789448400}}}' \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1 \
    URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR="${jail}" \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  if [[ "${mode}" == "heal" ]]; then
    if [[ ! -f "${jail}/cache-claude.json" ]]; then
      failed="true"
      reason="empty planted dir was not healed into a cache file"
    elif ! jq -e '.rate_5h_pct == 35' "${jail}/cache-claude.json" >/dev/null 2>&1; then
      failed="true"
      reason="healed cache file does not read back"
    fi
  else
    if [[ ! -f "${jail}/cache-claude.json/data" || "$(<"${jail}/cache-claude.json/data")" != "keep" ]]; then
      failed="true"
      reason="contents of a non-empty planted dir were disturbed"
    elif [[ "$(ls -A "${jail}/cache-claude.json")" != "data" ]]; then
      failed="true"
      reason="extra files landed inside the refused dir: $(ls -A "${jail}/cache-claude.json")"
    fi
  fi
  remove_jail "${jail}"
  cache_report "${label}" "${failed}" "${reason}"
}
cache_dir_case "Empty planted dir at the cache path self-heals" heal
cache_dir_case "Non-empty dir at the cache path is refused, contents intact" full

section "Update checker"
# Badge cases exercise only the synchronous cached-version comparison.
update_badge_case "Newer remote cached: badge shows [FSL Update Available]" \
  "1.1.0" "" "" '[FSL Update Available]' "" \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
update_badge_case "Remote equals local: no badge" \
  "1.0.0" "" "" "" '[FSL' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
update_badge_case "Older remote cached: no badge" \
  0.9.0 '' '' 'Opus' '[FSL Update Available]' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
update_badge_case "No cached remote at all: no badge" \
  "" "" "" "" '[FSL' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
update_badge_case "Disabled checker hides cached badge" \
  "1.1.0" "" "0" "" '[FSL' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
update_badge_case "Current local version clears badge" \
  "1.1.0" "1.1.0" "" "" '[FSL' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'
update_badge_case "Hostile cached remote_version injection is inert" \
  $'9.9.9\033[5;41;97m FAKE-ALERT \033[0m' "" "" '[FSL Update Available]' "FAKE-ALERT" \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":20}}'

# Background fetches update state and release their lock.
update_dispatch_case "Due check writes version and timestamp" \
  1700000000 ok "9.9.9"
update_dispatch_case "Failed fetch advances timestamp only" \
  1700000000 fail ""
export URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE=1
update_dispatch_case "Cache writing does not block update checks" \
  1700000000 ok "9.9.9"
unset URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE
update_dispatch_case "Stale lock is reclaimed" \
  1700000000 ok "9.9.9" 120

# Fresh state blocks duplicate fetches.
update_no_dispatch_case "Fresh timestamp blocks dispatch" \
  1700000000 1699999900
update_no_dispatch_case "Fresh lock blocks dispatch" \
  1700000000 "" 5
update_no_dispatch_case "One second under the interval still blocks" \
  1700000000 1699395201
update_interval_fire_case "Exactly the interval re-arms the check" \
  1700000000 604800

# The default checker URL must not redirect.
url_default_case

# A successful fetch still needs a strict X.Y.Z body before it is cached.
update_dispatch_case "Valid version body is cached" \
  1700000000 body "2.3.4" "" "2.3.4"
update_dispatch_case "Junk version body is rejected" \
  1700000000 body "" "" "garbage"
update_dispatch_case "Partial version body is rejected" \
  1700000000 body "" "" "1.0"
update_dispatch_case "HTML version body is rejected" \
  1700000000 body "" "" "<html><body>404 Not Found</body></html>"

# A downloader-less attempt advances the throttle, then the fresh check holds.
update_nocurl_case "Missing downloader advances throttle once" \
  1700000000
update_curl_case "Curl fetches and caches version" \
  1700000000
update_wget_case "Wget fetches and caches version" \
  1700000000

# --update self-swaps a valid renderer, rejects anything else, never half-writes.
update_self_case "Self-update accepts renderer" \
  good true
update_self_case "Self-update rejects invalid Bash" \
  junk false
update_self_case "Self-update rejects unrelated Bash" \
  wrong-identity false
update_self_case "Self-update rejects a truncated renderer" \
  truncated false
update_self_nodl_case "Self-update requires a downloader"
update_self_curl_case "Self-update supports curl (exact argv)"
update_self_wget_case "Self-update supports wget"
update_self_chmodfail_case "Self-update aborts when chmod fails, script left intact"
update_self_mvfail_case "Self-update failed swap preserves the original byte-for-byte"

version_file_case
tail_anchor_case
stat_order_case
grep_pipe_case
update_fidelity_case "Update checks preserve render bytes" \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"__HOME__/x"},"context_window":{"used_percentage":28},"rate_limits":{"five_hour":{"used_percentage":32.5,"resets_at":1000013320}}}'
# umask 077 plus mktemp keep the update-check state private.
PERM_JAIL="$(mktemp -d)"
PERM_FIXTURE="$(mktemp -d)"
printf '9.9.9' > "${PERM_FIXTURE}/VERSION"
render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}' \
  URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
  URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${PERM_JAIL}" \
  URDA_AI_FORGED_STATUS_LINE_VERSION_URL="file://${PERM_FIXTURE}/VERSION" \
  URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
perm_case "Update state last_check lands private (0600)" "${PERM_JAIL}/last_check"
perm_case "Update state remote_version lands private (0600)" "${PERM_JAIL}/remote_version"
remove_jail "${PERM_JAIL}" "${PERM_FIXTURE}"
# A pre-existing world-readable last_check goes private on the next write.
PERM_JAIL="$(mktemp -d)"
PERM_FIXTURE="$(mktemp -d)"
printf '9.9.9' > "${PERM_FIXTURE}/VERSION"
printf '1' > "${PERM_JAIL}/last_check"
chmod 644 "${PERM_JAIL}/last_check"
render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}' \
  URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
  URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${PERM_JAIL}" \
  URDA_AI_FORGED_STATUS_LINE_VERSION_URL="file://${PERM_FIXTURE}/VERSION" \
  URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
perm_case "Existing 0644 last_check goes private on rewrite" "${PERM_JAIL}/last_check"
remove_jail "${PERM_JAIL}" "${PERM_FIXTURE}"
# A symlink planted at last_check is replaced, never written through.
PERM_JAIL="$(mktemp -d)"
PERM_FIXTURE="$(mktemp -d)"
printf '9.9.9' > "${PERM_FIXTURE}/VERSION"
printf 'untouched' > "${PERM_JAIL}/decoy"
ln -s "${PERM_JAIL}/decoy" "${PERM_JAIL}/last_check"
render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}' \
  URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
  URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${PERM_JAIL}" \
  URDA_AI_FORGED_STATUS_LINE_VERSION_URL="file://${PERM_FIXTURE}/VERSION" \
  URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
if [[ "$(<"${PERM_JAIL}/decoy")" != "untouched" ]]; then
  cache_report "Symlinked last_check is not written through" "true" \
    "decoy content changed; the write followed the symlink"
elif [[ -L "${PERM_JAIL}/last_check" ]]; then
  cache_report "Symlinked last_check is not written through" "true" \
    "last_check is still a symlink; mv did not replace it"
else
  cache_report "Symlinked last_check is not written through" "false" ""
fi
remove_jail "${PERM_JAIL}" "${PERM_FIXTURE}"
# A planted directory at last_check: an empty one self-heals via rmdir, a
# non-empty one is refused with its contents intact, and a directory symlink
# is refused without touching its target.
dir_target_case() {
  #   dir_target_case <label> <mode: heal|full|dirlink>
  local label="${1}" mode="${2}" jail fixture failed="false" reason=""
  jail="$(mktemp -d)"
  fixture="$(mktemp -d)"
  printf '9.9.9' > "${fixture}/VERSION"
  case "${mode}" in
    heal) mkdir "${jail}/last_check" ;;
    full) mkdir "${jail}/last_check"; printf 'keep' > "${jail}/last_check/data" ;;
    dirlink) mkdir "${jail}/decoy-dir"; ln -s "${jail}/decoy-dir" "${jail}/last_check" ;;
  esac
  render_settled '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"},"context_window":{"used_percentage":20}}' \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK=1 \
    URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR="${jail}" \
    URDA_AI_FORGED_STATUS_LINE_VERSION_URL="file://${fixture}/VERSION" \
    URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW=1789430400
  case "${mode}" in
    heal)
      if [[ ! -f "${jail}/last_check" ]]; then
        failed="true"
        reason="empty planted dir was not healed into a state file"
      elif [[ "$(<"${jail}/last_check")" != "1789430400" ]]; then
        failed="true"
        reason="healed last_check holds $(<"${jail}/last_check"), want 1789430400"
      fi
      ;;
    full)
      if [[ ! -f "${jail}/last_check/data" || "$(<"${jail}/last_check/data")" != "keep" ]]; then
        failed="true"
        reason="contents of a non-empty planted dir were disturbed"
      elif [[ "$(ls -A "${jail}/last_check")" != "data" ]]; then
        failed="true"
        reason="extra files landed inside the refused dir: $(ls -A "${jail}/last_check")"
      fi
      ;;
    dirlink)
      if [[ -n "$(ls -A "${jail}/decoy-dir")" ]]; then
        failed="true"
        reason="files landed inside the symlink's target dir"
      elif [[ ! -L "${jail}/last_check" ]]; then
        failed="true"
        reason="directory symlink was removed; the guard should refuse instead"
      fi
      ;;
  esac
  remove_jail "${jail}" "${fixture}"
  cache_report "${label}" "${failed}" "${reason}"
}
dir_target_case "Empty planted dir at last_check self-heals" heal
dir_target_case "Non-empty dir at last_check is refused, contents intact" full
dir_target_case "Directory symlink at last_check is refused, never followed" dirlink
unset PERM_JAIL PERM_FIXTURE

section "Command flags"
# Recognized flags answer and exit; anything else must still render.
version_flag_case
flag_case "flags: --help documents --update" \
  --help '--update' ""
flag_case "flags: -h prints the same usage" \
  -h 'Usage:' ""
flag_case "flags: unknown argument still renders two rows" \
  --banana 'Opus' 2
flag_case "flags: bare -- still renders two rows" \
  -- 'Opus' 2

# --- summary ----------------------------------------------------------------

TOTAL=$(( PASS_COUNT + FAIL_COUNT ))
printf "\n%d passed, %d failed of %d.\n" "${PASS_COUNT}" "${FAIL_COUNT}" "${TOTAL}"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
