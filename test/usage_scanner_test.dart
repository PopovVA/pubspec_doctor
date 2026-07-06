import 'dart:io';

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

  test('finds packages referenced by imports, exports and conditionals', () {
    write('lib/main.dart', '''
import 'package:http/http.dart';
export 'package:collection/collection.dart';
import 'stub.dart' if (dart.library.io) 'package:path/path.dart';
''');

    final used = UsageScanner().scan(root, pubspecRaw: '');
    expect(used.all, containsAll({'http', 'collection', 'path'}));
  });

  test('finds packages referenced in analysis_options.yaml', () {
    write('analysis_options.yaml', 'include: package:lints/recommended.yaml\n');

    final used = UsageScanner().scan(root, pubspecRaw: '');
    expect(used.all, contains('lints'));
  });

  test('finds packages referenced as assets or fonts in pubspec', () {
    const pubspec = '''
flutter:
  assets:
    - packages/icon_pack/icons/add.png
''';
    final used = UsageScanner().scan(root, pubspecRaw: pubspec);
    expect(used.all, contains('icon_pack'));
  });

  test('skips .dart_tool and build directories', () {
    write('.dart_tool/generated.dart', "import 'package:hidden/hidden.dart';");
    write('build/out.dart', "import 'package:also_hidden/a.dart';");
    write('lib/app.dart', "import 'package:visible/visible.dart';");

    final used = UsageScanner().scan(root, pubspecRaw: '');
    expect(used.all, {'visible'});
  });

  test('root-level config file named after a package counts as usage', () {
    write('flutter_native_splash.yaml', 'color: "#ffffff"\n');
    write('lib/main.dart', '');

    final used = UsageScanner().scan(root, pubspecRaw: '');
    expect(used.all, contains('flutter_native_splash'));
    expect(used.public, isNot(contains('flutter_native_splash')));
  });

  test('packages mentioned in build.yaml count as usage', () {
    write('build.yaml', '''
targets:
  \$default:
    builders:
      json_serializable:
        options:
          explicit_to_json: true
      intl_utils|intl_utils:
        enabled: true
''');
    write('lib/main.dart', '');

    final used = UsageScanner().scan(root, pubspecRaw: '');
    expect(used.all, containsAll({'json_serializable', 'intl_utils'}));
  });

  test('dart run in Makefiles, scripts and CI workflows counts as usage', () {
    write('Makefile', 'icons:\n\tdart run flutter_launcher_icons\n');
    write('scripts/gen.sh', 'flutter pub run intl_utils:generate\n');
    write('.github/workflows/ci.yml', '''
jobs:
  build:
    steps:
      - run: dart pub run dart_code_metrics:metrics analyze lib
''');
    write('lib/main.dart', '');

    final used = UsageScanner().scan(root, pubspecRaw: '');
    expect(
      used.all,
      containsAll({
        'flutter_launcher_icons',
        'intl_utils',
        'dart_code_metrics',
      }),
    );
    expect(used.public, isNot(contains('intl_utils')));
  });

  test('splits references into runtime (public) and dev usage', () {
    write('lib/app.dart', "import 'package:lib_pkg/lib_pkg.dart';");
    write('bin/cli.dart', "import 'package:bin_pkg/bin_pkg.dart';");
    write('test/app_test.dart', "import 'package:test_pkg/test_pkg.dart';");
    write('tool/gen.dart', "import 'package:tool_pkg/tool_pkg.dart';");
    write('analysis_options.yaml', 'include: package:lints/core.yaml\n');
    const pubspec = '''
flutter:
  assets:
    - packages/asset_pkg/img.png
''';

    final used = UsageScanner().scan(root, pubspecRaw: pubspec);
    expect(used.public, {'lib_pkg', 'bin_pkg', 'asset_pkg'});
    expect(
      used.all,
      containsAll(
          {'lib_pkg', 'bin_pkg', 'test_pkg', 'tool_pkg', 'lints', 'asset_pkg'}),
    );
  });
}
