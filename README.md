# pubspec_doctor

[![CI](https://github.com/PopovVA/pubspec_doctor/actions/workflows/ci.yml/badge.svg)](https://github.com/PopovVA/pubspec_doctor/actions/workflows/ci.yml)

CLI that audits the dependencies in your `pubspec.yaml`:

- **Unused** — declared in `dependencies` / `dev_dependencies` but never
  referenced in the project.
- **Discontinued** — flagged as discontinued on pub.dev, including the
  suggested replacement package when the author provided one.
- **Stale** — the latest release is older than a threshold (2 years by
  default), a common sign of an unmaintained package.

Existing tools cover these separately (`dependency_validator` for unused,
`dart pub outdated` shows discontinued); `pubspec_doctor` gives you a single
report and a single CI gate.

## Install

```sh
dart pub global activate pubspec_doctor
```

## Usage

Run it from your project root (or point it anywhere with `--path`):

```sh
pubspec_doctor
```

Example output:

```
pubspec_doctor — diagnosis for "my_app" (14 dependencies checked)

Unused dependencies:
  - collection
  - rxdart

Discontinued packages:
  - flutter_markdown (replaced by: flutter_markdown_plus)

Stale packages (no release in a long time):
  - some_pkg (latest 0.3.1 published 1204 days ago)
```

### Options

| Flag | Description |
| --- | --- |
| `-p, --path` | Project root containing `pubspec.yaml` (default: `.`). |
| `-i, --ignore` | Package names to exclude from all checks (repeatable). |
| `--stale-days` | Staleness threshold in days (default: `730`). |
| `--offline` | Skip pub.dev health checks; unused analysis only. |
| `--fail-on-stale` | Non-zero exit code when stale packages are found. |
| `--json` | Machine-readable JSON report. |

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | No problems found. |
| `1` | Unused or discontinued packages found (stale too, with `--fail-on-stale`). |
| `2` | Usage or runtime error (e.g. no `pubspec.yaml`). |

### CI

```yaml
- run: dart pub global activate pubspec_doctor
- run: pubspec_doctor --fail-on-stale
```

## How "unused" is detected

A package counts as **used** when it appears as a `package:<name>/` URI in
any Dart file (imports, exports and conditional imports), in an
`analysis_options.yaml` include (so `lints` / `flutter_lints` are not false
positives), or as a `packages/<name>/` asset or font reference in
`pubspec.yaml`. SDK dependencies (`flutter`, `flutter_test`, …) are skipped.

Packages that are genuinely used without being imported — e.g.
`build_runner` or other codegen runners — should be listed via `--ignore`:

```sh
pubspec_doctor --ignore build_runner
```

## Roadmap

- Config file (`pubspec_doctor.yaml`) for permanent ignores.
- Auto-detect codegen packages (`build_runner`, `freezed`, …) as used.
- Under-/over-promotion checks (dep that should be a dev_dependency and
  vice versa).
- Dart SDK compatibility check for the latest release of each dependency.

## License

[MIT](LICENSE)
