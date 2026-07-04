import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pubspec_doctor/pubspec_doctor.dart';
import 'package:test/test.dart';

/// Serves canned pub.dev API responses for the packages in [packages];
/// everything else gets a 404.
PubApiClient fakePubApi(Map<String, Map<String, Object?>> packages) {
  return PubApiClient(
    client: MockClient((request) async {
      final name = request.url.pathSegments.last;
      final body = packages[name];
      if (body == null) return http.Response('not found', 404);
      return http.Response(jsonEncode(body), 200);
    }),
  );
}

Map<String, Object?> pubInfo(
  String name, {
  bool discontinued = false,
  String? replacedBy,
  String published = '2026-01-01T00:00:00Z',
  String? sdk,
}) =>
    {
      'name': name,
      if (discontinued) 'isDiscontinued': true,
      if (replacedBy != null) 'replacedBy': replacedBy,
      'latest': {
        'version': '1.0.0',
        'published': published,
        if (sdk != null)
          'pubspec': {
            'environment': {'sdk': sdk},
          },
      },
    };

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

  test('full diagnosis: unused, discontinued, stale and errors', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  used_pkg: ^1.0.0
  unused_pkg: ^1.0.0
  dead_pkg: ^1.0.0
  old_pkg: ^1.0.0
dev_dependencies:
  unused_dev: ^1.0.0
  missing_pkg: ^1.0.0
''');
    write('lib/main.dart', '''
import 'package:used_pkg/used_pkg.dart';
import 'package:dead_pkg/dead_pkg.dart';
import 'package:old_pkg/old_pkg.dart';
import 'package:missing_pkg/missing_pkg.dart';
''');

    final doctor = Doctor(
      apiClient: fakePubApi({
        'used_pkg': pubInfo('used_pkg'),
        'unused_pkg': pubInfo('unused_pkg'),
        'dead_pkg':
            pubInfo('dead_pkg', discontinued: true, replacedBy: 'alive_pkg'),
        'old_pkg': pubInfo('old_pkg', published: '2020-01-01T00:00:00Z'),
        'unused_dev': pubInfo('unused_dev'),
      }),
      now: DateTime.utc(2026, 7, 1),
    );

    final report = await doctor.diagnose(root, DoctorOptions());

    expect(report.packageName, 'my_app');
    expect(report.unusedDependencies, ['unused_pkg']);
    expect(report.unusedDevDependencies, ['unused_dev']);
    expect(report.discontinued.map((p) => p.name), ['dead_pkg']);
    expect(report.discontinued.single.replacedBy, 'alive_pkg');
    expect(report.stale.map((s) => s.health.name), ['old_pkg']);
    expect(report.errors.map((e) => e.package), ['missing_pkg']);
    // missing_pkg is a dev_dependency imported from lib/.
    expect(report.underPromoted, ['missing_pkg']);
    expect(report.hasProblems(failOnStale: false), isTrue);
  });

  test('detects over- and under-promoted dependencies', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  runtime_pkg: ^1.0.0
  test_only_pkg: ^1.0.0
dev_dependencies:
  dev_in_lib_pkg: ^1.0.0
  proper_dev_pkg: ^1.0.0
''');
    write('lib/main.dart', '''
import 'package:runtime_pkg/runtime_pkg.dart';
import 'package:dev_in_lib_pkg/dev_in_lib_pkg.dart';
''');
    write('test/main_test.dart', '''
import 'package:test_only_pkg/test_only_pkg.dart';
import 'package:proper_dev_pkg/proper_dev_pkg.dart';
''');

    final report = await Doctor(apiClient: fakePubApi({}))
        .diagnose(root, DoctorOptions(offline: true));

    expect(report.overPromoted, ['test_only_pkg']);
    expect(report.underPromoted, ['dev_in_lib_pkg']);
    expect(report.unusedDependencies, isEmpty);
    expect(report.hasProblems(failOnStale: false), isTrue);
  });

  test('codegen-only dependencies are over-promoted, not runtime deps',
      () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  freezed_annotation: ^3.0.0
  freezed: ^3.0.0
''');
    write('lib/model.dart',
        "import 'package:freezed_annotation/freezed_annotation.dart';");

    final report = await Doctor(apiClient: fakePubApi({}))
        .diagnose(root, DoctorOptions(offline: true));

    // freezed is used (via its companion) but only at build time.
    expect(report.unusedDependencies, isEmpty);
    expect(report.overPromoted, ['freezed']);
  });

  test('flags latest releases incompatible with the current SDK', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  future_pkg: ^1.0.0
  fine_pkg: ^1.0.0
''');
    write('lib/main.dart', '''
import 'package:future_pkg/future_pkg.dart';
import 'package:fine_pkg/fine_pkg.dart';
''');

    final doctor = Doctor(
      apiClient: fakePubApi({
        'future_pkg': pubInfo('future_pkg', sdk: '>=3.9.0 <4.0.0'),
        'fine_pkg': pubInfo('fine_pkg', sdk: '>=3.0.0 <4.0.0'),
      }),
      now: DateTime.utc(2026, 7, 1),
      sdkVersion: '3.5.0',
    );
    final report = await doctor.diagnose(root, DoctorOptions());

    expect(report.sdkIncompatible.map((s) => s.health.name), ['future_pkg']);
    expect(report.sdkIncompatible.single.currentSdk, '3.5.0');
    // SDK incompatibility is informational: it never fails the build.
    expect(report.hasProblems(failOnStale: true), isFalse);
  });

  test('ignored packages are excluded from all checks', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  unused_pkg: ^1.0.0
''');
    write('lib/main.dart', '');

    final doctor = Doctor(apiClient: fakePubApi({}));
    final report = await doctor.diagnose(
      root,
      DoctorOptions(ignore: {'unused_pkg'}),
    );

    expect(report.unusedDependencies, isEmpty);
    expect(report.errors, isEmpty);
    expect(report.hasProblems(failOnStale: true), isFalse);
  });

  test('offline mode skips the pub.dev health check', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  unused_pkg: ^1.0.0
''');
    write('lib/main.dart', '');

    final report = await Doctor(apiClient: fakePubApi({}))
        .diagnose(root, DoctorOptions(offline: true));

    expect(report.unusedDependencies, ['unused_pkg']);
    expect(report.healthCheckSkipped, isTrue);
    expect(report.discontinued, isEmpty);
    expect(report.errors, isEmpty);
  });

  test('stale packages fail only with failOnStale', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  old_pkg: ^1.0.0
''');
    write('lib/main.dart', "import 'package:old_pkg/old_pkg.dart';");

    final doctor = Doctor(
      apiClient: fakePubApi(
        {'old_pkg': pubInfo('old_pkg', published: '2020-01-01T00:00:00Z')},
      ),
      now: DateTime.utc(2026, 7, 1),
    );
    final report = await doctor.diagnose(root, DoctorOptions());

    expect(report.stale, hasLength(1));
    expect(report.hasProblems(failOnStale: false), isFalse);
    expect(report.hasProblems(failOnStale: true), isTrue);
  });

  test('report renders GitHub annotations', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  unused_pkg: ^1.0.0
  dead_pkg: ^1.0.0
  old_pkg: ^1.0.0
''');
    write('lib/main.dart', '''
import 'package:dead_pkg/dead_pkg.dart';
import 'package:old_pkg/old_pkg.dart';
''');

    final doctor = Doctor(
      apiClient: fakePubApi({
        'unused_pkg': pubInfo('unused_pkg'),
        'dead_pkg':
            pubInfo('dead_pkg', discontinued: true, replacedBy: 'alive_pkg'),
        'old_pkg': pubInfo('old_pkg', published: '2020-01-01T00:00:00Z'),
      }),
      now: DateTime.utc(2026, 7, 1),
    );
    final annotations =
        (await doctor.diagnose(root, DoctorOptions())).toGithubAnnotations();

    expect(annotations, hasLength(3));
    expect(
      annotations[0],
      '::error file=pubspec.yaml,title=Unused dependency::'
      'unused_pkg is declared in dependencies but never used',
    );
    expect(annotations[1], contains('Discontinued package'));
    expect(annotations[1], contains('alive_pkg'));
    expect(annotations[2], startsWith('::warning'));
    expect(annotations[2], contains('old_pkg'));
  });

  test('reports dependency overrides; only path/git ones fail', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  http: ^1.0.0
dependency_overrides:
  pinned_pkg: 1.2.3
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  local_pkg:
    path: ../local_pkg
''');
    write('lib/main.dart', "import 'package:http/http.dart';");

    final report = await Doctor(apiClient: fakePubApi({}))
        .diagnose(root, DoctorOptions(offline: true));

    expect(report.overrides.map((o) => o.name).toSet(),
        {'pinned_pkg', 'local_pkg'});
    expect(report.hasProblems(failOnStale: false), isTrue);

    final annotations = report.toGithubAnnotations();
    expect(
      annotations.where((a) => a.contains('local_pkg')).single,
      startsWith('::error file=pubspec_overrides.yaml'),
    );
    expect(
      annotations.where((a) => a.contains('pinned_pkg')).single,
      startsWith('::warning'),
    );
  });

  test('version-only overrides do not fail the run', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  http: ^1.0.0
dependency_overrides:
  pinned_pkg: 1.2.3
''');
    write('lib/main.dart', "import 'package:http/http.dart';");

    final report = await Doctor(apiClient: fakePubApi({}))
        .diagnose(root, DoctorOptions(offline: true));

    expect(report.overrides.single.name, 'pinned_pkg');
    expect(report.hasProblems(failOnStale: true), isFalse);
  });

  test('report serializes to JSON', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  dead_pkg: ^1.0.0
''');
    write('lib/main.dart', "import 'package:dead_pkg/dead_pkg.dart';");

    final doctor = Doctor(
      apiClient: fakePubApi({
        'dead_pkg': pubInfo('dead_pkg', discontinued: true),
      }),
      now: DateTime.utc(2026, 7, 1),
    );
    final report = await doctor.diagnose(root, DoctorOptions());
    final json = report.toJson();

    expect(json['package'], 'my_app');
    expect(json['unusedDependencies'], isEmpty);
    expect(
      (json['discontinued'] as List).single,
      containsPair('name', 'dead_pkg'),
    );
  });
}
