import 'package:pubspec_doctor/pubspec_doctor.dart';
import 'package:test/test.dart';

void main() {
  group('PubspecInfo.parse', () {
    test('splits dependencies by section and source', () {
      final info = PubspecInfo.parse('''
name: my_app
environment:
  sdk: ^3.0.0
dependencies:
  flutter:
    sdk: flutter
  http: ^1.0.0
  local_pkg:
    path: ../local_pkg
  git_pkg:
    git: https://example.com/git_pkg.git
  pinned:
    hosted: https://private.example.com
    version: ^2.0.0
dev_dependencies:
  test: ^1.24.0
''');

      expect(info.name, 'my_app');
      expect(
        info.dependencies,
        {'http', 'local_pkg', 'git_pkg', 'pinned'},
      );
      expect(info.devDependencies, {'test'});
      expect(info.sdkDependencies, {'flutter'});
      expect(info.hostedDependencies, {'http', 'pinned', 'test'});
    });

    test('handles missing dependency sections', () {
      final info = PubspecInfo.parse('name: bare\n');
      expect(info.dependencies, isEmpty);
      expect(info.devDependencies, isEmpty);
    });

    test('throws on a pubspec without a name', () {
      expect(
        () => PubspecInfo.parse('dependencies:\n  http: ^1.0.0\n'),
        throwsFormatException,
      );
    });

    test('parses workspace member paths', () {
      final info = PubspecInfo.parse('''
name: my_workspace
workspace:
  - packages/app
  - packages/core
''');
      expect(info.workspacePaths, ['packages/app', 'packages/core']);
    });

    test('parses dependency_overrides from pubspec and overrides file', () {
      final info = PubspecInfo.parse('''
name: my_app
dependency_overrides:
  local_pkg:
    path: ../local_pkg
  pinned_pkg: 1.2.3
''', overridesContent: '''
dependency_overrides:
  git_pkg:
    git: https://example.com/git_pkg.git
''');

      expect(info.overrides, hasLength(3));
      final byName = {for (final o in info.overrides) o.name: o};
      expect(byName['local_pkg']!.source, 'path');
      expect(byName['local_pkg']!.origin, 'pubspec.yaml');
      expect(byName['local_pkg']!.blocksRelease, isTrue);
      expect(byName['pinned_pkg']!.source, 'version');
      expect(byName['pinned_pkg']!.blocksRelease, isFalse);
      expect(byName['git_pkg']!.source, 'git');
      expect(byName['git_pkg']!.origin, 'pubspec_overrides.yaml');
    });
  });
}
