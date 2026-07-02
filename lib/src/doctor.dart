import 'dart:io';

import 'pub_api_client.dart';
import 'pubspec_info.dart';
import 'report.dart';
import 'usage_scanner.dart';

class DoctorOptions {
  DoctorOptions({
    this.ignore = const {},
    this.staleDays = 730,
    this.offline = false,
  });

  /// Packages excluded from every check.
  final Set<String> ignore;

  /// A package is stale when its latest release is older than this.
  final int staleDays;

  /// Skip the pub.dev health check entirely.
  final bool offline;
}

/// Orchestrates the checks: parses the pubspec, scans the project for
/// package references, and queries pub.dev for the health of each hosted
/// dependency.
class Doctor {
  Doctor({UsageScanner? scanner, PubApiClient? apiClient, DateTime? now})
      : _scanner = scanner ?? UsageScanner(),
        _apiClient = apiClient,
        _now = now;

  final UsageScanner _scanner;
  final PubApiClient? _apiClient;
  final DateTime? _now;

  static const _concurrentRequests = 8;

  Future<Report> diagnose(Directory root, DoctorOptions options) async {
    final pubspec = PubspecInfo.load(root);
    final used = _scanner.scan(root, pubspecRaw: pubspec.raw)
      ..add(pubspec.name);

    List<String> unusedIn(Set<String> declared) => declared
        .where((d) => !used.contains(d) && !options.ignore.contains(d))
        .toList()
      ..sort();

    final checked = {...pubspec.dependencies, ...pubspec.devDependencies}
        .difference(options.ignore);

    final discontinued = <PackageHealth>[];
    final stale = <StalePackage>[];
    final errors = <HealthCheckError>[];

    if (!options.offline) {
      final targets = pubspec.hostedDependencies
          .difference(options.ignore)
          .toList()
        ..sort();
      final now = _now ?? DateTime.now();
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
      errors.sort((a, b) => a.package.compareTo(b.package));
    }

    return Report(
      packageName: pubspec.name,
      unusedDependencies: unusedIn(pubspec.dependencies),
      unusedDevDependencies: unusedIn(pubspec.devDependencies),
      discontinued: discontinued,
      stale: stale,
      errors: errors,
      checkedCount: checked.length,
      healthCheckSkipped: options.offline,
    );
  }
}
