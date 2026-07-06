# pubspec_doctor

[![CI](https://github.com/PopovVA/pubspec_doctor/actions/workflows/ci.yml/badge.svg)](https://github.com/PopovVA/pubspec_doctor/actions/workflows/ci.yml)

CLI that audits the dependencies in your `pubspec.yaml`:

- **Unused** — declared in `dependencies` / `dev_dependencies` but never
  referenced in the project.
- **Wrongly promoted** — a `dependencies` entry only used outside runtime
  code (should be a dev_dependency), or a `dev_dependencies` entry used in
  `lib/`, `bin/` or `web/` (should be a regular dependency).
- **Discontinued** — flagged as discontinued on pub.dev, including the
  suggested replacement package when the author provided one.
- **Stale** — the latest release is older than a threshold (2 years by
  default), a common sign of an unmaintained package.
- **SDK-incompatible** *(informational)* — the latest release requires a
  newer Dart SDK than you are running, so upgrades are silently blocked.
- **Outdated constraint** *(informational)* — the declared constraint does
  not allow the latest release (e.g. `^0.13.0` while pub.dev is at
  `1.2.0`), which usually means a package was added at an old major.
- **Leftover overrides** — `dependency_overrides` entries in `pubspec.yaml`
  or `pubspec_overrides.yaml`. Path and git overrides fail the run (they
  must not survive to a release); version pins are warnings.
- **Missing assets** — declared under `flutter: assets:` or `fonts:` but
  not present on disk, which breaks the Flutter build.
- **Unused assets** *(informational)* — asset files that no string literal
  in the project references. Dead images silently bloat the app bundle.

Pub workspaces are supported out of the box: when the pubspec has a
`workspace:` section, every member package is diagnosed (workspace members
are excluded from the pub.dev health check, and member configs refine the
root config).

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
| `--fix` | Apply safe fixes to `pubspec.yaml` (see below). |
| `--fix-outdated` | Also bump constraints that block the latest release. |

### Fixing what it finds

`--fix` edits `pubspec.yaml` in place, preserving comments and formatting:
unused dependencies are removed, wrongly promoted ones move to the right
section, and path/git `dependency_overrides` are deleted. Discontinued and
stale packages are never touched — replacing a package is your call.

`--fix-outdated` additionally rewrites constraints that do not allow the
latest release (e.g. `^0.13.0` becomes `^1.6.0`). That can pull in breaking
changes, which is why it is a separate flag. After any fix, review the git
diff, then run `dart pub get` and your tests.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | No problems found. |
| `1` | Unused, wrongly promoted or discontinued packages, or path/git overrides found (stale too, with `--fail-on-stale`). |
| `2` | Usage or runtime error (e.g. no `pubspec.yaml`). |

SDK-incompatible latest releases and outdated constraints are reported as warnings and never affect
the exit code.

## CI integration

The exit code makes `pubspec_doctor` behave like a test suite: `0` passes the
build, `1` fails it. On GitHub Actions, findings are also emitted as
annotations, so unused or discontinued packages show up directly on
`pubspec.yaml` in the pull request UI.

The easiest way is the bundled GitHub Action:

```yaml
name: Dependency audit
on: [pull_request]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: PopovVA/pubspec_doctor@v0
        with:
          # path: packages/my_app        # for monorepos
          args: --fail-on-stale --ignore build_runner
```

Or run the CLI yourself on any CI system:

```yaml
- run: dart pub global activate pubspec_doctor
- run: dart pub global run pubspec_doctor --fail-on-stale
```

For machine-readable pipelines, combine `--json` with `jq`:

```sh
pubspec_doctor --json | jq '.unusedDependencies'
```

## Configuration

Create `pubspec_doctor.yaml` next to your `pubspec.yaml` (or add a
top-level `pubspec_doctor:` section to `pubspec.yaml` itself):

```yaml
ignore:
  - some_internal_pkg
stale_days: 365
fail_on_stale: true
```

CLI flags take precedence over the config file; `ignore` lists are merged.

## How "unused" is detected

A package counts as **used** when it appears as a `package:<name>/` URI in
any Dart file (imports, exports and conditional imports), in an
`analysis_options.yaml` include (so `lints` / `flutter_lints` are not false
positives), or as a `packages/<name>/` asset or font reference in
`pubspec.yaml`. SDK dependencies (`flutter`, `flutter_test`, …) are skipped.

Codegen and tool packages that are used without being imported are
recognized automatically:

- generators whose companion package is referenced in code — `freezed`
  (via `freezed_annotation`), `json_serializable` (via `json_annotation`),
  `drift_dev` (via `drift`), `riverpod_generator`, `mobx_codegen`, and
  other common pairs;
- `build_runner`, when any declared package looks like a generator;
- tools configured through a top-level `pubspec.yaml` key, such as
  `flutter_launcher_icons` and `flutter_native_splash`;
- tools configured through a root-level `<package>.yaml` file
  (e.g. `flutter_native_splash.yaml`);
- packages referenced in `build.yaml`;
- packages invoked as `dart run <package>` / `flutter pub run <package>`
  in shell scripts, Makefiles, justfiles and CI workflows (including
  `.github/workflows`).

Anything else that is intentionally unimported can be listed in the
config `ignore` or via `--ignore`.

## How "unused assets" are detected

Files from declared `flutter: assets:` entries (directories are
non-recursive, exactly like in Flutter) are matched against string
literals in your Dart code. An asset counts as **used** when a literal
contains its full path or its file name, or when a literal with
interpolation mentions its directory — so
`Image.asset('assets/flags/$code.png')` marks the whole `assets/flags/`
directory as used. Resolution variants (`assets/2.0x/logo.png`) resolve
to their logical path first. Because dynamic paths make certainty
impossible, unused assets are reported as warnings and never fail the
build.

## Roadmap

Suggestions welcome — [file an issue](https://github.com/PopovVA/pubspec_doctor/issues).

## License

[MIT](LICENSE)
