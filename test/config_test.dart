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

  test('loads pubspec_doctor.yaml', () {
    write('pubspec_doctor.yaml', '''
ignore:
  - build_runner
  - some_pkg
stale_days: 365
fail_on_stale: true
''');

    final config = DoctorConfig.load(root);
    expect(config.ignore, {'build_runner', 'some_pkg'});
    expect(config.staleDays, 365);
    expect(config.failOnStale, isTrue);
  });

  test('falls back to the pubspec_doctor section in pubspec.yaml', () {
    write('pubspec.yaml', '''
name: my_app
pubspec_doctor:
  ignore:
    - some_pkg
''');

    final config = DoctorConfig.load(root);
    expect(config.ignore, {'some_pkg'});
    expect(config.staleDays, isNull);
  });

  test('pubspec_doctor.yaml wins over the pubspec section', () {
    write('pubspec_doctor.yaml', 'stale_days: 100\n');
    write('pubspec.yaml', '''
name: my_app
pubspec_doctor:
  stale_days: 200
''');

    expect(DoctorConfig.load(root).staleDays, 100);
  });

  test('returns defaults when no config exists', () {
    final config = DoctorConfig.load(root);
    expect(config.ignore, isEmpty);
    expect(config.staleDays, isNull);
    expect(config.failOnStale, isNull);
  });

  test('rejects unknown options', () {
    write('pubspec_doctor.yaml', 'staleDays: 100\n');
    expect(() => DoctorConfig.load(root), throwsFormatException);
  });

  test('rejects invalid stale_days', () {
    write('pubspec_doctor.yaml', 'stale_days: -5\n');
    expect(() => DoctorConfig.load(root), throwsFormatException);
  });

  test('mergedWith layers the member config over the root config', () {
    final rootConfig = DoctorConfig(
      ignore: {'a'},
      staleDays: 100,
      failOnStale: true,
    );
    final member = DoctorConfig(ignore: {'b'}, staleDays: 200);

    final merged = rootConfig.mergedWith(member);
    expect(merged.ignore, {'a', 'b'});
    expect(merged.staleDays, 200);
    expect(merged.failOnStale, isTrue);
  });
}
