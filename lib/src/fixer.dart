import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'report.dart';

/// Applies fixes for a [Report] by editing `pubspec.yaml` (and
/// `pubspec_overrides.yaml`) in place. Uses yaml_edit, so comments,
/// ordering and formatting are preserved.
///
/// Safe fixes: remove unused dependencies, move wrongly promoted ones to
/// the right section, and delete path/git `dependency_overrides`.
/// Opt-in fix: bump constraints that do not allow the latest release
/// (changes behavior, so it is separate).
class Fixer {
  /// Returns human-readable descriptions of the edits that were applied.
  List<String> apply(
    Directory root,
    Report report, {
    bool safe = true,
    bool outdated = false,
  }) {
    final applied = <String>[];
    final pubspecFile =
        File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    final editor = YamlEditor(pubspecFile.readAsStringSync());

    YamlMap? section(String name) {
      final doc = loadYaml(editor.toString());
      final node = doc is YamlMap ? doc[name] : null;
      return node is YamlMap ? node : null;
    }

    Object? plain(Object? node) {
      if (node is YamlMap) {
        return {
          for (final entry in node.entries)
            entry.key.toString(): plain(entry.value),
        };
      }
      if (node is YamlList) return [for (final item in node) plain(item)];
      return node;
    }

    if (safe) {
      for (final name in report.unusedDependencies) {
        if (section('dependencies')?.containsKey(name) ?? false) {
          editor.remove(['dependencies', name]);
          applied.add('removed unused dependency $name');
        }
      }
      for (final name in report.unusedDevDependencies) {
        if (section('dev_dependencies')?.containsKey(name) ?? false) {
          editor.remove(['dev_dependencies', name]);
          applied.add('removed unused dev_dependency $name');
        }
      }

      void move(String name, {required String from, required String to}) {
        final source = section(from);
        if (source == null || !source.containsKey(name)) return;
        final value = plain(source[name]);
        editor.remove([from, name]);
        if (section(to) == null) {
          editor.update([to], {name: value});
        } else {
          editor.update([to, name], value);
        }
        applied.add('moved $name from $from to $to');
      }

      for (final name in report.overPromoted) {
        move(name, from: 'dependencies', to: 'dev_dependencies');
      }
      for (final name in report.underPromoted) {
        move(name, from: 'dev_dependencies', to: 'dependencies');
      }

      _removeOverrides(
        report,
        editor,
        origin: 'pubspec.yaml',
        applied: applied,
      );

      _removeMissingAssetDeclarations(report, editor, applied);
    }

    if (outdated) {
      for (final entry in report.outdatedConstraints) {
        final name = entry.health.name;
        final target = (section('dependencies')?.containsKey(name) ?? false)
            ? 'dependencies'
            : (section('dev_dependencies')?.containsKey(name) ?? false)
                ? 'dev_dependencies'
                : null;
        if (target == null) continue;
        editor.update([target, name], '^${entry.health.latestVersion}');
        applied.add('bumped $name from "${entry.constraint}" '
            'to "^${entry.health.latestVersion}"');
      }
    }

    pubspecFile.writeAsStringSync(editor.toString());

    if (safe) {
      _fixOverridesFile(root, report, applied);
    }

    return applied;
  }

  /// Deletes asset files reported as possibly unused. Only files tracked
  /// by git are deleted, so every deletion is recoverable with
  /// `git checkout`; untracked files are skipped with a note.
  List<String> deleteUnusedAssets(Directory root, Report report) {
    final applied = <String>[];
    for (final asset in report.unusedAssets) {
      final file = File(
          '${root.path}${Platform.pathSeparator}${asset.replaceAll('/', Platform.pathSeparator)}');
      if (!file.existsSync()) continue;
      if (!_isGitTracked(root, asset)) {
        applied.add('skipped $asset (not tracked by git — delete it manually)');
        continue;
      }
      file.deleteSync();
      applied.add('deleted unused asset $asset');
    }
    return applied;
  }

  bool _isGitTracked(Directory root, String relativePath) {
    try {
      return Process.runSync(
            'git',
            [
              '-C',
              root.path,
              'ls-files',
              '--error-unmatch',
              '--',
              relativePath
            ],
          ).exitCode ==
          0;
    } on ProcessException {
      return false;
    }
  }

  /// Removes `flutter: assets:` entries whose path does not exist on disk.
  /// Missing font files are left alone — restructuring font families is a
  /// human decision.
  void _removeMissingAssetDeclarations(
    Report report,
    YamlEditor editor,
    List<String> applied,
  ) {
    if (report.missingAssets.isEmpty) return;
    final missing = report.missingAssets.toSet();

    String? pathOf(Object? entry) {
      if (entry is String) return entry;
      if (entry is YamlMap && entry['path'] is String) {
        return entry['path'] as String;
      }
      return null;
    }

    String normalize(String path) =>
        path.startsWith('./') ? path.substring(2) : path;

    YamlList? assetsList() {
      final doc = loadYaml(editor.toString());
      final flutter = doc is YamlMap ? doc['flutter'] : null;
      final assets = flutter is YamlMap ? flutter['assets'] : null;
      return assets is YamlList ? assets : null;
    }

    final assets = assetsList();
    if (assets == null) return;
    // Remove from the end so earlier indices stay valid.
    for (var i = assets.length - 1; i >= 0; i--) {
      final path = pathOf(assets[i]);
      if (path != null && missing.contains(normalize(path))) {
        editor.remove(['flutter', 'assets', i]);
        applied.add('removed missing asset declaration $path');
      }
    }

    if (assetsList()?.isEmpty ?? false) {
      editor.remove(['flutter', 'assets']);
      final doc = loadYaml(editor.toString());
      final flutter = doc is YamlMap ? doc['flutter'] : null;
      if (flutter is YamlMap && flutter.isEmpty) {
        editor.remove(['flutter']);
      }
    }
  }

  /// Removes path/git overrides that live in the file [origin] using the
  /// given [editor]; drops the whole `dependency_overrides` key when it
  /// becomes empty.
  void _removeOverrides(
    Report report,
    YamlEditor editor, {
    required String origin,
    required List<String> applied,
  }) {
    final targets = report.overrides
        .where((o) => o.blocksRelease && o.origin == origin)
        .map((o) => o.name);
    var removedAny = false;
    for (final name in targets) {
      final doc = loadYaml(editor.toString());
      final overrides = doc is YamlMap ? doc['dependency_overrides'] : null;
      if (overrides is! YamlMap || !overrides.containsKey(name)) continue;
      editor.remove(['dependency_overrides', name]);
      applied.add('removed ${origin == 'pubspec.yaml' ? '' : '$origin '}'
          'dependency_override for $name');
      removedAny = true;
    }
    if (removedAny) {
      final doc = loadYaml(editor.toString());
      final overrides = doc is YamlMap ? doc['dependency_overrides'] : null;
      if (overrides is YamlMap && overrides.isEmpty) {
        editor.remove(['dependency_overrides']);
      }
    }
  }

  void _fixOverridesFile(Directory root, Report report, List<String> applied) {
    final file =
        File('${root.path}${Platform.pathSeparator}pubspec_overrides.yaml');
    if (!file.existsSync()) return;
    final editor = YamlEditor(file.readAsStringSync());
    _removeOverrides(
      report,
      editor,
      origin: 'pubspec_overrides.yaml',
      applied: applied,
    );
    final result = editor.toString();
    final doc = loadYaml(result);
    if (doc == null || (doc is YamlMap && doc.isEmpty)) {
      file.deleteSync();
      applied.add('deleted empty pubspec_overrides.yaml');
    } else {
      file.writeAsStringSync(result);
    }
  }
}
