import 'pub_api_client.dart';

/// A package whose latest release is older than the configured threshold.
class StalePackage {
  StalePackage({required this.health, required this.ageDays});

  final PackageHealth health;
  final int ageDays;
}

class HealthCheckError {
  HealthCheckError({required this.package, required this.message});

  final String package;
  final String message;
}

/// The full diagnosis for one project.
class Report {
  Report({
    required this.packageName,
    required this.unusedDependencies,
    required this.unusedDevDependencies,
    required this.discontinued,
    required this.stale,
    required this.errors,
    required this.checkedCount,
    required this.healthCheckSkipped,
  });

  final String packageName;
  final List<String> unusedDependencies;
  final List<String> unusedDevDependencies;
  final List<PackageHealth> discontinued;
  final List<StalePackage> stale;
  final List<HealthCheckError> errors;

  /// Number of dependencies inspected (both sections, SDK deps excluded).
  final int checkedCount;

  /// True when the pub.dev health check was skipped (`--offline`).
  final bool healthCheckSkipped;

  bool get hasUnused =>
      unusedDependencies.isNotEmpty || unusedDevDependencies.isNotEmpty;

  bool hasProblems({required bool failOnStale}) =>
      hasUnused || discontinued.isNotEmpty || (failOnStale && stale.isNotEmpty);

  Map<String, Object?> toJson() => {
        'package': packageName,
        'checkedDependencies': checkedCount,
        'unusedDependencies': unusedDependencies,
        'unusedDevDependencies': unusedDevDependencies,
        'discontinued': discontinued.map((p) => p.toJson()).toList(),
        'stale': stale
            .map((s) => {...s.health.toJson(), 'ageDays': s.ageDays})
            .toList(),
        'errors': errors
            .map((e) => {'package': e.package, 'message': e.message})
            .toList(),
        'healthCheckSkipped': healthCheckSkipped,
      };

  String toConsole() {
    final out = StringBuffer()
      ..writeln('pubspec_doctor — diagnosis for "$packageName" '
          '($checkedCount dependencies checked)')
      ..writeln();

    void section(String title, Iterable<String> lines) {
      out.writeln(title);
      for (final line in lines) {
        out.writeln('  - $line');
      }
      out.writeln();
    }

    if (unusedDependencies.isNotEmpty) {
      section('Unused dependencies:', unusedDependencies);
    }
    if (unusedDevDependencies.isNotEmpty) {
      section('Unused dev_dependencies:', unusedDevDependencies);
    }
    if (discontinued.isNotEmpty) {
      section(
        'Discontinued packages:',
        discontinued.map((p) => p.replacedBy == null
            ? p.name
            : '${p.name} (replaced by: ${p.replacedBy})'),
      );
    }
    if (stale.isNotEmpty) {
      section(
        'Stale packages (no release in a long time):',
        stale.map((s) => '${s.health.name} '
            '(latest ${s.health.latestVersion} published ${s.ageDays} days ago)'),
      );
    }
    if (errors.isNotEmpty) {
      section(
        'Health check errors:',
        errors.map((e) => '${e.package}: ${e.message}'),
      );
    }

    if (healthCheckSkipped) {
      out.writeln('Note: pub.dev health check skipped (--offline).');
    }
    if (!hasUnused && discontinued.isEmpty && stale.isEmpty && errors.isEmpty) {
      out.writeln('No problems found. Your pubspec looks healthy!');
    }

    return out.toString().trimRight();
  }
}
