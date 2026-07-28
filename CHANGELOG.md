# Urda's Forged Status Line CHANGELOG

## [1.0.0] - 2026-07-28

First public release of Urda's Forged Status Line (`FSL`, `fsl`).

### Features

- Two-row status line with model, effort, thinking-disabled state, working
  directory, context usage, and optional 5-hour/7-day rate gauges.
- Fixed-width bars with eighth-cell fill, floored display percentages, reset
  countdowns, and per-gauge icon escalation.
- Warn and alarm thresholds per gauge, each falling back to a shared pair and
  then to built-in defaults.
- Unknown and malformed-input fallbacks that keep the status line visible,
  including `???%`, `(Missing ...)`, and a missing-`jq` notice.
- Context-window badges for any window below 1M and normalization of legacy
  `(1M context)` model names.
- Dark/light themes, a master icon switch, and per-icon overrides.
- Best-effort compatibility with Antigravity (`agy`) and GitHub Copilot
  (`copilot`).
- Optional detached rate-limit caches for `claude` and `agy`, with agy cached
  per quota pool (`cache-agy-gemini.json` / `cache-agy-3p.json`). Percentages
  remain unfloored, resets are floored, absent windows are omitted, and a
  complete pair replaces a cached window only when its reset is not older.
  Values that would not read back are never written, and a file nothing can
  replace is removed.
- Weekly detached update checks with a `[FSL Update Available]` badge and
  configurable source URLs.
- Atomic `--update` and installer flows using `curl` or `wget`, Bash parsing, and
  anchored renderer identity and completeness checks.
- `--update`, `--version`, and `--help` flags. Any other argument is ignored in
  favor of a normal render.
- Bash 3.2 and `jq` 1.6 minimums, both asserted by CI rather than assumed.

[1.0.0]: https://github.com/urda/forged-statusline/releases/tag/v1.0.0
