# Changelog

## [0.9.0](https://github.com/PopovVA/pubspec_doctor/compare/v0.8.0...v0.9.0) (2026-07-06)


### Features

* missing and unused asset checks ([#24](https://github.com/PopovVA/pubspec_doctor/issues/24)) ([4a92448](https://github.com/PopovVA/pubspec_doctor/commit/4a92448de14c58e192158d21e26adae5536557ab))

## [0.8.0](https://github.com/PopovVA/pubspec_doctor/compare/v0.7.1...v0.8.0) (2026-07-06)


### Features

* detect config-driven package usage ([#22](https://github.com/PopovVA/pubspec_doctor/issues/22)) ([38f9c32](https://github.com/PopovVA/pubspec_doctor/commit/38f9c3283c34fe5a9fda20364d43db7c4ba5887a))

## [0.7.1](https://github.com/PopovVA/pubspec_doctor/compare/v0.7.0...v0.7.1) (2026-07-05)


### Bug Fixes

* shorten action description for GitHub Marketplace ([#20](https://github.com/PopovVA/pubspec_doctor/issues/20)) ([3c5feb2](https://github.com/PopovVA/pubspec_doctor/commit/3c5feb28a98d4d5eb78441e68cae131883d93d53))

## [0.7.0](https://github.com/PopovVA/pubspec_doctor/compare/v0.6.0...v0.7.0) (2026-07-04)


### Features

* --fix and --fix-outdated apply findings to pubspec.yaml ([#18](https://github.com/PopovVA/pubspec_doctor/issues/18)) ([389e524](https://github.com/PopovVA/pubspec_doctor/commit/389e524face7f323d7fcf56042dea6a5f44195b9))

## [0.6.0](https://github.com/PopovVA/pubspec_doctor/compare/v0.5.1...v0.6.0) (2026-07-04)


### Features

* warn when a declared constraint does not allow the latest release ([#16](https://github.com/PopovVA/pubspec_doctor/issues/16)) ([1ac2621](https://github.com/PopovVA/pubspec_doctor/commit/1ac26213bd4705c47a59c8280fb7c24f6512fea0))

## [0.5.1](https://github.com/PopovVA/pubspec_doctor/compare/v0.5.0...v0.5.1) (2026-07-04)


### Bug Fixes

* tighten dependency lower bounds for downgrade analysis ([#13](https://github.com/PopovVA/pubspec_doctor/issues/13)) ([484a3f9](https://github.com/PopovVA/pubspec_doctor/commit/484a3f9859177778861e1663c93c0a42da450853))

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
