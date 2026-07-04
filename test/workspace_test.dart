import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pubspec_doctor/pubspec_doctor.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pubspec_doctor_test');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void write(String relativePath, String content) {
    File('${root.path}/$relativePath')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  DoctorOptions offlineOptions(Directory _) => DoctorOptions(offline: true);

  test('a regular package produces a single report', () async {
    write('pubspec.yaml', 'name: solo\n');

    final results = await WorkspaceDoctor().diagnose(root, offlineOptions);

    expect(results, hasLength(1));
    expect(results.single.path, '.');
    expect(results.single.report.packageName, 'solo');
    expect(results.single.pubspecFile, 'pubspec.yaml');
  });

  test('diagnoses every member of a workspace', () async {
    write('pubspec.yaml', '''
name: my_workspace
workspace:
  - packages/app
  - packages/core
''');
    write('packages/app/pubspec.yaml', '''
name: app
resolution: workspace
dependencies:
  core: ^1.0.0
  unused_in_app: ^1.0.0
''');
    write('packages/app/lib/app.dart', "import 'package:core/core.dart';");
    write('packages/core/pubspec.yaml', '''
name: core
resolution: workspace
''');
    write('packages/core/lib/core.dart', '');

    final results = await WorkspaceDoctor().diagnose(root, offlineOptions);

    expect(results.map((r) => r.path), ['.', 'packages/app', 'packages/core']);
    final app = results[1].report;
    expect(app.unusedDependencies, ['unused_in_app']);
    expect(results[1].pubspecFile, 'packages/app/pubspec.yaml');
  });

  test('member code does not count as usage for the workspace root', () async {
    write('pubspec.yaml', '''
name: my_workspace
workspace:
  - packages/app
dev_dependencies:
  root_dev_pkg: ^1.0.0
''');
    write('packages/app/pubspec.yaml', 'name: app\nresolution: workspace\n');
    // The member imports the package the ROOT declares — the root itself
    // never uses it, so for the root it is unused.
    write('packages/app/lib/app.dart',
        "import 'package:root_dev_pkg/root_dev_pkg.dart';");

    final results = await WorkspaceDoctor().diagnose(root, offlineOptions);

    expect(results.first.report.unusedDevDependencies, ['root_dev_pkg']);
  });

  test('workspace members are excluded from the pub.dev health check',
      () async {
    write('pubspec.yaml', '''
name: my_workspace
workspace:
  - packages/app
  - packages/core
''');
    write('packages/app/pubspec.yaml', '''
name: app
resolution: workspace
dependencies:
  core: ^1.0.0
''');
    write('packages/app/lib/app.dart', "import 'package:core/core.dart';");
    write('packages/core/pubspec.yaml', 'name: core\nresolution: workspace\n');
    write('packages/core/lib/core.dart', '');

    // Online mode with an API that knows no packages: fetching `core`
    // would produce a "not found" error if it were not excluded.
    final doctor = Doctor(
      apiClient: PubApiClient(client: _notFoundClient()),
      sdkVersion: '3.9.0',
    );
    final results = await WorkspaceDoctor(doctor: doctor)
        .diagnose(root, (_) => DoctorOptions());

    for (final result in results) {
      expect(result.report.errors, isEmpty,
          reason: 'no pub.dev lookups expected for ${result.path}');
    }
  });
}

http.Client _notFoundClient() =>
    MockClient((_) async => http.Response('not found', 404));
