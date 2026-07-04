import 'dart:io';

import 'package:yaml/yaml.dart';

/// Project-level configuration, loaded from `pubspec_doctor.yaml` in the
/// project root or, if absent, from a top-level `pubspec_doctor:` section
/// in `pubspec.yaml`:
///
/// ```yaml
/// ignore:
///   - build_runner
/// stale_days: 365
/// fail_on_stale: true
/// ```
class DoctorConfig {
  DoctorConfig({
    this.ignore = const {},
    this.staleDays,
    this.failOnStale,
  });

  final Set<String> ignore;
  final int? staleDays;
  final bool? failOnStale;

  /// This config with [other] layered on top: scalar options from [other]
  /// win, ignore lists are merged. Used for workspace members, whose own
  /// config refines the workspace root config.
  DoctorConfig mergedWith(DoctorConfig other) => DoctorConfig(
        ignore: {...ignore, ...other.ignore},
        staleDays: other.staleDays ?? staleDays,
        failOnStale: other.failOnStale ?? failOnStale,
      );

  static const fileName = 'pubspec_doctor.yaml';

  static DoctorConfig load(Directory root) {
    final configFile = File('${root.path}${Platform.pathSeparator}$fileName');
    if (configFile.existsSync()) {
      return _parse(loadYaml(configFile.readAsStringSync()), fileName);
    }

    final pubspecFile =
        File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    if (pubspecFile.existsSync()) {
      final doc = loadYaml(pubspecFile.readAsStringSync());
      if (doc is YamlMap && doc['pubspec_doctor'] != null) {
        return _parse(doc['pubspec_doctor'], 'pubspec.yaml: pubspec_doctor');
      }
    }

    return DoctorConfig();
  }

  static DoctorConfig _parse(Object? node, String source) {
    if (node is! YamlMap) {
      throw FormatException('$source must be a YAML map');
    }

    const knownKeys = {'ignore', 'stale_days', 'fail_on_stale'};
    for (final key in node.keys) {
      if (!knownKeys.contains(key)) {
        throw FormatException(
            '$source: unknown option "$key" (expected one of: '
            '${knownKeys.join(', ')})');
      }
    }

    final ignoreNode = node['ignore'];
    if (ignoreNode != null && ignoreNode is! YamlList) {
      throw FormatException('$source: "ignore" must be a list');
    }
    final staleDays = node['stale_days'];
    if (staleDays != null && (staleDays is! int || staleDays <= 0)) {
      throw FormatException('$source: "stale_days" must be a positive integer');
    }
    final failOnStale = node['fail_on_stale'];
    if (failOnStale != null && failOnStale is! bool) {
      throw FormatException('$source: "fail_on_stale" must be a boolean');
    }

    return DoctorConfig(
      ignore: ignoreNode == null
          ? const {}
          : (ignoreNode as YamlList).map((e) => e.toString()).toSet(),
      staleDays: staleDays as int?,
      failOnStale: failOnStale as bool?,
    );
  }
}
