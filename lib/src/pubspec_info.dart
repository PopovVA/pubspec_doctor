import 'dart:io';

import 'package:yaml/yaml.dart';

/// A single entry under `dependency_overrides:`, either in `pubspec.yaml`
/// or in `pubspec_overrides.yaml`.
class DependencyOverride {
  DependencyOverride({
    required this.name,
    required this.source,
    required this.origin,
  });

  final String name;

  /// Where the override points: `path`, `git`, `sdk` or `version`.
  final String source;

  /// The file the override was found in.
  final String origin;

  /// Path and git overrides must not survive to a release; a version pin
  /// is sometimes intentional.
  bool get blocksRelease => source == 'path' || source == 'git';

  Map<String, Object?> toJson() =>
      {'name': name, 'source': source, 'origin': origin};
}

/// Parsed view of a project's `pubspec.yaml`, limited to what the doctor
/// needs: dependency names grouped by section and by source.
class PubspecInfo {
  PubspecInfo({
    required this.name,
    required this.dependencies,
    required this.devDependencies,
    required this.sdkDependencies,
    required this.hostedDependencies,
    required this.raw,
    this.workspacePaths = const [],
    this.overrides = const [],
  });

  /// The package name declared in `pubspec.yaml`.
  final String name;

  /// Names under `dependencies:`, excluding SDK dependencies.
  final Set<String> dependencies;

  /// Names under `dev_dependencies:`, excluding SDK dependencies.
  final Set<String> devDependencies;

  /// Dependencies resolved from an SDK (e.g. `flutter`, `flutter_test`).
  final Set<String> sdkDependencies;

  /// Dependencies hosted on pub.dev (default hosting), i.e. the ones the
  /// pub.dev health check can be run against. Path and git dependencies are
  /// excluded.
  final Set<String> hostedDependencies;

  /// The raw file content, used to detect non-import usages such as
  /// `packages/<name>/...` asset and font references.
  final String raw;

  /// Member package paths from a `workspace:` section (pub workspaces).
  /// Empty for regular packages.
  final List<String> workspacePaths;

  /// `dependency_overrides:` entries from both `pubspec.yaml` and
  /// `pubspec_overrides.yaml`.
  final List<DependencyOverride> overrides;

  static PubspecInfo load(Directory root) {
    final file = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    if (!file.existsSync()) {
      throw PubspecNotFoundException(file.path);
    }
    final overridesFile =
        File('${root.path}${Platform.pathSeparator}pubspec_overrides.yaml');
    return parse(
      file.readAsStringSync(),
      overridesContent:
          overridesFile.existsSync() ? overridesFile.readAsStringSync() : null,
    );
  }

  static PubspecInfo parse(String content, {String? overridesContent}) {
    final doc = loadYaml(content);
    if (doc is! YamlMap) {
      throw const FormatException('pubspec.yaml is not a YAML map');
    }
    final name = doc['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('pubspec.yaml has no package name');
    }

    final sdkDeps = <String>{};
    final hostedDeps = <String>{};

    Set<String> section(String key) {
      final node = doc[key];
      if (node is! YamlMap) return const {};
      final names = <String>{};
      for (final entry in node.entries) {
        final depName = entry.key.toString();
        final spec = entry.value;
        if (spec is YamlMap && spec.containsKey('sdk')) {
          sdkDeps.add(depName);
          continue;
        }
        names.add(depName);
        final isHosted = spec == null ||
            spec is String ||
            (spec is YamlMap &&
                !spec.containsKey('path') &&
                !spec.containsKey('git'));
        if (isHosted) hostedDeps.add(depName);
      }
      return names;
    }

    final workspace = doc['workspace'];
    final overrides = [
      ..._parseOverrides(doc['dependency_overrides'], 'pubspec.yaml'),
      if (overridesContent != null)
        ..._parseOverrides(
          (loadYaml(overridesContent) as YamlMap?)?['dependency_overrides'],
          'pubspec_overrides.yaml',
        ),
    ];

    return PubspecInfo(
      name: name,
      dependencies: section('dependencies'),
      devDependencies: section('dev_dependencies'),
      sdkDependencies: sdkDeps,
      hostedDependencies: hostedDeps,
      raw: content,
      workspacePaths: workspace is YamlList
          ? workspace.map((p) => p.toString()).toList()
          : const [],
      overrides: overrides,
    );
  }

  static List<DependencyOverride> _parseOverrides(Object? node, String origin) {
    if (node is! YamlMap) return const [];
    String sourceOf(Object? spec) {
      if (spec is YamlMap) {
        if (spec.containsKey('path')) return 'path';
        if (spec.containsKey('git')) return 'git';
        if (spec.containsKey('sdk')) return 'sdk';
      }
      return 'version';
    }

    return [
      for (final entry in node.entries)
        DependencyOverride(
          name: entry.key.toString(),
          source: sourceOf(entry.value),
          origin: origin,
        ),
    ];
  }
}

class PubspecNotFoundException implements Exception {
  PubspecNotFoundException(this.path);

  final String path;

  @override
  String toString() => 'No pubspec.yaml found at $path';
}
