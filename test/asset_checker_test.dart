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

  AssetFindings check({
    List<String> assets = const [],
    List<String> fonts = const [],
  }) =>
      AssetChecker().check(root, assetPaths: assets, fontAssets: fonts);

  test('reports declared assets and fonts that do not exist', () {
    write('assets/logo.png', '');
    write('lib/main.dart', "const a = 'assets/logo.png';");

    final findings = check(
      assets: ['assets/logo.png', 'assets/missing.png', 'images/'],
      fonts: ['fonts/Missing.ttf'],
    );

    expect(findings.missing,
        ['assets/missing.png', 'fonts/Missing.ttf', 'images/']);
    expect(findings.unused, isEmpty);
  });

  test('reports asset files never referenced in code', () {
    write('assets/used.png', '');
    write('assets/unused.png', '');
    write('lib/main.dart', "const a = 'assets/used.png';");

    final findings = check(assets: ['assets/']);
    expect(findings.unused, ['assets/unused.png']);
  });

  test('a bare file name reference counts as usage', () {
    write('assets/logo.png', '');
    write('lib/main.dart', "Image.asset(dir + 'logo.png');");

    final findings = check(assets: ['assets/']);
    expect(findings.unused, isEmpty);
  });

  test('interpolated directory paths mark the whole directory used', () {
    write('assets/flags/us.png', '');
    write('assets/flags/de.png', '');
    write('lib/main.dart', r"final p = 'assets/flags/$code.png';");

    final findings = check(assets: ['assets/flags/']);
    expect(findings.unused, isEmpty);
  });

  test('resolution variants resolve to their logical path', () {
    write('assets/logo.png', '');
    write('assets/2.0x/logo.png', '');
    write('lib/main.dart', "const a = 'assets/logo.png';");

    final findings = check(assets: ['assets/', 'assets/2.0x/']);
    expect(findings.unused, isEmpty);
  });

  test('directory declarations are not recursive, like in Flutter', () {
    write('assets/top.png', '');
    write('assets/nested/deep.png', '');
    write('lib/main.dart', '');

    final findings = check(assets: ['assets/']);
    // deep.png is not part of the bundle, so it is not "unused" either.
    expect(findings.unused, ['assets/top.png']);
  });
}
