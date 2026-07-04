import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'codegen_detector.dart';
import 'pub_api_client.dart';
import 'pubspec_info.dart';
import 'report.dart';
import 'usage_scanner.dart';

class DoctorOptions {
  DoctorOptions({
    this.ignore = const {},
    this.staleDays = 730,
    this.offline = false,
    this.localPackages = const {},
    this.excludeScanPaths = const {},
  });

  /// Packages excluded from every check.
  final Set<String> ignore;

  /// A package is stale when its latest release is older than this.
  final int staleDays;

  /// Skip the pub.dev health check entirely.
  final bool offline;

  /// Packages that resolve locally (workspace members) — skipped by the
  /// pub.dev health check.
  final Set<String> localPackages;

  /// Directories excluded from the usage scan (workspace member roots
  /// when diagnosing the workspace root).
  final Set<String> excludeScanPaths;

  DoctorOptions copyWith({
    Set<String>? localPackages,
    Set<String>? excludeScanPaths,
  }) =>
      DoctorOptions(
        ignore: ignore,
        staleDays: staleDays,
        offline: offline,
        localPackages: localPackages ?? this.localPackages,
        excludeScanPaths: excludeScanPaths ?? this.excludeScanPaths,
      );
}

/// Orchestrates the checks: parses the pubspec, scans the project for
/// package references, and queries pub.dev for the health of each hosted
/// dependency.
class Doctor {
  Doctor({
    UsageScanner? scanner,
    PubApiClient? apiClient,
    DateTime? now,
    String? sdkVersion,
  })  : _scanner = scanner ?? UsageScanner(),
        _apiClient = apiClient,
        _now = now,
        _sdkVersion = sdkVersion;

  final UsageScanner _scanner;
  final PubApiClient? _apiClient;
  final DateTime? _now;
  final String? _sdkVersion;

  static const _concurrentRequests = 8;

  Future<Report> diagnose(Directory root, DoctorOptions options) async {
    final pubspec = PubspecInfo.load(root);
    final usage = _scanner.scan(
      root,
      pubspecRaw: pubspec.raw,
      excludePaths: options.excludeScanPaths,
    );
    final used = {...usage.all, pubspec.name};
    used.addAll(CodegenDetector().implicitlyUsed(
      declared: {...pubspec.dependencies, ...pubspec.devDependencies},
      referenced: used,
      pubspecRaw: pubspec.raw,
    ));

    List<String> unusedIn(Set<String> declared) => declared
        .where((d) => !used.contains(d) && !options.ignore.contains(d))
        .toList()
      ..sort();

    final overPromoted = pubspec.dependencies
        .where((d) =>
            used.contains(d) &&
            !usage.public.contains(d) &&
            !options.ignore.contains(d))
        .toList()
      ..sort();
    final underPromoted = pubspec.devDependencies
        .where((d) => usage.public.contains(d) && !options.ignore.contains(d))
        .toList()
      ..sort();

    final checked = {...pubspec.dependencies, ...pubspec.devDependencies}
        .difference(options.ignore);

    final discontinued = <PackageHealth>[];
    final stale = <StalePackage>[];
    final sdkIncompatible = <SdkIncompatiblePackage>[];
    final outdatedConstraints = <OutdatedConstraint>[];
    final errors = <HealthCheckError>[];

    if (!options.offline) {
      final targets = pubspec.hostedDependencies
          .difference(options.ignore)
          .difference(options.localPackages)
          .toList()
        ..sort();
      final now = _now ?? DateTime.now();
      final currentSdk =
          Version.parse((_sdkVersion ?? Platform.version).split(' ').first);
      final client = _apiClient ?? PubApiClient();
      try {
        for (var i = 0; i < targets.length; i += _concurrentRequests) {
          final batch = targets.skip(i).take(_concurrentRequests);
          await Future.wait(batch.map((package) async {
            try {
              final health = await client.fetch(package);
              if (health.isDiscontinued) discontinued.add(health);
              final age = now.difference(health.publishedAt).inDays;
              if (!health.isDiscontinued && age > options.staleDays) {
                stale.add(StalePackage(health: health, ageDays: age));
              }
              if (!health.isDiscontinued &&
                  !_allowsSdk(health.sdkConstraint, currentSdk)) {
                sdkIncompatible.add(SdkIncompatiblePackage(
                  health: health,
                  currentSdk: currentSdk.toString(),
                ));
              }
              final constraint = pubspec.versionConstraints[package];
              if (!health.isDiscontinued &&
                  constraint != null &&
                  !_constraintAllowsLatest(constraint, health.latestVersion)) {
                outdatedConstraints.add(OutdatedConstraint(
                  health: health,
                  constraint: constraint,
                ));
              }
            } on PubApiException catch (e) {
              errors.add(
                HealthCheckError(package: e.package, message: e.message),
              );
            } catch (e) {
              errors.add(
                HealthCheckError(package: package, message: e.toString()),
              );
            }
          }));
        }
      } finally {
        if (_apiClient == null) client.close();
      }
      discontinued.sort((a, b) => a.name.compareTo(b.name));
      stale.sort((a, b) => a.health.name.compareTo(b.health.name));
      sdkIncompatible.sort((a, b) => a.health.name.compareTo(b.health.name));
      outdatedConstraints
          .sort((a, b) => a.health.name.compareTo(b.health.name));
      errors.sort((a, b) => a.package.compareTo(b.package));
    }

    return Report(
      packageName: pubspec.name,
      unusedDependencies: unusedIn(pubspec.dependencies),
      unusedDevDependencies: unusedIn(pubspec.devDependencies),
      overPromoted: overPromoted,
      underPromoted: underPromoted,
      overrides: pubspec.overrides
          .where((o) => !options.ignore.contains(o.name))
          .toList(),
      discontinued: discontinued,
      stale: stale,
      sdkIncompatible: sdkIncompatible,
      outdatedConstraints: outdatedConstraints,
      errors: errors,
      checkedCount: checked.length,
      healthCheckSkipped: options.offline,
    );
  }

  /// True when [constraint] admits [sdk]. Missing or unparseable
  /// constraints count as compatible — err on the quiet side.
  bool _allowsSdk(String? constraint, Version sdk) {
    if (constraint == null) return true;
    try {
      return VersionConstraint.parse(constraint).allows(sdk);
    } on FormatException {
      return true;
    }
  }

  /// True when the declared [constraint] admits [latestVersion].
  /// Unparseable input counts as allowed — err on the quiet side.
  bool _constraintAllowsLatest(String constraint, String latestVersion) {
    try {
      return VersionConstraint.parse(constraint)
          .allows(Version.parse(latestVersion));
    } on FormatException {
      return true;
    }
  }
}
