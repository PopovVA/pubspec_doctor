import 'dart:io';

/// Which packages a project references, split by where the reference lives.
class UsageResult {
  UsageResult({required this.public, required this.all});

  /// Packages referenced from runtime code — `lib/`, `bin/`, `web/` — or
  /// from `packages/<name>/` asset and font references in `pubspec.yaml`.
  /// These must be declared under `dependencies`.
  final Set<String> public;

  /// Packages referenced anywhere in the project, including `test/`,
  /// `tool/`, `example/` and `analysis_options.yaml`.
  final Set<String> all;
}

/// Finds which packages a project actually references.
///
/// A package counts as used when it appears as a `package:<name>/` URI in
/// any Dart file (imports, exports, conditional imports and string literals
/// all match — erring towards "used" keeps false positives out of the unused
/// list), in an `analysis_options.yaml` include, or as a `packages/<name>/`
/// asset/font reference in `pubspec.yaml`.
///
/// Config-driven usage also counts: a root-level `<package>.yaml` config
/// file, a mention in `build.yaml`, or a `dart run <package>` invocation in
/// scripts, Makefiles and CI workflows (including `.github/`).
class UsageScanner {
  static final _packageUri = RegExp('["\']package:([A-Za-z0-9_]+)/');
  // In YAML includes the URI is usually unquoted: `include: package:lints/...`
  static final _unquotedPackageUri = RegExp('package:([A-Za-z0-9_]+)/');
  static final _packageAsset = RegExp('packages/([A-Za-z0-9_]+)/');
  // `dart run pkg`, `flutter pub run pkg:script`, `dart pub run pkg` — the
  // package is a real dependency of the project, unlike `pub global run`.
  static final _dartRun =
      RegExp(r'(?:dart|flutter)\s+(?:pub\s+)?run\s+([A-Za-z0-9_]+)');
  // Words that can be a package name, for dep-aware matching in build.yaml.
  static final _packageWord = RegExp(r'([A-Za-z_][A-Za-z0-9_]+)');

  static const _skippedDirs = {'.dart_tool', 'build', '.git'};
  static const _publicDirs = {'lib', 'bin', 'web'};

  /// Non-Dart files that may invoke `dart run <package>`.
  static bool _isScript(String name) =>
      name.endsWith('.yaml') ||
      name.endsWith('.yml') ||
      name.endsWith('.sh') ||
      name.toLowerCase() == 'makefile' ||
      name.toLowerCase() == 'justfile' ||
      name.toLowerCase() == 'gnumakefile';

  UsageResult scan(
    Directory root, {
    required String pubspecRaw,
    Set<String> excludePaths = const {},
  }) {
    final public = <String>{};
    final all = <String>{};
    final excluded = excludePaths.map(_canonical).toSet();

    for (final entity in _walk(root, excluded)) {
      final name = _fileName(entity);
      final refs = <String>{};
      if (name.endsWith('.dart')) {
        refs.addAll(_matches(_packageUri, entity.readAsStringSync()));
      } else if (name == 'analysis_options.yaml') {
        refs.addAll(_matches(_unquotedPackageUri, entity.readAsStringSync()));
      } else if (_isScript(name)) {
        final content = entity.readAsStringSync();
        // `dart run <pkg>` in Makefiles, shell scripts and CI workflows.
        refs.addAll(_matches(_dartRun, content));
        // Builders configured in build.yaml reference their package name.
        if (name == 'build.yaml' || name == 'build.dev.yaml') {
          all.addAll(_matches(_packageWord, content));
        }
      } else {
        continue;
      }
      all.addAll(refs);
      if (_isPublic(root, entity)) public.addAll(refs);
    }

    // Tools configured via a root-level config file named after the
    // package, e.g. flutter_native_splash.yaml or flutter_launcher_icons.yaml.
    for (final entity in root.listSync()) {
      if (entity is! File) continue;
      final name = _fileName(entity);
      if (name.endsWith('.yaml') || name.endsWith('.yml')) {
        all.add(name.replaceFirst(RegExp(r'\.ya?ml$'), ''));
      }
    }

    final assetRefs = _matches(_packageAsset, pubspecRaw);
    all.addAll(assetRefs);
    public.addAll(assetRefs);

    return UsageResult(public: public, all: all);
  }

  Iterable<File> _walk(Directory root, Set<String> excluded) sync* {
    for (final entity in root.listSync()) {
      final name = _fileName(entity);
      if (entity is Directory) {
        // Hidden directories are skipped except .github, where CI workflows
        // may invoke `dart run <package>`.
        if (_skippedDirs.contains(name) ||
            (name.startsWith('.') && name != '.github')) {
          continue;
        }
        if (excluded.contains(_canonical(entity.path))) continue;
        yield* _walk(entity, excluded);
      } else if (entity is File) {
        yield entity;
      }
    }
  }

  static String _canonical(String path) =>
      Directory(path).absolute.uri.normalizePath().toString();

  bool _isPublic(Directory root, File file) {
    final rootSegments = root.absolute.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .length;
    final segments = file.absolute.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    // Files directly in the root (scripts, analysis_options.yaml) are not
    // runtime code.
    if (segments.length <= rootSegments + 1) return false;
    return _publicDirs.contains(segments[rootSegments]);
  }

  Set<String> _matches(RegExp pattern, String content) =>
      pattern.allMatches(content).map((match) => match.group(1)!).toSet();

  String _fileName(FileSystemEntity entity) =>
      entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
}
