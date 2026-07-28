#!/usr/bin/env bash
#
# Install Urda's Forged Status Line.
#
#   curl -fsSL https://raw.githubusercontent.com/urda/forged-statusline/release/install.sh | bash
#   wget -qO-  https://raw.githubusercontent.com/urda/forged-statusline/release/install.sh | bash
#
# Pass `--agy` or `--copilot` through `bash -s --`.
set -euo pipefail

SCRIPT="urda-com-forged-statusline.sh"
SRC="https://raw.githubusercontent.com/urda/forged-statusline/release/${SCRIPT}"

if [[ $# -gt 1 ]]; then
  printf 'error: too many arguments: pass at most one host flag (--agy or --copilot).\n' >&2
  exit 1
fi

case "${1:-}" in
  "")        HOST="claude" ;;
  --agy)     HOST="agy" ;;
  --copilot) HOST="copilot" ;;
  *)         printf 'error: unknown option %s (use --agy for Antigravity CLI or --copilot for GitHub Copilot CLI).\n' "${1}" >&2; exit 1 ;;
esac

if [[ "${HOST}" == "agy" ]]; then
  HOST_NAME="Antigravity CLI"
  DEST_DIR="${HOME}/.gemini/antigravity-cli"
elif [[ "${HOST}" == "copilot" ]]; then
  HOST_NAME="GitHub Copilot CLI"
  DEST_DIR="${HOME}/.copilot"
else
  HOST_NAME="Claude Code"
  DEST_DIR="${HOME}/.claude"
fi
DEST="${DEST_DIR}/${SCRIPT}"

# Do not create a host directory before that host is configured.
if [[ ! -d "${DEST_DIR}" ]]; then
  printf 'error: %s not found. Set up %s first, then re-run.\n' "${DEST_DIR}" "${HOST_NAME}" >&2
  exit 1
fi

# A directory here would swallow the final mv instead of being replaced.
if [[ -d "${DEST}" ]]; then
  printf 'error: %s is a directory; move it aside and re-run.\n' "${DEST}" >&2
  exit 1
fi

# The fallback also supports locally invoked copies of this installer.
if command -v curl >/dev/null 2>&1; then
  DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
  DOWNLOADER="wget"
else
  printf 'error: need curl or wget to download %s.\n' "${SCRIPT}" >&2
  exit 1
fi

# Keep the validated move on one filesystem.
TMP="$(mktemp "${DEST_DIR}/.${SCRIPT}.XXXXXX")"
trap 'rm -f "${TMP}"' EXIT

if [[ "${DOWNLOADER}" == "curl" ]]; then
  curl -fsSL "${SRC}" -o "${TMP}"
else
  # -q silences wget's own diagnostics, so report the failure here.
  wget -qO "${TMP}" "${SRC}" \
    || { printf 'error: failed to download %s\n' "${SRC}" >&2; exit 1; }
fi

bash -n "${TMP}"

# Reject unrelated valid Bash. This checks plausibility, not authenticity.
IDENTITY_ERR="error: downloaded file is not the renderer (identity check failed)"
if [[ "$(head -1 "${TMP}")" != '#!/usr/bin/env bash' ]]; then
  printf '%s\n' "${IDENTITY_ERR}" >&2
  exit 1
fi
if ! grep -q '^URDA_AI_FORGED_STATUS_LINE_VERSION=' "${TMP}"; then
  printf '%s\n' "${IDENTITY_ERR}" >&2
  exit 1
fi
if ! grep -q '^update_check()' "${TMP}"; then
  printf '%s\n' "${IDENTITY_ERR}" >&2
  exit 1
fi

# A prefix of the renderer can still parse, so require the closing line too.
if [[ "$(tail -1 "${TMP}")" != 'exit 0' ]]; then
  printf 'error: downloaded file is incomplete (truncated download).\n' >&2
  exit 1
fi

chmod 755 "${TMP}"
mv -f "${TMP}" "${DEST}"

printf 'Installed %s -> %s\n\n' "${SCRIPT}" "${DEST}"

# Claude's snippet adds periodic refresh and explicit zero padding.
if [[ "${HOST}" == "agy" ]]; then
  printf 'Add this to ~/.gemini/antigravity-cli/settings.json to enable it:\n\n'
  cat <<'JSON'
  "statusLine": {
    "type": "command",
    "command": "~/.gemini/antigravity-cli/urda-com-forged-statusline.sh"
  }
JSON
elif [[ "${HOST}" == "copilot" ]]; then
  printf 'Add this to ~/.copilot/settings.json to enable it:\n\n'
  cat <<'JSON'
  "statusLine": {
    "type": "command",
    "command": "~/.copilot/urda-com-forged-statusline.sh"
  }
JSON
else
  printf 'Add this to ~/.claude/settings.json to enable it:\n\n'
  cat <<'JSON'
  "statusLine": {
    "command": "~/.claude/urda-com-forged-statusline.sh",
    "padding": 0,
    "refreshInterval": 20,
    "type": "command"
  }
JSON
fi
