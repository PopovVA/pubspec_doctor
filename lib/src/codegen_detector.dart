/// Detects packages that are used through code generation or tool
/// configuration rather than through imports, so they are not falsely
/// reported as unused.
class CodegenDetector {
  /// Generator package → companion packages that appear in source code.
  /// The generator counts as used when one of its companions is referenced.
  static const Map<String, List<String>> _companions = {
    'auto_route_generator': ['auto_route'],
    'built_value_generator': ['built_value'],
    'chopper_generator': ['chopper'],
    'copy_with_extension_gen': ['copy_with_extension'],
    'drift_dev': ['drift'],
    'envied_generator': ['envied'],
    'floor_generator': ['floor'],
    'freezed': ['freezed_annotation'],
    'go_router_builder': ['go_router'],
    'hive_generator': ['hive', 'hive_flutter'],
    'injectable_generator': ['injectable'],
    'isar_generator': ['isar'],
    'json_serializable': ['json_annotation'],
    'mobx_codegen': ['mobx', 'flutter_mobx'],
    'objectbox_generator': ['objectbox'],
    'retrofit_generator': ['retrofit'],
    'riverpod_generator': [
      'riverpod_annotation',
      'flutter_riverpod',
      'hooks_riverpod',
    ],
  };

  /// Suffixes that mark a package as a build_runner-based generator even
  /// when it is not in the known-companions map.
  static final _generatorName = RegExp(r'(_generator|_gen|_codegen|_builder)$');

  /// Packages from [declared] that are in use even though nothing imports
  /// them:
  ///
  /// - generators whose companion package is referenced in the code
  ///   (e.g. `freezed` is used when `freezed_annotation` is imported);
  /// - `build_runner` when any declared package looks like a generator;
  /// - tools configured via a top-level key in `pubspec.yaml`
  ///   (e.g. `flutter_launcher_icons:`, `flutter_native_splash:`).
  Set<String> implicitlyUsed({
    required Set<String> declared,
    required Set<String> referenced,
    required String pubspecRaw,
  }) {
    final used = <String>{};

    for (final entry in _companions.entries) {
      if (declared.contains(entry.key) &&
          entry.value.any(referenced.contains)) {
        used.add(entry.key);
      }
    }

    if (declared.contains('build_runner') &&
        declared.any((dep) =>
            _companions.containsKey(dep) ||
            dep == 'source_gen' ||
            _generatorName.hasMatch(dep))) {
      used.add('build_runner');
    }

    for (final dep in declared) {
      final topLevelKey = RegExp('^${RegExp.escape(dep)}:', multiLine: true);
      if (topLevelKey.hasMatch(pubspecRaw)) used.add(dep);
    }

    return used;
  }
}
