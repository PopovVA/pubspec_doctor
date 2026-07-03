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
