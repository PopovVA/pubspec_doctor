# Changelog

## [0.3.0](https://github.com/PopovVA/pubspec_doctor/compare/v0.2.0...v0.3.0) (2026-07-03)


### Features

* config file and codegen auto-detection ([#5](https://github.com/PopovVA/pubspec_doctor/issues/5)) ([b3a7521](https://github.com/PopovVA/pubspec_doctor/commit/b3a7521dffec8d356266e93b2baa31c576a87b1f))

## [0.2.0](https://github.com/PopovVA/pubspec_doctor/compare/v0.1.0...v0.2.0) (2026-07-02)


### Features

* first-class CI integration ([#2](https://github.com/PopovVA/pubspec_doctor/issues/2)) ([b78d28f](https://github.com/PopovVA/pubspec_doctor/commit/b78d28f529cb06c6b8323e463894382ab34a24f4))

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
