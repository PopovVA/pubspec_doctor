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

/// A package whose latest release cannot be used with the current Dart SDK.
class SdkIncompatiblePackage {
  SdkIncompatiblePackage({required this.health, required this.currentSdk});

  final PackageHealth health;
  final String currentSdk;
}

/// The full diagnosis for one project.
class Report {
  Report({
    required this.packageName,
    required this.unusedDependencies,
    required this.unusedDevDependencies,
    required this.overPromoted,
    required this.underPromoted,
    required this.discontinued,
    required this.stale,
    required this.sdkIncompatible,
    required this.errors,
    required this.checkedCount,
    required this.healthCheckSkipped,
  });

  final String packageName;
  final List<String> unusedDependencies;
  final List<String> unusedDevDependencies;

  /// In `dependencies` but only used outside runtime code — should be a
  /// dev_dependency.
  final List<String> overPromoted;

  /// In `dev_dependencies` but used in runtime code (`lib/`, `bin/`,
  /// `web/`) — should be a regular dependency.
  final List<String> underPromoted;

  final List<PackageHealth> discontinued;
  final List<StalePackage> stale;

  /// Latest releases that do not support the current Dart SDK, i.e.
  /// upgrades are blocked until the SDK is updated.
  final List<SdkIncompatiblePackage> sdkIncompatible;

  final List<HealthCheckError> errors;

  /// Number of dependencies inspected (both sections, SDK deps excluded).
  final int checkedCount;

  /// True when the pub.dev health check was skipped (`--offline`).
  final bool healthCheckSkipped;

  bool get hasUnused =>
      unusedDependencies.isNotEmpty || unusedDevDependencies.isNotEmpty;

  bool get hasPromotionIssues =>
      overPromoted.isNotEmpty || underPromoted.isNotEmpty;

  bool hasProblems({required bool failOnStale}) =>
      hasUnused ||
      hasPromotionIssues ||
      discontinued.isNotEmpty ||
      (failOnStale && stale.isNotEmpty);

  Map<String, Object?> toJson() => {
        'package': packageName,
        'checkedDependencies': checkedCount,
        'unusedDependencies': unusedDependencies,
        'unusedDevDependencies': unusedDevDependencies,
        'overPromoted': overPromoted,
        'underPromoted': underPromoted,
        'discontinued': discontinued.map((p) => p.toJson()).toList(),
        'stale': stale
            .map((s) => {...s.health.toJson(), 'ageDays': s.ageDays})
            .toList(),
        'sdkIncompatible': sdkIncompatible
            .map((s) => {...s.health.toJson(), 'currentSdk': s.currentSdk})
            .toList(),
        'errors': errors
            .map((e) => {'package': e.package, 'message': e.message})
            .toList(),
        'healthCheckSkipped': healthCheckSkipped,
      };

  /// GitHub Actions workflow commands (`::error::` / `::warning::`) that
  /// surface findings as annotations on `pubspec.yaml` in the PR UI.
  List<String> toGithubAnnotations() {
    String esc(String message) => message
        .replaceAll('%', '%25')
        .replaceAll('\r', '%0D')
        .replaceAll('\n', '%0A');

    return [
      for (final name in unusedDependencies)
        '::error file=pubspec.yaml,title=Unused dependency::'
            '${esc('$name is declared in dependencies but never used')}',
      for (final name in unusedDevDependencies)
        '::error file=pubspec.yaml,title=Unused dev_dependency::'
            '${esc('$name is declared in dev_dependencies but never used')}',
      for (final name in overPromoted)
        '::error file=pubspec.yaml,title=Over-promoted dependency::'
            '${esc('$name is only used outside runtime code — move it to dev_dependencies')}',
      for (final name in underPromoted)
        '::error file=pubspec.yaml,title=Under-promoted dependency::'
            '${esc('$name is used in runtime code — move it from dev_dependencies to dependencies')}',
      for (final package in discontinued)
        '::error file=pubspec.yaml,title=Discontinued package::'
            '${esc('${package.name} is discontinued on pub.dev'
                '${package.replacedBy == null ? '' : ', suggested replacement: ${package.replacedBy}'}')}',
      for (final entry in stale)
        '::warning file=pubspec.yaml,title=Stale package::'
            '${esc('${entry.health.name} has had no release for ${entry.ageDays} days '
                '(latest ${entry.health.latestVersion})')}',
      for (final entry in sdkIncompatible)
        '::warning file=pubspec.yaml,title=SDK-incompatible latest release::'
            '${esc('${entry.health.name} ${entry.health.latestVersion} requires Dart '
                '"${entry.health.sdkConstraint}" but the current SDK is ${entry.currentSdk} — upgrades are blocked')}',
    ];
  }

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
    if (overPromoted.isNotEmpty) {
      section(
        'Over-promoted (only used outside runtime code — '
        'move to dev_dependencies):',
        overPromoted,
      );
    }
    if (underPromoted.isNotEmpty) {
      section(
        'Under-promoted (used in runtime code — move to dependencies):',
        underPromoted,
      );
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
    if (sdkIncompatible.isNotEmpty) {
      section(
        'Latest releases incompatible with the current Dart SDK '
        '(upgrades blocked):',
        sdkIncompatible.map((s) => '${s.health.name} '
            '(latest ${s.health.latestVersion} requires '
            '"${s.health.sdkConstraint}", current SDK is ${s.currentSdk})'),
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
    if (!hasUnused &&
        !hasPromotionIssues &&
        discontinued.isEmpty &&
        stale.isEmpty &&
        sdkIncompatible.isEmpty &&
        errors.isEmpty) {
      out.writeln('No problems found. Your pubspec looks healthy!');
    }

    return out.toString().trimRight();
  }
}
