import 'package:pubspec_doctor/pubspec_doctor.dart';
import 'package:test/test.dart';

void main() {
  final detector = CodegenDetector();

  test('generator counts as used when its companion is referenced', () {
    final used = detector.implicitlyUsed(
      declared: {'freezed', 'freezed_annotation', 'json_serializable'},
      referenced: {'freezed_annotation'},
      pubspecRaw: '',
    );
    expect(used, contains('freezed'));
    expect(used, isNot(contains('json_serializable')));
  });

  test('build_runner counts as used when a known generator is declared', () {
    final used = detector.implicitlyUsed(
      declared: {'build_runner', 'freezed'},
      referenced: {},
      pubspecRaw: '',
    );
    expect(used, contains('build_runner'));
  });

  test('build_runner counts as used for generator-looking names', () {
    final used = detector.implicitlyUsed(
      declared: {'build_runner', 'my_custom_generator'},
      referenced: {},
      pubspecRaw: '',
    );
    expect(used, contains('build_runner'));
  });

  test('build_runner stays unused without generators', () {
    final used = detector.implicitlyUsed(
      declared: {'build_runner', 'http'},
      referenced: {'http'},
      pubspecRaw: '',
    );
    expect(used, isNot(contains('build_runner')));
  });

  test('tools configured via a top-level pubspec key count as used', () {
    const pubspec = '''
name: my_app
dev_dependencies:
  flutter_launcher_icons: ^0.14.0
flutter_launcher_icons:
  android: true
''';
    final used = detector.implicitlyUsed(
      declared: {'flutter_launcher_icons'},
      referenced: {},
      pubspecRaw: pubspec,
    );
    expect(used, contains('flutter_launcher_icons'));
  });

  test('the dependency entry itself is not a top-level key', () {
    const pubspec = '''
name: my_app
dev_dependencies:
  flutter_launcher_icons: ^0.14.0
''';
    final used = detector.implicitlyUsed(
      declared: {'flutter_launcher_icons'},
      referenced: {},
      pubspecRaw: pubspec,
    );
    expect(used, isEmpty);
  });
}
