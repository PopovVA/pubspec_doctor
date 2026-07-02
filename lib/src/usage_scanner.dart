import 'dart:io';

/// Finds which packages a project actually references.
///
/// A package counts as used when it appears as a `package:<name>/` URI in any
/// Dart file (imports, exports, conditional imports and string literals all
/// match — erring towards "used" keeps false positives out of the unused
/// list), in an `analysis_options.yaml` include, or as a `packages/<name>/`
/// asset/font reference in `pubspec.yaml`.
class UsageScanner {
  static final _packageUri = RegExp('["\']package:([A-Za-z0-9_]+)/');
  // In YAML includes the URI is usually unquoted: `include: package:lints/...`
  static final _unquotedPackageUri = RegExp('package:([A-Za-z0-9_]+)/');
  static final _packageAsset = RegExp('packages/([A-Za-z0-9_]+)/');

  static const _skippedDirs = {'.dart_tool', 'build', '.git'};

  Set<String> scan(Directory root, {required String pubspecRaw}) {
    final used = <String>{};

    for (final entity in _walk(root)) {
      final name = _fileName(entity);
      if (name.endsWith('.dart')) {
        used.addAll(_matches(_packageUri, entity.readAsStringSync()));
      } else if (name == 'analysis_options.yaml') {
        used.addAll(_matches(_unquotedPackageUri, entity.readAsStringSync()));
      }
    }

    for (final match in _packageAsset.allMatches(pubspecRaw)) {
      used.add(match.group(1)!);
    }

    return used;
  }

  Iterable<File> _walk(Directory root) sync* {
    for (final entity in root.listSync()) {
      final name = _fileName(entity);
      if (entity is Directory) {
        if (_skippedDirs.contains(name) || name.startsWith('.')) continue;
        yield* _walk(entity);
      } else if (entity is File) {
        yield entity;
      }
    }
  }

  Set<String> _matches(RegExp pattern, String content) =>
      pattern.allMatches(content).map((match) => match.group(1)!).toSet();

  String _fileName(FileSystemEntity entity) =>
      entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
}
