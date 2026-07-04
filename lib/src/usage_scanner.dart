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
class UsageScanner {
  static final _packageUri = RegExp('["\']package:([A-Za-z0-9_]+)/');
  // In YAML includes the URI is usually unquoted: `include: package:lints/...`
  static final _unquotedPackageUri = RegExp('package:([A-Za-z0-9_]+)/');
  static final _packageAsset = RegExp('packages/([A-Za-z0-9_]+)/');

  static const _skippedDirs = {'.dart_tool', 'build', '.git'};
  static const _publicDirs = {'lib', 'bin', 'web'};

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
      final Set<String> refs;
      if (name.endsWith('.dart')) {
        refs = _matches(_packageUri, entity.readAsStringSync());
      } else if (name == 'analysis_options.yaml') {
        refs = _matches(_unquotedPackageUri, entity.readAsStringSync());
      } else {
        continue;
      }
      all.addAll(refs);
      if (_isPublic(root, entity)) public.addAll(refs);
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
        if (_skippedDirs.contains(name) || name.startsWith('.')) continue;
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
