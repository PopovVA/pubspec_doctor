import 'dart:io';

import 'doctor.dart';
import 'pubspec_info.dart';
import 'report.dart';

/// One diagnosed package inside a run: `path` is relative to the
/// invocation root (`.` for the root itself).
class PackageReport {
  PackageReport({required this.path, required this.report});

  final String path;
  final Report report;

  /// The pubspec location for GitHub annotations.
  String get pubspecFile => path == '.' ? 'pubspec.yaml' : '$path/pubspec.yaml';
}

/// Runs the doctor over a single package, or over every member of a pub
/// workspace when the root pubspec has a `workspace:` section.
class WorkspaceDoctor {
  WorkspaceDoctor({Doctor? doctor}) : _doctor = doctor ?? Doctor();

  final Doctor _doctor;

  /// [optionsFor] builds the options for each package directory, so the
  /// caller can apply per-package config files.
  Future<List<PackageReport>> diagnose(
    Directory root,
    DoctorOptions Function(Directory packageDir) optionsFor,
  ) async {
    final rootInfo = PubspecInfo.load(root);
    if (rootInfo.workspacePaths.isEmpty) {
      return [
        PackageReport(
          path: '.',
          report: await _doctor.diagnose(root, optionsFor(root)),
        ),
      ];
    }

    final members = {
      for (final path in rootInfo.workspacePaths)
        path: Directory('${root.path}${Platform.pathSeparator}$path'),
    };

    // Workspace members resolve locally: exclude them from the pub.dev
    // health check by name.
    final localNames = {
      rootInfo.name,
      for (final dir in members.values) PubspecInfo.load(dir).name,
    };

    return [
      PackageReport(
        path: '.',
        report: await _doctor.diagnose(
          root,
          optionsFor(root).copyWith(
            localPackages: localNames,
            // Member code must not count as usage for the root package.
            excludeScanPaths: members.values.map((d) => d.path).toSet(),
          ),
        ),
      ),
      for (final entry in members.entries)
        PackageReport(
          path: entry.key,
          report: await _doctor.diagnose(
            entry.value,
            optionsFor(entry.value).copyWith(localPackages: localNames),
          ),
        ),
    ];
  }
}
