#!/usr/bin/env bash
#
# -*- bash -*-
# shellcheck shell=bash
#
# Urda's Forged Status Line
#
# - https://urda.com
# - https://anvil.urda.com
#
# Renders two rows:
#   row 1:  🔮 model 🦾 effort 🚫 Thinking: OFF | 💾 directory
#   row 2:  🧠 context % | ⏳ 5h % (time) | 🪔 7d % (time)
#
# No `set -e`: a non-zero exit or empty stdout blanks the status line.
#
# Self-overridable so tests can compare cached and local versions.
URDA_AI_FORGED_STATUS_LINE_VERSION="${URDA_AI_FORGED_STATUS_LINE_VERSION:-1.0.0}"

# --- manual self-update (user-invoked) --------------------------------------
update_self() {
  # The parsed function remains safe after atomically replacing its source file.
  # tmp stays global so the EXIT trap can clean it up.
  local self self_dir url status

  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" \
    || { printf 'update: cannot resolve own location\n' >&2; return 1; }
  self="${self_dir}/$(basename "${BASH_SOURCE[0]}")"

  url="${URDA_AI_FORGED_STATUS_LINE_UPDATE_URL:-https://raw.githubusercontent.com/urda/forged-statusline/release/urda-com-forged-statusline.sh}"

  # Keep the validated move on one filesystem.
  tmp="$(mktemp "${self_dir}/.urda-com-forged-statusline.XXXXXX")" \
    || { printf 'update: cannot create temp file in %s\n' "${self_dir}" >&2; return 1; }
  trap 'rm -f "${tmp}"' EXIT

  # Code downloads follow redirects; version probes do not.
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}" -o "${tmp}"; status=$?
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${tmp}" "${url}"; status=$?
  else
    printf 'update: need curl or wget\n' >&2; return 1
  fi
  (( status == 0 )) || { printf 'update: download failed (status %s)\n' "${status}" >&2; return 1; }

  # Reject error pages and unrelated valid Bash.
  bash -n "${tmp}" 2>/dev/null \
    || { printf 'update: not valid bash; keeping current version\n' >&2; return 1; }
  if [[ "$(head -1 "${tmp}")" != '#!/usr/bin/env bash' ]] \
     || ! grep -q '^URDA_AI_FORGED_STATUS_LINE_VERSION=' "${tmp}" \
     || ! grep -q '^update_check()' "${tmp}"; then
    printf 'update: identity check failed; keeping current version\n' >&2
    return 1
  fi

  # A prefix of the renderer can still parse, so require the closing line too.
  if [[ "$(tail -1 "${tmp}")" != 'exit 0' ]]; then
    printf 'update: incomplete download; keeping current version\n' >&2
    return 1
  fi

  chmod 755 "${tmp}" \
    || { printf 'update: cannot set file mode; keeping current version\n' >&2; return 1; }
  mv -f "${tmp}" "${self}" \
    || { printf 'update: swap failed; keeping current version\n' >&2; return 1; }
  trap - EXIT

  printf 'Updated Forged Status Line (%s); takes effect on next render.\n' "${self}"
  return 0
}

# Handle commands before reading render input. An unrecognized argument falls
# through to a render, because refusing one would blank the status line.
case "${1:-}" in
  --update)
    update_self
    exit $?
    ;;
  --version)
    printf '%s\n' "${URDA_AI_FORGED_STATUS_LINE_VERSION}"
    exit 0
    ;;
  -h|--help)
    printf "Urda's Forged Status Line %s\n" "${URDA_AI_FORGED_STATUS_LINE_VERSION}"
    printf '%s\n' \
      'https://anvil.urda.com/forged-statusline/' \
      '' \
      'Your Claude runs this with session JSON on stdin; it prints two rows.' \
      '' \
      'Usage: urda-com-forged-statusline.sh [--update|--version|--help]' \
      '' \
      '  --update    Replace this file with the latest release.' \
      '  --version   Print the version.' \
      '  -h, --help  Print this message.'
    exit 0
    ;;
esac

# --- configuration ----------------------------------------------------------

# Use selector-free emoji defaults because U+FE0F drifts bar width.
ICON_ALARM="${URDA_AI_FORGED_STATUS_LINE_ICON_ALARM:-🔴}"
ICON_CONTEXT="${URDA_AI_FORGED_STATUS_LINE_ICON_CONTEXT:-🧠}"
ICON_CONTEXT_UNKNOWN="${URDA_AI_FORGED_STATUS_LINE_ICON_CONTEXT_UNKNOWN:-🌀}"
ICON_DIR="${URDA_AI_FORGED_STATUS_LINE_ICON_DIR:-💾}"
ICON_EFFORT="${URDA_AI_FORGED_STATUS_LINE_ICON_EFFORT:-🦾}"
ICON_MODEL="${URDA_AI_FORGED_STATUS_LINE_ICON_MODEL:-🔮}"
ICON_RATE_5H="${URDA_AI_FORGED_STATUS_LINE_ICON_RATE_5H:-⏳}"
ICON_RATE_7D="${URDA_AI_FORGED_STATUS_LINE_ICON_RATE_7D:-🪔}"
ICON_THINKING="${URDA_AI_FORGED_STATUS_LINE_ICON_THINKING:-🚫}"
ICON_WARN="${URDA_AI_FORGED_STATUS_LINE_ICON_WARN:-🟡}"

case "${URDA_AI_FORGED_STATUS_LINE_ICONS:-1}" in
  0) ICONS_ON=0 ;;
  *) ICONS_ON=1 ;;
esac

RESET=$'\033[0m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'
GRAY=$'\033[90m'
GREEN=$'\033[32m'
RED=$'\033[31m'
WHITE=$'\033[37m'
YELLOW=$'\033[33m'

# Light mode retints only colors that wash out on white.
case "${URDA_AI_FORGED_STATUS_LINE_THEME:-dark}" in
  light)
    GRAY=$'\033[38;5;240m'   # bright-black is faint on white; mid-gray reads
    WHITE=$'\033[39m'        # default fg adapts; forced bright-white washes out
    ;;
esac

SEP=" ${GRAY}|${RESET} "

# Indexed by the last cell's fractional eighths.
CHAR_FILLED="█"
CHAR_EMPTY=" "
CHAR_PARTIALS=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
CELL_STEPS=${#CHAR_PARTIALS[@]}   # fill steps per cell, derived from the ramp size

BAR_WIDTH=8

# JSON stores numbers as doubles, which count integers exactly only below
# 2^53. At and past this line, distinct values collapse into each other.
JSON_EXACT_CEILING=9007199254740992

# One ceiling for every number accepted anywhere: Bash arithmetic wraps past
# 18 digits, and the cache reader rejects JSON_EXACT_CEILING (16 digits) and
# up, so 15 digits is the widest run that is always safe in both.
MAX_SAFE_DIGITS=15

CTX_FULL_WINDOW=1000000

UPDATE_CHECK_ON=1
case "${URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK:-1}" in 0) UPDATE_CHECK_ON=0 ;; esac
UPDATE_STATE_DIR="${URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/forged-statusline}"
UPDATE_CHECK_INTERVAL=604800  # 7 days

WRITE_CACHE_ON=0
case "${URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE:-0}" in 1) WRITE_CACHE_ON=1 ;; esac

# --- pure helpers -----------------------------------------------------------
# Helpers avoid subshells through caller-supplied output variables. Their local
# names use __ prefixes because printf -v prefers same-named locals.

is_integer() {
  #   is_integer <value>
  [[ "${1}" =~ ^[0-9]+$ ]]
}

clamp_percent() {
  #   clamp_percent <var>
  # Pin a digit reading to three columns, in place.
  local __v="${1}" __digits
  if [[ "${!__v}" =~ ^0*([0-9]+)$ ]]; then
    __digits="${BASH_REMATCH[1]}"
    if (( ${#__digits} > 3 )); then
      __digits=100
    fi
    printf -v "${__v}" '%s' "${__digits}"
  fi
}

sanitize_cache_pair() {
  #   sanitize_cache_pair <pct_var> <reset_var>
  # Blank a half the cache reader would reject.
  local __p="${1}" __r="${2}" __pv="${!1}" __rv="${!2}"
  local __pct_re="^[0-9]{1,${MAX_SAFE_DIGITS}}(\.[0-9]+)?\$"
  [[ "${__pv}" =~ ${__pct_re} ]] || printf -v "${__p}" '%s' ""
  if ! is_integer "${__rv}" || (( ${#__rv} > MAX_SAFE_DIGITS )); then
    printf -v "${__r}" '%s' ""
  fi
}

normalize_pair() {
  #   normalize_pair <out_warn> <out_alarm> <warn> <alarm>
  # Accept one valid increasing pair of 0-100 integers, leaving both outputs
  # untouched otherwise. Callers pre-seed the outputs, so a rejected pair falls
  # back to what was there.
  local __ow="${1}" __oa="${2}" __w="${3}" __a="${4}"

  [[ "${__w}" =~ ^0*([0-9]{1,3})$ ]] || return 1
  __w="${BASH_REMATCH[1]}"
  [[ "${__a}" =~ ^0*([0-9]{1,3})$ ]] || return 1
  __a="${BASH_REMATCH[1]}"
  (( __w <= 100 && __a <= 100 && __w < __a )) || return 1

  printf -v "${__ow}" '%s' "${__w}"
  printf -v "${__oa}" '%s' "${__a}"
}

threshold_pair() {
  #   threshold_pair <gauge>
  # Resolve THRESHOLD_<gauge>_WARN and _ALARM from that gauge's own overrides,
  # falling back to the shared pair. Bash 3.2 has no associative arrays, so both
  # names are built and read by indirection.
  local gauge="${1}"
  local warn_env="URDA_AI_FORGED_STATUS_LINE_THRESHOLD_${gauge}_WARN"
  local alarm_env="URDA_AI_FORGED_STATUS_LINE_THRESHOLD_${gauge}_ALARM"

  printf -v "THRESHOLD_${gauge}_WARN" '%s' "${THRESHOLD_WARN}"
  printf -v "THRESHOLD_${gauge}_ALARM" '%s' "${THRESHOLD_ALARM}"

  # An unset half inherits the shared value, so a lone override still pairs up.
  normalize_pair "THRESHOLD_${gauge}_WARN" "THRESHOLD_${gauge}_ALARM" \
    "${!warn_env:-${THRESHOLD_WARN}}" "${!alarm_env:-${THRESHOLD_ALARM}}"
  return 0
}

render_bar() {
  #   render_bar <out> <percent> <gauge>
  # Fixed-width colored bar with eighth-cell fill, banded by that gauge's
  # thresholds.
  local __out="${1}" PCT="${2}" __gauge="${3}"
  local color fill empty bar i eighths full rem used partial
  local __wv="THRESHOLD_${__gauge}_WARN" __av="THRESHOLD_${__gauge}_ALARM"
  local __warn="${!__wv:-${THRESHOLD_WARN}}" __alarm="${!__av:-${THRESHOLD_ALARM}}"

  if ! is_integer "${PCT}"; then
    empty=""
    for (( i = 0; i < BAR_WIDTH; i++ )); do empty+="${CHAR_EMPTY}"; done
    printf -v "${__out}" '%s[%s]%s???%%%s' "${GRAY}" "${empty}" "${GRAY}" "${RESET}"
    return
  fi

  if (( PCT > 100 )); then
    PCT=100
  fi

  if (( PCT < __warn )); then
    color="${GREEN}"
  elif (( PCT < __alarm )); then
    color="${YELLOW}"
  else
    color="${RED}"
  fi

  # Preserve a sliver for any nonzero reading.
  eighths=$(( PCT * BAR_WIDTH * CELL_STEPS / 100 ))
  if (( PCT > 0 && eighths == 0 )); then
    eighths=1
  fi

  full=$(( eighths / CELL_STEPS ))
  rem=$(( eighths % CELL_STEPS ))

  fill=""
  for (( i = 0; i < full; i++ )); do fill+="${CHAR_FILLED}"; done

  partial=0
  if (( rem > 0 && full < BAR_WIDTH )); then
    fill+="${CHAR_PARTIALS[rem]}"
    partial=1
  fi
  used=$(( full + partial ))

  empty=""
  for (( i = used; i < BAR_WIDTH; i++ )); do empty+="${CHAR_EMPTY}"; done

  bar="${color}${fill}${GRAY}${empty}"
  printf -v "${__out}" '%s[%s]%s%3d%%%s' "${GRAY}" "${bar}" "${color}" "${PCT}" "${RESET}"
}

status_icon() {
  #   status_icon <out> <percent> <gauge> <calm> [<unknown>]
  local __out="${1}" PCT="${2}" __gauge="${3}" CALM="${4}" UNKNOWN="${5:-${4}}"
  local __wv="THRESHOLD_${__gauge}_WARN" __av="THRESHOLD_${__gauge}_ALARM"
  local __warn="${!__wv:-${THRESHOLD_WARN}}" __alarm="${!__av:-${THRESHOLD_ALARM}}"

  if ! is_integer "${PCT}"; then
    printf -v "${__out}" '%s' "${UNKNOWN}"
    return
  fi

  if (( PCT >= __alarm )); then
    printf -v "${__out}" '%s' "${ICON_ALARM}"
  elif (( PCT >= __warn )); then
    printf -v "${__out}" '%s' "${ICON_WARN}"
  else
    printf -v "${__out}" '%s' "${CALM}"
  fi
}

seg() {
  #   seg <out> <icon> <body>
  # Omit the icon and its gap when icons are disabled.
  local __out="${1}" icon="${2}" body="${3}"
  if (( ICONS_ON )) && [[ -n "${icon}" ]]; then
    printf -v "${__out}" '%s %s' "${icon}" "${body}"
  else
    printf -v "${__out}" '%s' "${body}"
  fi
}

format_countdown() {
  #   format_countdown <out> <reset> <now>
  # Days/hours above 24h, otherwise hours/minutes. Past resets clamp to 0h00m.
  local __out="${1}" epoch="${2}" now="${3}"
  local remaining days hours mins token

  remaining=$(( epoch - now ))
  if (( remaining < 0 )); then
    remaining=0
  fi

  if (( remaining >= 86400 )); then
    days=$(( remaining / 86400 ))
    hours=$(( (remaining % 86400) / 3600 ))
    printf -v token '%dd%02dh' "${days}" "${hours}"
  else
    hours=$(( remaining / 3600 ))
    mins=$(( (remaining % 3600) / 60 ))
    printf -v token '%dh%02dm' "${hours}" "${mins}"
  fi

  printf -v "${__out}" '(%s)' "${token}"
}

humanize_window() {
  #   humanize_window <out> <size>
  # Round with a decimal divisor to a whole K. Callers only pass sizes under the
  # 1M full window, so no M branch exists.
  local __out="${1}" __size="${2}" __val
  __val=$(( (__size + 500) / 1000 ))
  printf -v "${__out}" '%dK' "${__val}"
}

rate_gauge() {
  #   rate_gauge <out> <rate> <reset> <icon> <label> <now> <gauge>
  local __out="${1}" rate="${2}" reset="${3}" icon="${4}" label="${5}" now="${6}" gauge="${7}"
  local __ico __bar __seg __cd __frag=""
  if [[ -n "${rate}" ]]; then
    status_icon __ico "${rate}" "${gauge}" "${icon}"
    render_bar __bar "${rate}" "${gauge}"
    seg __seg "${__ico}" "${GRAY}${label}${RESET} ${__bar}"
    __frag="${SEP}${__seg}"
    # A reset Bash arithmetic cannot hold is treated as absent, not fatal.
    if is_integer "${reset}" && (( ${#reset} <= MAX_SAFE_DIGITS )); then
      format_countdown __cd "${reset}" "${now}"
      __frag+=" ${GRAY}${__cd}${RESET}"
    fi
  fi
  printf -v "${__out}" '%s' "${__frag}"
}

# --- optional rate-limit cache (opt-in, fire-and-forget) --------------------
write_cache() {
  # ${VAR:-} protects the detached child's set -u after a jq failure.
  local dir file cached
  local new_5h_pct new_5h_reset new_7d_pct new_7d_reset
  local cur_5h_pct cur_5h_reset cur_7d_pct cur_7d_reset
  local eff_5h_pct eff_5h_reset eff_7d_pct eff_7d_reset

  # Global for the child EXIT trap.
  TMP=""
  trap 'rm -f "${TMP}"' EXIT

  dir="${URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/forged-statusline}"

  new_5h_pct="${CACHE_5H_PCT:-}"
  new_5h_reset="${RESET_5H:-}"
  new_7d_pct="${CACHE_7D_PCT:-}"
  new_7d_reset="${RESET_7D:-}"

  sanitize_cache_pair new_5h_pct new_5h_reset
  sanitize_cache_pair new_7d_pct new_7d_reset

  # Agy caches per quota pool: one shared slot would flip meaning with the
  # active model family.
  case "${HOST:-claude}" in
    claude) file="${dir}/cache-claude.json" ;;
    agy)
      case "${POOL}" in
        gemini|3p) file="${dir}/cache-agy-${POOL}.json" ;;
        *)         return ;;
      esac
      ;;
    *) return ;;
  esac

  cur_5h_pct=""; cur_5h_reset=""; cur_7d_pct=""; cur_7d_reset=""
  # Read the cache as one object rather than four independent fields: slurping
  # drops any trailing documents, a window counts only as a complete pair of
  # sane numbers, and flooring the reset keeps the comparisons below inside
  # Bash arithmetic. Anything else reads as absent and gets overwritten.
  if [[ -f "${file}" ]]; then
    cached="$(jq -rs --argjson ceiling "${JSON_EXACT_CEILING}" '
      def sane: (type == "number") and (. >= 0) and (. < $ceiling);
      def window($p; $r):
        if ($p | sane) and ($r | sane)
        then [($p | tostring), ($r | floor | tostring)]
        else ["", ""] end;
      ((.[0] // {}) | if type == "object" then . else {} end) as $c
      | window($c.rate_5h_pct; $c.rate_5h_reset) + window($c.rate_7d_pct; $c.rate_7d_reset)
      | join("\u001f")
    ' "${file}" 2>/dev/null)" || cached=""
    IFS=$'\037' read -r cur_5h_pct cur_5h_reset cur_7d_pct cur_7d_reset <<< "${cached}"
  fi

  # No incoming data: write nothing, but still drop a file that reads as
  # nothing, so a corrupt cache cannot outlive rate-free renders.
  if [[ -z "${new_5h_pct}${new_5h_reset}${new_7d_pct}${new_7d_reset}" ]]; then
    if [[ -f "${file}" && -z "${cur_5h_reset}${cur_7d_reset}" ]]; then
      rm -f "${file}"
    fi
    return
  fi

  # Only complete pairs with non-regressing resets replace cached windows.
  # The unlocked race self-corrects on the next render.
  if [[ -n "${new_5h_pct}" && -n "${new_5h_reset}" && ( -z "${cur_5h_reset}" || "${new_5h_reset}" -ge "${cur_5h_reset}" ) ]]; then
    eff_5h_pct="${new_5h_pct}"; eff_5h_reset="${new_5h_reset}"
  else
    eff_5h_pct="${cur_5h_pct}"; eff_5h_reset="${cur_5h_reset}"
  fi
  if [[ -n "${new_7d_pct}" && -n "${new_7d_reset}" && ( -z "${cur_7d_reset}" || "${new_7d_reset}" -ge "${cur_7d_reset}" ) ]]; then
    eff_7d_pct="${new_7d_pct}"; eff_7d_reset="${new_7d_reset}"
  else
    eff_7d_pct="${cur_7d_pct}"; eff_7d_reset="${cur_7d_reset}"
  fi

  if [[ -z "${eff_5h_reset}" && -z "${eff_7d_reset}" ]]; then
    # Nothing to write, so drop a file that no longer reads back at all.
    if [[ -f "${file}" && -z "${cur_5h_reset}${cur_7d_reset}" ]]; then
      rm -f "${file}"
    fi
    return
  fi

  # Write atomically and omit absent windows.
  mkdir -p "${dir}"
  TMP="${file}.$$.tmp"
  jq -n \
    --argjson now "${NOW:-0}" \
    --arg p5 "${eff_5h_pct}" --arg r5 "${eff_5h_reset}" \
    --arg p7 "${eff_7d_pct}" --arg r7 "${eff_7d_reset}" \
    '{schema: 1, written_at: $now}
     + (if $p5 != "" then {rate_5h_pct: ($p5 | tonumber)} else {} end)
     + (if $r5 != "" then {rate_5h_reset: ($r5 | tonumber)} else {} end)
     + (if $p7 != "" then {rate_7d_pct: ($p7 | tonumber)} else {} end)
     + (if $r7 != "" then {rate_7d_reset: ($r7 | tonumber)} else {} end)' \
    > "${TMP}"
  mv -f "${TMP}" "${file}"

  # Bash 3.2 may skip EXIT traps when a background function falls through.
  exit 0
}

# --- optional update check (opt-out, on by default) -------------------------
update_check() {
  # Fetch VERSION independently of cache writes.
  # lockdir is global for the EXIT trap; fetched guards the set -u child.
  local stale_after fetched="" status held_at tmp url

  lockdir="${UPDATE_STATE_DIR}/update-check.lock"
  stale_after=60  # cushion curl's total and wget's per-operation timeout

  mkdir -p "${UPDATE_STATE_DIR}" || return

  # A stale-lock race can only duplicate a fetch.
  if ! mkdir "${lockdir}" 2>/dev/null; then
    # GNU and BSD stat use different formatting flags.
    held_at="$(stat -c %Y "${lockdir}" 2>/dev/null || stat -f %m "${lockdir}" 2>/dev/null || echo "${NOW:-0}")"
    if (( ${NOW:-0} - held_at < stale_after )); then
      return
    fi
    rmdir "${lockdir}" 2>/dev/null
    mkdir "${lockdir}" 2>/dev/null || return
  fi
  trap 'rmdir "${lockdir}" 2>/dev/null' EXIT

  # Do not follow redirects; status=127 throttles a missing downloader.
  url="${URDA_AI_FORGED_STATUS_LINE_VERSION_URL:-https://raw.githubusercontent.com/urda/forged-statusline/release/VERSION}"
  if command -v curl >/dev/null 2>&1; then
    fetched="$(curl -fs -m 5 "${url}" 2>/dev/null)" \
      && status=0 || status=$?
  elif command -v wget >/dev/null 2>&1; then
    fetched="$(wget --max-redirect=0 --timeout=5 --tries=1 -qO- "${url}" 2>/dev/null)" \
      && status=0 || status=$?
  else
    status=127
  fi

  # A killed downloader retries because it never records completion.
  printf '%s' "${NOW:-0}" > "${UPDATE_STATE_DIR}/last_check"

  # Accept only strict X.Y.Z responses.
  fetched="${fetched//[[:space:]]/}"
  if (( status == 0 )) && [[ "${fetched}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    tmp="${UPDATE_STATE_DIR}/remote_version.$$.tmp"
    printf '%s' "${fetched}" > "${tmp}"
    mv -f "${tmp}" "${UPDATE_STATE_DIR}/remote_version"
  fi

  # Bash 3.2 needs an explicit exit to release the lock.
  exit 0
}

# --- session parse ----------------------------------------------------------

# Missing dependencies must not blank the status line.
if ! command -v jq >/dev/null 2>&1; then
  _icon=""
  if (( ICONS_ON )); then
    _icon="${ICON_ALARM} "
  fi
  printf '%s%sjq not found on PATH: install jq%s\n' "${_icon}" "${RED}" "${RESET}"
  exit 0
fi

# Seed every destination first: a total jq failure must land on these safe
# defaults, never on values inherited from the caller's environment.
HOST="claude"
MODEL="(Missing Model)"
CURRENT_DIR="(Missing Directory)"
EFFORT="" THINKING="" PERCENT="" RATE_5H="" RATE_7D="" POOL=""
RESET_5H="" RESET_7D="" CTX_SIZE="" CACHE_5H_PCT="" CACHE_7D_PCT=""

# Parse allowlisted NAME<US>value records once. Fields degrade independently;
# display percentages are denoised and floored while cache values remain raw.
while IFS=$'\037' read -r _field _value; do
  # Keep this assignment allowlist synchronized with the jq records.
  case "${_field}" in
    HOST|MODEL|CURRENT_DIR|EFFORT|THINKING|PERCENT|RATE_5H|RATE_7D|RESET_5H|RESET_7D|CTX_SIZE|CACHE_5H_PCT|CACHE_7D_PCT|POOL) ;;
    *) continue ;;
  esac
  printf -v "${_field}" '%s' "${_value}"
done < <(
  # jq 1.6 shifts fromdateiso8601 by an hour when the local zone is on DST.
  TZ=UTC jq -r '
    def show: (. * 10000000000 | round) / 10000000000 | floor;
    def clean: gsub("[[:cntrl:]]"; "");   # strip control chars from raw display text (injection guard)
    (if ((.product | strings) // "") | ascii_downcase | contains("antigravity") then "agy"
     elif (.ai_used | type) == "object" then "copilot"
     else "claude" end) as $host |
    (if ((((.model.display_name)? | strings) // ((.model.id)? | strings) // "") | ascii_downcase | contains("gemini")) then "gemini" else "3p" end) as $pool |
    "HOST\u001f"        + $host,
    "POOL\u001f"        + $pool,
    "MODEL\u001f"       + ((((.model.display_name)? | strings) // "(Missing Model)") | clean),
    "CURRENT_DIR\u001f" + ((((.workspace.current_dir)? | strings) // "(Missing Directory)") | clean),
    "EFFORT\u001f"      + ((((.effort.level)? | strings) // "") | clean),
    "THINKING\u001f"    + (if ((.thinking.enabled)? | type) == "boolean" then (.thinking.enabled | tostring) else "" end),
    "PERCENT\u001f"     + (if ((.context_window.used_percentage)? | type) == "number" then (.context_window.used_percentage | show | tostring)
                          elif $host == "copilot" and ((.context_window.current_context_used_percentage)? | type) == "number"
                            then (.context_window.current_context_used_percentage | show | tostring)
                          else "" end),
    "RATE_5H\u001f"     + (if ((.rate_limits.five_hour.used_percentage)? | type) == "number"
                            then (.rate_limits.five_hour.used_percentage | show | tostring)
                          elif $host == "agy" and ((.quota[$pool + "-5h"].remaining_fraction)? | type) == "number"
                            then ((1 - .quota[$pool + "-5h"].remaining_fraction) * 100 | show | tostring)
                          else "" end),
    "RATE_7D\u001f"     + (if ((.rate_limits.seven_day.used_percentage)? | type) == "number"
                            then (.rate_limits.seven_day.used_percentage | show | tostring)
                          elif $host == "agy" and ((.quota[$pool + "-weekly"].remaining_fraction)? | type) == "number"
                            then ((1 - .quota[$pool + "-weekly"].remaining_fraction) * 100 | show | tostring)
                          else "" end),
    "RESET_5H\u001f"    + (if ((.rate_limits.five_hour.resets_at)? | type) == "number"
                            then (.rate_limits.five_hour.resets_at | floor | tostring)
                          elif $host == "agy" and ((.quota[$pool + "-5h"].reset_time)? | type) == "string"
                            then (try (.quota[$pool + "-5h"].reset_time | fromdateiso8601 | tostring) catch "")
                          else "" end),
    "RESET_7D\u001f"    + (if ((.rate_limits.seven_day.resets_at)? | type) == "number"
                            then (.rate_limits.seven_day.resets_at | floor | tostring)
                          elif $host == "agy" and ((.quota[$pool + "-weekly"].reset_time)? | type) == "string"
                            then (try (.quota[$pool + "-weekly"].reset_time | fromdateiso8601 | tostring) catch "")
                          else "" end),
    "CTX_SIZE\u001f"    + (if (.context_window.context_window_size? | type) == "number"
                            then (.context_window.context_window_size | floor | tostring)
                          elif $host == "copilot" and (.context_window.displayed_context_limit? | type) == "number"
                            then (.context_window.displayed_context_limit | floor | tostring)
                          else "" end),
    "CACHE_5H_PCT\u001f" + (if ((.rate_limits.five_hour.used_percentage)? | type) == "number"
                            then (.rate_limits.five_hour.used_percentage | tostring)
                          elif $host == "agy" and ((.quota[$pool + "-5h"].remaining_fraction)? | type) == "number"
                            then ((1 - .quota[$pool + "-5h"].remaining_fraction) * 100 | tostring)
                          else "" end),
    "CACHE_7D_PCT\u001f" + (if ((.rate_limits.seven_day.used_percentage)? | type) == "number"
                            then (.rate_limits.seven_day.used_percentage | tostring)
                          elif $host == "agy" and ((.quota[$pool + "-weekly"].remaining_fraction)? | type) == "number"
                            then ((1 - .quota[$pool + "-weekly"].remaining_fraction) * 100 | tostring)
                          else "" end)
  ' 2>/dev/null
)
unset _field _value

# --- derived state ----------------------------------------------------------

clamp_percent PERCENT
clamp_percent RATE_5H
clamp_percent RATE_7D

THRESHOLD_WARN=50
THRESHOLD_ALARM=80
normalize_pair THRESHOLD_WARN THRESHOLD_ALARM \
  "${URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN:-${THRESHOLD_WARN}}" \
  "${URDA_AI_FORGED_STATUS_LINE_THRESHOLD_ALARM:-${THRESHOLD_ALARM}}"

threshold_pair CONTEXT
threshold_pair 5H
threshold_pair 7D

# Collapse only exact HOME paths, not sibling prefixes.
if [[ "${CURRENT_DIR}" == "${HOME}" ]]; then
  DIR_NAME="~"
elif [[ "${CURRENT_DIR}" == "${HOME}/"* ]]; then
  DIR_NAME="~${CURRENT_DIR#"${HOME}"}"
else
  DIR_NAME="${CURRENT_DIR}"
fi

BADGE_1M_SUFFIX=" (1M context)"
if [[ "${MODEL}" == *"${BADGE_1M_SUFFIX}" ]]; then
  MODEL="${MODEL%"${BADGE_1M_SUFFIX}"}"
fi

# Agy embeds effort in model names; thinking-on remains the silent default.
# Bash 3.2 requires the =~ pattern in an unquoted variable.
if [[ "${HOST}" == "agy" ]]; then
  AGY_TAG_RE='\(([Ll]ow|[Mm]edium|[Hh]igh|[Tt]hinking)\)$'
  if [[ "${MODEL}" =~ ${AGY_TAG_RE} ]]; then
    _tag="${BASH_REMATCH[1]}"
    MODEL="${MODEL% ("${_tag}")}"
    if [[ -z "${EFFORT}" ]]; then
      case "${_tag}" in
        [Ll]ow)    EFFORT="low" ;;
        [Mm]edium) EFFORT="medium" ;;
        [Hh]igh)   EFFORT="high" ;;
      esac
    fi
    unset _tag
  fi
fi

CTX_BADGE=""
if is_integer "${CTX_SIZE}" && (( CTX_SIZE > 0 && CTX_SIZE < CTX_FULL_WINDOW )); then
  humanize_window CTX_BADGE "${CTX_SIZE}"
fi

# Bash 3.2 needs date; DEBUG_NOW keeps tests deterministic.
NOW="${URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW:-}"
if [[ -z "${NOW}" ]]; then
  if (( BASH_VERSINFO[0] >= 5 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2) )); then
    printf -v NOW '%(%s)T' -1
  else
    NOW="$(date +%s)"
  fi
fi

# Compare every render so an installed update clears the badge immediately.
UPDATE_BADGE=""
if (( UPDATE_CHECK_ON )); then
  _remote_version=""
  if [[ -f "${UPDATE_STATE_DIR}/remote_version" ]]; then
    _remote_version="$(<"${UPDATE_STATE_DIR}/remote_version")"
  fi
  if [[ -n "${_remote_version}" && "${_remote_version}" != "${URDA_AI_FORGED_STATUS_LINE_VERSION}" ]]; then
    _update_newest="$(printf '%s\n%s' "${_remote_version}" "${URDA_AI_FORGED_STATUS_LINE_VERSION}" | sort -V 2>/dev/null | tail -1)"
    if [[ "${_update_newest}" == "${_remote_version}" ]]; then
      UPDATE_BADGE="[FSL Update Available]"
    fi
  fi
  unset _remote_version _update_newest
fi

# --- row 1: model, modes, directory, update badge ---------------------------
# Seeds for ShellCheck only: printf -v assignment is invisible to it (SC2154).
_seg="" _ctx_icon="" _ctx_bar="" _g5h="" _g7d=""
MODEL_BODY="${WHITE}${MODEL}${RESET}"
if [[ -n "${CTX_BADGE}" ]]; then
  MODEL_BODY+=" ${CYAN}[${CTX_BADGE}]${RESET}"
fi
seg ROW1 "${ICON_MODEL}" "${MODEL_BODY}"
if [[ -n "${EFFORT}" ]]; then
  seg _seg "${ICON_EFFORT}" "${CYAN}${EFFORT}${RESET}"; ROW1+=" ${_seg}"
fi
if [[ "${THINKING}" == "false" ]]; then
  seg _seg "${ICON_THINKING}" "${RED}Thinking: OFF${RESET}"; ROW1+=" ${_seg}"
fi
seg _seg "${ICON_DIR}" "${BLUE}${DIR_NAME}${RESET}"; ROW1+="${SEP}${_seg}"
if [[ -n "${UPDATE_BADGE}" ]]; then
  ROW1+=" ${CYAN}${UPDATE_BADGE}${RESET}"
fi

# --- row 2: fill gauges -----------------------------------------------------
status_icon _ctx_icon "${PERCENT}" CONTEXT "${ICON_CONTEXT}" "${ICON_CONTEXT_UNKNOWN}"
render_bar _ctx_bar "${PERCENT}" CONTEXT
seg ROW2 "${_ctx_icon}" "${_ctx_bar}"
rate_gauge _g5h "${RATE_5H}" "${RESET_5H}" "${ICON_RATE_5H}" "5h" "${NOW}" 5H; ROW2+="${_g5h}"
rate_gauge _g7d "${RATE_7D}" "${RESET_7D}" "${ICON_RATE_7D}" "7d" "${NOW}" 7D; ROW2+="${_g7d}"

printf '%s\n%s\n' "${ROW1}" "${ROW2}"

# --- detached side effects, only after the render is printed ----------------

UPDATE_CHECK_DUE=0
if (( UPDATE_CHECK_ON )); then
  _last_check=0
  if [[ -f "${UPDATE_STATE_DIR}/last_check" ]]; then
    _last_check="$(<"${UPDATE_STATE_DIR}/last_check")"
  fi
  is_integer "${_last_check}" || _last_check=0
  if (( NOW - _last_check >= UPDATE_CHECK_INTERVAL )); then
    UPDATE_CHECK_DUE=1
  fi
  unset _last_check
fi

# Detach every fd from the renderer capture pipe.
if (( WRITE_CACHE_ON )); then
  { set -euo pipefail; trap '' HUP; write_cache; } >/dev/null 2>&1 </dev/null &
fi
if (( UPDATE_CHECK_ON && UPDATE_CHECK_DUE )); then
  { set -euo pipefail; trap '' HUP; update_check; } >/dev/null 2>&1 </dev/null &
fi

# End of Line
exit 0
