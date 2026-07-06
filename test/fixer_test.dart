import 'dart:io';

import 'package:pubspec_doctor/pubspec_doctor.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pubspec_doctor_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void write(String relativePath, String content) {
    File('${root.path}/$relativePath')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  String pubspec() => File('${root.path}/pubspec.yaml').readAsStringSync();

  Future<Report> diagnose() =>
      Doctor().diagnose(root, DoctorOptions(offline: true));

  test('removes unused dependencies and keeps comments', () async {
    write('pubspec.yaml', '''
name: my_app
# keep this comment
dependencies:
  used_pkg: ^1.0.0 # inline note
  unused_pkg: ^1.0.0
dev_dependencies:
  unused_dev: ^2.0.0
''');
    write('lib/main.dart', "import 'package:used_pkg/used_pkg.dart';");

    final applied = Fixer().apply(root, await diagnose());

    expect(applied, hasLength(2));
    final result = pubspec();
    expect(result, contains('# keep this comment'));
    expect(result, contains('used_pkg: ^1.0.0 # inline note'));
    expect(result, isNot(contains('unused_pkg')));
    expect(result, isNot(contains('unused_dev')));

    final after = await diagnose();
    expect(after.hasProblems(failOnStale: true), isFalse);
  });

  test('moves wrongly promoted dependencies between sections', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  runtime_pkg: ^1.0.0
  test_only_pkg: ^2.0.0
dev_dependencies:
  dev_in_lib_pkg: ^3.0.0
''');
    write('lib/main.dart', '''
import 'package:runtime_pkg/runtime_pkg.dart';
import 'package:dev_in_lib_pkg/dev_in_lib_pkg.dart';
''');
    write('test/a_test.dart',
        "import 'package:test_only_pkg/test_only_pkg.dart';");

    Fixer().apply(root, await diagnose());

    final info = PubspecInfo.load(root);
    expect(info.dependencies, {'runtime_pkg', 'dev_in_lib_pkg'});
    expect(info.devDependencies, {'test_only_pkg'});
    // Constraints travel with the move.
    expect(info.versionConstraints['test_only_pkg'], '^2.0.0');
    expect(info.versionConstraints['dev_in_lib_pkg'], '^3.0.0');

    final after = await diagnose();
    expect(after.hasProblems(failOnStale: true), isFalse);
  });

  test('creates the target section when it does not exist', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  test_only_pkg: ^2.0.0
''');
    write('test/a_test.dart',
        "import 'package:test_only_pkg/test_only_pkg.dart';");

    Fixer().apply(root, await diagnose());

    final info = PubspecInfo.load(root);
    expect(info.dependencies, isEmpty);
    expect(info.devDependencies, {'test_only_pkg'});
  });

  test('removes path/git overrides but keeps version pins', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  http: ^1.0.0
dependency_overrides:
  local_pkg:
    path: ../local_pkg
  pinned_pkg: 1.2.3
''');
    write('lib/main.dart', "import 'package:http/http.dart';");

    Fixer().apply(root, await diagnose());

    final result = pubspec();
    expect(result, isNot(contains('local_pkg')));
    expect(result, contains('pinned_pkg: 1.2.3'));
  });

  test(
      'drops an emptied overrides section and deletes an emptied '
      'pubspec_overrides.yaml', () async {
    write('pubspec.yaml', '''
name: my_app
dependency_overrides:
  local_pkg:
    path: ../local_pkg
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  git_pkg:
    git: https://example.com/git_pkg.git
''');
    write('lib/main.dart', '');

    Fixer().apply(root, await diagnose());

    expect(pubspec(), isNot(contains('dependency_overrides')));
    expect(File('${root.path}/pubspec_overrides.yaml').existsSync(), isFalse);
  });

  test('removes missing asset declarations but not missing fonts', () async {
    write('pubspec.yaml', '''
name: my_app
flutter:
  uses-material-design: true
  assets:
    - assets/present.png
    - assets/gone.png
    - path: assets/also_gone/
  fonts:
    - family: Missing
      fonts:
        - asset: fonts/Missing.ttf
''');
    write('assets/present.png', '');
    write('lib/main.dart', "const a = 'assets/present.png';");

    Fixer().apply(root, await diagnose());

    final result = pubspec();
    expect(result, contains('assets/present.png'));
    expect(result, isNot(contains('assets/gone.png')));
    expect(result, isNot(contains('assets/also_gone/')));
    // Fonts and unrelated flutter keys stay untouched.
    expect(result, contains('fonts/Missing.ttf'));
    expect(result, contains('uses-material-design: true'));
  });

  test('drops an emptied assets list', () async {
    write('pubspec.yaml', '''
name: my_app
flutter:
  assets:
    - assets/gone.png
''');
    write('lib/main.dart', '');

    Fixer().apply(root, await diagnose());

    final result = pubspec();
    expect(result, isNot(contains('assets:')));
    expect(result, isNot(contains('flutter:')));
  });

  test('deleteUnusedAssets deletes git-tracked files, skips untracked',
      () async {
    write('pubspec.yaml', '''
name: my_app
flutter:
  assets:
    - assets/
''');
    write('assets/tracked.png', 'x');
    write('assets/untracked.png', 'x');
    write('lib/main.dart', '');
    Process.runSync('git', ['-C', root.path, 'init', '-q']);
    Process.runSync(
        'git', ['-C', root.path, 'add', 'assets/tracked.png', 'pubspec.yaml']);

    final report = await diagnose();
    expect(report.unusedAssets,
        containsAll({'assets/tracked.png', 'assets/untracked.png'}));

    final applied = Fixer().deleteUnusedAssets(root, report);

    expect(File('${root.path}/assets/tracked.png').existsSync(), isFalse);
    expect(File('${root.path}/assets/untracked.png').existsSync(), isTrue);
    expect(applied.join('\n'), contains('deleted unused asset'));
    expect(applied.join('\n'), contains('delete it manually'));
  });

  test('bumps outdated constraints only with outdated: true', () async {
    write('pubspec.yaml', '''
name: my_app
dependencies:
  old_major_pkg: ^0.13.0
''');
    write(
        'lib/main.dart', "import 'package:old_major_pkg/old_major_pkg.dart';");

    final report = Report(
      packageName: 'my_app',
      unusedDependencies: const [],
      unusedDevDependencies: const [],
      overPromoted: const [],
      underPromoted: const [],
      overrides: const [],
      discontinued: const [],
      stale: const [],
      sdkIncompatible: const [],
      outdatedConstraints: [
        OutdatedConstraint(
          health: PackageHealth(
            name: 'old_major_pkg',
            isDiscontinued: false,
            latestVersion: '1.6.0',
            publishedAt: DateTime.utc(2026),
          ),
          constraint: '^0.13.0',
        ),
      ],
      errors: const [],
      checkedCount: 1,
      healthCheckSkipped: false,
    );

    Fixer().apply(root, report);
    expect(pubspec(), contains('old_major_pkg: ^0.13.0'));

    Fixer().apply(root, report, outdated: true);
    expect(pubspec(), contains('old_major_pkg: ^1.6.0'));
  });
}
