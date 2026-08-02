# Urda's Forged Status Line

<p align="center">
  <a href="https://anvil.urda.com/forged-statusline/"><img src="https://anvil.urda.com/forged-statusline/res/img/icon.png" alt="Urda Anvil AI Logo" width="200"></a>
</p>

[![Claude Code - Native](https://img.shields.io/badge/Claude_Code-Native-D97757?style=plastic&logo=claudecode&logoColor=D97757&logoSize=auto)](#install)
[![Antigravity CLI - Supported](https://img.shields.io/badge/Antigravity_CLI-Supported-a56cc1?style=plastic&logo=googlegemini&logoColor=a56cc1&logoSize=auto)](#other-hosts)
[![Copilot CLI - Supported](https://img.shields.io/badge/Copilot_CLI-Supported-000000?style=plastic&logo=githubcopilot&logoColor=000000&logoSize=auto)](#other-hosts)
[![CI/CD](https://github.com/urda/forged-statusline/actions/workflows/cicd.yaml/badge.svg)](https://github.com/urda/forged-statusline/actions/workflows/cicd.yaml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**A two-row status line for Claude Code: model and modes above, live context and
rate-limit gauges below.**

See the demo and gallery at
[anvil.urda.com/forged-statusline](https://anvil.urda.com/forged-statusline/).

```text
🔮 Opus 4.8 🦾 max | 💾 ~/dev/urda/forged-statusline
🧠 [██▏     ] 28% | ⏳ 5h [███▌    ] 44% (3h42m) | 🪔 7d [█       ] 14% (5d08h)
```

With icons disabled:

```text
Opus 4.8 max | ~/dev/urda/forged-statusline
[██▏     ] 28% | 5h [███▌    ] 44% (3h42m) | 7d [█       ] 14% (5d08h)
```

## Features

- Model, effort, thinking-disabled state, and abbreviated working directory.
- Context, 5-hour, and 7-day gauges when supplied by the host.
- Fixed-width 8-cell bars with eighth-cell fill and per-gauge warn/alarm
  thresholds.
- A `???%` startup state and `(Missing ...)` fallbacks instead of false data or
  a blank status line.
- A context-size badge, like `[200K]`, whenever the window is under 1M.
- Dark and light terminal themes, a master icon switch, and per-icon overrides.
- Best-effort Antigravity CLI (`agy`) and GitHub Copilot CLI support.
- Optional per-host rate-limit caches and a weekly release update check.

## Requirements

| Dependency | Minimum | Purpose              |
| ---------- | ------- | -------------------- |
| `bash`     | 3.2     | Renderer             |
| `jq`       | 1.6     | Session JSON parsing |

`make`, `shellcheck`, `perl`, and `curl` are development dependencies: the
test suites measure bar cells with `perl` and fetch `file://` fixtures with
`curl`. CI runs both suites on
Ubuntu with Bash 5 and on macOS with its system Bash 3.2, then repeats them
against the minimum `jq` above. Both minimums are asserted, not assumed.

## Install

Install into `~/.claude/`:

```bash
curl -fsSL https://raw.githubusercontent.com/urda/forged-statusline/release/install.sh | bash
```

Or use `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/urda/forged-statusline/release/install.sh | bash
```

Add the status line to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "command": "~/.claude/urda-com-forged-statusline.sh",
    "padding": 0,
    "refreshInterval": 20,
    "type": "command"
  }
}
```

Claude Code loads it on the next status refresh. The installer validates the
download as Bash, checks renderer identity markers, and requires a complete file
before atomically replacing an existing copy. This is a plausibility check over
HTTPS, not code signing.

### Other hosts

Claude Code is the first-class target. Pass one host flag through
`bash -s --` for a best-effort installation elsewhere:

| Host               | Flag        | Destination                  | Settings file                             |
| ------------------ | ----------- | ---------------------------- | ----------------------------------------- |
| Antigravity CLI    | `--agy`     | `~/.gemini/antigravity-cli/` | `~/.gemini/antigravity-cli/settings.json` |
| GitHub Copilot CLI | `--copilot` | `~/.copilot/`                | `~/.copilot/settings.json`                |

```bash
curl -fsSL https://raw.githubusercontent.com/urda/forged-statusline/release/install.sh | bash -s -- --agy
curl -fsSL https://raw.githubusercontent.com/urda/forged-statusline/release/install.sh | bash -s -- --copilot
```

Both hosts use a two-key settings block:

```json
"statusLine": {
  "type": "command",
  "command": "~/.gemini/antigravity-cli/urda-com-forged-statusline.sh"
}
```

Use `~/.copilot/urda-com-forged-statusline.sh` for Copilot.

Agy maps its Gemini or third-party `quota` pool to the 5h/7d gauges when
Claude-style rate limits are absent. It moves a trailing Low, Medium, or High
model tag into the effort segment and drops the constant Thinking tag.

Copilot supplies context usage through
`context_window.current_context_used_percentage` and its window badge through
`context_window.displayed_context_limit`. It supplies no rate data, so 5h/7d
gauges and cache writes are absent. Before the first model call, null data
renders `(Missing Model)` and `???%`.

## Updating

A `[FSL Update Available]` badge appears on row 1 when a newer release is
available. Update the installed copy you invoke:

```bash
~/.claude/urda-com-forged-statusline.sh --update
```

Use the equivalent agy or Copilot path for those hosts. The command downloads,
validates, and atomically replaces the renderer. The badge clears on the next
render.

`--version` prints the installed version, and `--help` or `-h` summarizes both.
Any other argument is ignored in favor of a normal render, so a host cannot
blank the status line by passing one.

## Uninstalling

By default FSL is one file plus one state directory. To remove it completely:

```bash
rm ~/.claude/urda-com-forged-statusline.sh          # the renderer
rm -r ~/.local/state/forged-statusline              # update stamps and caches
```

Use the equivalent agy or Copilot path for those hosts, and honor
`$XDG_STATE_HOME` if you have it set. Then delete the `statusLine` block from
the host settings file the install instructions had you edit. To roll back
instead of removing, reinstall or restore any copy of the renderer you kept;
nothing else needs to change.

## Configuration

Set configuration in the `env` block of `~/.claude/settings.json`:

```json
{
  "env": {
    "URDA_AI_FORGED_STATUS_LINE_ICON_MODEL": "🤖",
    "URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN": "40",
    "URDA_AI_FORGED_STATUS_LINE_THRESHOLD_ALARM": "70",
    "URDA_AI_FORGED_STATUS_LINE_THRESHOLD_7D_ALARM": "90"
  }
}
```

### Display

| Variable                           | Default | Effect                                                     |
| ---------------------------------- | ------- | ---------------------------------------------------------- |
| `URDA_AI_FORGED_STATUS_LINE_ICONS` | `1`     | `0` hides every icon; other values keep icons on           |
| `URDA_AI_FORGED_STATUS_LINE_THEME` | `dark`  | `light` retints gray and model text; other values use dark |

Icons remain swap-only: use the master switch to hide them without leaving
spacing gaps.

### Thresholds

A gauge turns yellow at its warn threshold and red at its alarm threshold. Each
gauge can carry its own pair, and the shared pair covers whatever a gauge does
not set.

| Variable                                             | Default  | Gauge         |
| ---------------------------------------------------- | -------- | ------------- |
| `URDA_AI_FORGED_STATUS_LINE_THRESHOLD_WARN`          | `50`     | Every gauge   |
| `URDA_AI_FORGED_STATUS_LINE_THRESHOLD_ALARM`         | `80`     | Every gauge   |
| `URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_WARN`  | *shared* | Context       |
| `URDA_AI_FORGED_STATUS_LINE_THRESHOLD_CONTEXT_ALARM` | *shared* | Context       |
| `URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN`       | *shared* | 5-hour rate   |
| `URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_ALARM`      | *shared* | 5-hour rate   |
| `URDA_AI_FORGED_STATUS_LINE_THRESHOLD_7D_WARN`       | *shared* | 7-day rate    |
| `URDA_AI_FORGED_STATUS_LINE_THRESHOLD_7D_ALARM`      | *shared* | 7-day rate    |

Every gauge resolves its pair in the same order: its own two variables, then
the shared pair, then the built-in 50 and 80. A pair applies only when both
values are integers from 0 through 100 and warn is below alarm. Anything else
falls back to the next level rather than turning the bands off, so a typo
costs you an override instead of the gauge.

Setting one half of a pair inherits the other half from the fallback. With the
defaults in place, `URDA_AI_FORGED_STATUS_LINE_THRESHOLD_5H_WARN=60` gives the
5-hour gauge 60 and 80 while the other gauges stay at 50 and 80.

### Icons

| Variable                                          | Default | Segment                 |
| ------------------------------------------------- | ------- | ----------------------- |
| `URDA_AI_FORGED_STATUS_LINE_ICON_ALARM`           | 🔴      | Gauge at or above alarm |
| `URDA_AI_FORGED_STATUS_LINE_ICON_CONTEXT`         | 🧠      | Calm context            |
| `URDA_AI_FORGED_STATUS_LINE_ICON_CONTEXT_UNKNOWN` | 🌀      | Unknown context         |
| `URDA_AI_FORGED_STATUS_LINE_ICON_DIR`             | 💾      | Working directory       |
| `URDA_AI_FORGED_STATUS_LINE_ICON_EFFORT`          | 🦾      | Effort                  |
| `URDA_AI_FORGED_STATUS_LINE_ICON_MODEL`           | 🔮      | Model                   |
| `URDA_AI_FORGED_STATUS_LINE_ICON_RATE_5H`         | ⏳      | Calm 5-hour rate        |
| `URDA_AI_FORGED_STATUS_LINE_ICON_RATE_7D`         | 🪔      | Calm 7-day rate         |
| `URDA_AI_FORGED_STATUS_LINE_ICON_THINKING`        | 🚫      | `Thinking: OFF`         |
| `URDA_AI_FORGED_STATUS_LINE_ICON_WARN`            | 🟡      | Gauge at or above warn  |

Pick a replacement that is a single code point, defaults to emoji
presentation, and renders two columns wide, like every default above.
Anything else, including a hidden `U+FE0F` variation selector, changes the
glyph's width and misaligns the bars.

### Rate-limit cache

Cache writing is off by default and detached from rendering.

| Variable                                     | Default             | Effect             |
| -------------------------------------------- | ------------------- | ------------------ |
| `URDA_AI_FORGED_STATUS_LINE_WRITE_CACHE`     | `0`                 | `1` enables writes |

The cache directory is
`${XDG_STATE_HOME:-$HOME/.local/state}/forged-statusline/`. Claude writes
`cache-claude.json`; agy writes one file per quota pool, `cache-agy-gemini.json`
or `cache-agy-3p.json`, for whichever pool the active model draws from;
Copilot writes nothing. Each render updates only the selected pool's cache
file, so a model switch leaves the other file intact.

All files use this public schema:

```json
{
  "schema": 1,
  "written_at": 1789430400,
  "rate_5h_pct": 32.5,
  "rate_5h_reset": 1789448400,
  "rate_7d_pct": 9.999999999999998,
  "rate_7d_reset": 1789887600
}
```

Percentages remain unfloored. Reset values are floored epoch seconds, and
`written_at` is the render's epoch second. Absent windows are omitted. A window
is updated only from a complete percentage and reset pair whose reset is not
older than the cached value. If neither window is complete, no file is written.

An existing file whose leading JSON object yields no complete pair of sane
numbers is treated as absent; `schema` and `written_at` are not consulted.
The next write carrying a complete window replaces it outright, and a write
with no complete window to put in its place deletes it instead of leaving it.

If `$XDG_STATE_HOME` relocates this directory, point a quota-pace reader's
`URDA_PACE_CACHE` file setting at
`$XDG_STATE_HOME/forged-statusline/cache-claude.json`.

### Update checker

The checker is enabled by default. It compares the cached remote version on
each render and performs a detached fetch at most weekly. Completed failures
are throttled like successful checks.

| Variable                                      | Default                                                                                          | Effect                             |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------- |
| `URDA_AI_FORGED_STATUS_LINE_UPDATE_CHECK`     | `1`                                                                                              | `0` disables fetches and the badge |

The checker state directory matches the rate-limit cache directory.

## Testing and development

```bash
make help                     # list targets
make lint                     # shellcheck all shell files
make test                     # every test suite, as CI's test job runs them
make test-statusline          # PASS/FAIL lines and summary
make test-statusline-verbose  # full visual catalog
make test-install             # installer atomicity and validation
make version-check            # compare VERSION with the renderer
```

The renderer suite pins `URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW` so countdowns
are deterministic.

## Design notes

- A non-zero exit or empty stdout blanks Claude Code's status line. The renderer
  therefore avoids `set -e`, treats JSON fields as optional, and falls back
  cleanly after a total `jq` failure.
- Bash 3.2 is the compatibility floor, including the stock macOS shell.
- Fixed readouts, 8-cell bars, and selector-free emoji prevent width shifts.
- Displayed percentages are denoised and floored, never rounded up.

## License

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Copyright 2026 Peter Urda

Licensed under the [Apache License, Version 2.0](LICENSE). See
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE) for the full terms and attribution.
