import 'dart:io';

import 'package:pubspec_doctor/pubspec_doctor.dart';

/// Programmatic usage. Most people want the CLI instead:
///
/// ```sh
/// dart pub global activate pubspec_doctor
/// pubspec_doctor --fail-on-stale
/// ```
Future<void> main() async {
  final report = await Doctor().diagnose(
    Directory.current,
    DoctorOptions(staleDays: 365),
  );

  print(report.toConsole());

  if (report.hasProblems(failOnStale: false)) {
    exitCode = 1;
  }
}
