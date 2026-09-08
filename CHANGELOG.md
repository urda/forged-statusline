# Urda's Forged Status Line CHANGELOG

## [1.0.3] - 2026-09-08

### Added

- The release gate now lives in `scripts/release-gate.sh`. `make release-gate`
  runs it by hand, and the Release Gate workflow calls the same target. One
  copy of the checks serves CI and the local tree, and `make lint` covers the
  script. The target stays outside `make test`, because the gate fails on any
  day that is not a release day.
- Three new gate checks. A pushed `vX.Y.Z` tag must point into the current
  history, so a spent version number cannot ship on a second commit. The
  CHANGELOG section for the version must carry real `- ` notes, so a bare
  heading cannot pass. The `[X.Y.Z]:` link reference must end in
  `/releases/tag/vX.Y.Z`, so a line copied from the release above cannot keep
  a stale target.

### Changed

- The rate-limit cache `schema` field is now `3`. Each window may carry a
  read stamp, `rate_5h_read` and `rate_7d_read`: the epoch second of the API
  reply that produced its percentage and reset. The renderer recovers it from
  the Claude Code payload's `prompt_cache.expires_at` minus the cache TTL.
  Antigravity has no source for one, so an agy cache never carries a stamp.
  Consumers reading named keys are unaffected.

### Fixed

- Concurrent Claude Code sessions can no longer pin a stale rate-limit
  percentage. The 1.0.2 rule kept the higher percentage on an equal reset, on
  the assumption that usage inside one window only accrues. The provider can
  also lower a percentage, and on 2026-09-04 an idle session replayed a
  frozen 29% weekly reading that beat the live 3% on every write until the
  reset. On an equal reset the newer read stamp now wins in either direction,
  a tie takes the incoming pair, and an unstamped replay never displaces a
  stamped pair. Unstamped pairs on both sides keep the higher-percentage
  rule, so agy behaves as before. A stamp ahead of the clock by more than an
  hour, or older than a week and an hour, is dropped, and a schema-2 file
  heals on its first stamped write.
- The rate-limit cache writer now bounds every reset against the clock: a
  five-hour reset may sit at most 6 hours ahead, a seven-day reset at most
  7 days and 1 hour ahead (one window length plus an hour of skew slack). A
  plausible far-future reset used to out-rank every real reset in the
  monotonic guard and wedge the window until the user deleted the cache file
  by hand. The bound applies to incoming and cached pairs alike, so an
  already wedged cache heals on the next valid write, and normal provider
  ordering protection is unchanged. A dead clock skips the bound rather than
  freezing the cache.
- The test suite no longer writes to the real rate-limit cache directory. One
  update-check case enabled cache writing without its own jail, so the writer
  resolved the maintainer's real state directory, and its no-incoming-data
  branch deleted any cache file it read as empty or corrupt. The suite now
  exports a throwaway `WRITE_CACHE_DIR` for every case, so a case that forgets
  its own jail can no longer reach live data. Test-only change; the renderer is
  untouched.

## [1.0.2] - 2026-08-26

### Added

- The rate-limit cache now carries `observed_at`: the epoch second of the last
  write in which an effective percentage actually changed. It is stamped only
  on movement, so a genuine plateau keeps its old stamp and a consumer can
  tell a fresh reading from a re-stamped one. `written_at` keeps its meaning
  of "this file was last touched". A schema-1 file has no `observed_at` to
  carry forward, so the first schema-2 write stamps the current clock once.

### Changed

- The rate-limit cache `schema` field is now `2`, for the added `observed_at`.
  Consumers reading named keys are unaffected.
- README now opens with a demo screenshot (`docs/img/demo.png`) and drops the
  text render examples it duplicated; the sample model name is current.

### Security

- State files (the rate-limit cache, `last_check`, and `remote_version`) are
  now written through private (`umask 077`) `mktemp` swaps instead of
  predictable `.$$.tmp` names or in-place redirects. A pre-existing
  world-readable state file goes private on its next write, and a symlink or
  directory planted at a state path is replaced or refused, never written
  through.

### Fixed

- Concurrent sessions no longer clobber the rate-limit cache with stale
  percentages. An idle session's hours-old reading shares the live reset
  epoch, so the old non-regressing-reset guard admitted it. The window guard
  is now reset-keyed: a newer reset takes the incoming pair whole, an equal
  reset keeps the higher percentage (usage inside one window only accrues),
  and an older reset never replaces the cached pair. Every writer applies the
  same rule, so the unlocked write race converges on the freshest reading.
- Clock values now normalize to plain epoch integers before any arithmetic:
  the debug clock (`URDA_AI_FORGED_STATUS_LINE_DEBUG_NOW`), the rate-limit
  reset epochs, the update-check `last_check` state, and the update-lock
  timestamp. A malformed value such as `08` (invalid octal in bash
  arithmetic) or an arithmetic-expression shape previously broke countdown
  and throttle math; it now degrades to the real clock or a safe default.

## [1.0.1] - 2026-08-03

### Changed

- README badge work: consistent badge styles, an embedded Antigravity mark,
  and trimmed values from the README that should not be user touched most
  days.

### Fixed

- Light theme now retints cyan to a dark teal (`38;5;30`); palette cyan
  washed out on white backgrounds. Affects the context-window badge, the
  effort readout, and the update badge.

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

[1.0.3]: https://github.com/urda/forged-statusline/releases/tag/v1.0.3
[1.0.2]: https://github.com/urda/forged-statusline/releases/tag/v1.0.2
[1.0.1]: https://github.com/urda/forged-statusline/releases/tag/v1.0.1
[1.0.0]: https://github.com/urda/forged-statusline/releases/tag/v1.0.0
