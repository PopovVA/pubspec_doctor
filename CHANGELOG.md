# Changelog

## 0.1.0

- Initial release.
- Detects unused `dependencies` and `dev_dependencies` (imports, exports,
  conditional imports, `analysis_options.yaml` includes and
  `packages/<name>/` asset references all count as usage).
- Flags discontinued packages via the pub.dev API, including the suggested
  replacement.
- Flags stale packages (latest release older than `--stale-days`,
  default 730).
- `--json` output, `--offline` mode, `--ignore`, `--fail-on-stale` and
  CI-friendly exit codes.
