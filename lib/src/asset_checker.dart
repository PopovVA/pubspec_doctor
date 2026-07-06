import 'dart:io';

/// Findings about the `flutter: assets:` section.
class AssetFindings {
  AssetFindings({required this.missing, required this.unused});

  /// Declared in the pubspec but not present on disk — the build breaks.
  final List<String> missing;

  /// Present on disk but never referenced anywhere. A heuristic: assets
  /// loaded through interpolated paths make certainty impossible, so this
  /// errs towards "used" and is reported as a warning only.
  final List<String> unused;
}

/// Checks declared assets against the file system and against string
/// literals in the project's Dart code.
///
/// An asset counts as used when any string literal contains its full path
/// or its file name, or when a literal with interpolation (`$`) mentions
/// its directory — the `'assets/images/${name}.png'` pattern. Resolution
/// variants (`assets/2.0x/logo.png`) are resolved against their logical
/// path before matching.
class AssetChecker {
  static final _stringLiteral = RegExp('\'([^\'\\n]*)\'|"([^"\\n]*)"');
  static final _resolutionDir = RegExp(r'^\d+(\.\d+)?x$');

  static const _skippedDirs = {'.dart_tool', 'build', '.git'};

  AssetFindings check(
    Directory root, {
    required List<String> assetPaths,
    required List<String> fontAssets,
  }) {
    final missing = <String>[];
    final assetFiles = <String>{};

    for (final entry in assetPaths) {
      final relative = _normalize(entry);
      if (relative.endsWith('/')) {
        final dir = Directory('${root.path}/$relative');
        if (!dir.existsSync()) {
          missing.add(relative);
          continue;
        }
        // Flutter includes only the files directly inside a declared
        // directory, not its subdirectories.
        for (final file in dir.listSync().whereType<File>()) {
          assetFiles.add('$relative${_basename(file.path)}');
        }
      } else {
        if (File('${root.path}/$relative').existsSync()) {
          assetFiles.add(relative);
        } else {
          missing.add(relative);
        }
      }
    }

    for (final font in fontAssets) {
      final relative = _normalize(font);
      if (!File('${root.path}/$relative').existsSync()) {
        missing.add(relative);
      }
    }

    if (assetFiles.isEmpty) {
      return AssetFindings(missing: missing..sort(), unused: const []);
    }

    final literals = _collectStringLiterals(root);
    final interpolatedDirs = literals
        .where((l) => l.contains(r'$'))
        .map(_directoryOf)
        .where((dir) => dir.isNotEmpty)
        .toSet();

    bool isUsed(String asset) {
      final logical = _logicalPath(asset);
      final base = _basename(logical);
      if (literals.any((l) => l.contains(logical) || l.contains(base))) {
        return true;
      }
      final dir = _directoryOf(logical);
      return interpolatedDirs
          .any((d) => d.startsWith(dir) || dir.startsWith(d));
    }

    final unused = assetFiles.where((a) => !isUsed(a)).toList()..sort();
    return AssetFindings(missing: missing..sort(), unused: unused);
  }

  Set<String> _collectStringLiterals(Directory root) {
    final literals = <String>{};
    void walk(Directory dir) {
      for (final entity in dir.listSync()) {
        final name = _basename(entity.path);
        if (entity is Directory) {
          if (_skippedDirs.contains(name) || name.startsWith('.')) continue;
          walk(entity);
        } else if (entity is File && name.endsWith('.dart')) {
          for (final match
              in _stringLiteral.allMatches(entity.readAsStringSync())) {
            final value = match.group(1) ?? match.group(2);
            if (value != null && value.isNotEmpty) literals.add(value);
          }
        }
      }
    }

    walk(root);
    return literals;
  }

  /// `assets/2.0x/logo.png` resolves to the logical `assets/logo.png` that
  /// code actually references.
  String _logicalPath(String path) {
    final segments =
        path.split('/').where((s) => !_resolutionDir.hasMatch(s)).toList();
    return segments.join('/');
  }

  String _normalize(String path) =>
      path.startsWith('./') ? path.substring(2) : path;

  String _basename(String path) =>
      path.split(Platform.pathSeparator).last.split('/').last;

  String _directoryOf(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '' : path.substring(0, index + 1);
  }
}
