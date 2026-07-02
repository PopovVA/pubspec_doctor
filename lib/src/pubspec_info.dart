import 'dart:io';

import 'package:yaml/yaml.dart';

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

  static PubspecInfo load(Directory root) {
    final file = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    if (!file.existsSync()) {
      throw PubspecNotFoundException(file.path);
    }
    return parse(file.readAsStringSync());
  }

  static PubspecInfo parse(String content) {
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

    return PubspecInfo(
      name: name,
      dependencies: section('dependencies'),
      devDependencies: section('dev_dependencies'),
      sdkDependencies: sdkDeps,
      hostedDependencies: hostedDeps,
      raw: content,
    );
  }
}

class PubspecNotFoundException implements Exception {
  PubspecNotFoundException(this.path);

  final String path;

  @override
  String toString() => 'No pubspec.yaml found at $path';
}
