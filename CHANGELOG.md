# Changelog

## [0.5.0](https://github.com/PopovVA/pubspec_doctor/compare/v0.4.0...v0.5.0) (2026-07-04)


### Features

* pub workspaces support and leftover dependency_overrides check ([#11](https://github.com/PopovVA/pubspec_doctor/issues/11)) ([31c6868](https://github.com/PopovVA/pubspec_doctor/commit/31c68684a97f41ae49bdcc59b3914697fa161525))

## [0.4.0](https://github.com/PopovVA/pubspec_doctor/compare/v0.3.1...v0.4.0) (2026-07-03)


### Features

* promotion checks and SDK compatibility warnings ([#9](https://github.com/PopovVA/pubspec_doctor/issues/9)) ([4d641ab](https://github.com/PopovVA/pubspec_doctor/commit/4d641abfa502223938ecb17816763026fe5fb46c))

## [0.3.1](https://github.com/PopovVA/pubspec_doctor/compare/v0.3.0...v0.3.1) (2026-07-03)


### Bug Fixes

* **ci:** move major tag by release SHA, not unresolvable tag name ([#7](https://github.com/PopovVA/pubspec_doctor/issues/7)) ([b4a2270](https://github.com/PopovVA/pubspec_doctor/commit/b4a2270879f4bfb00bed2e4a67890317a2e14357))

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
