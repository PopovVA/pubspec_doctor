import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'config.dart';
import 'doctor.dart';
import 'fixer.dart';
import 'pubspec_info.dart';
import 'workspace.dart';

/// Exit codes: 0 — healthy, 1 — problems found, 2 — usage or runtime error.
Future<int> run(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'path',
      abbr: 'p',
      defaultsTo: '.',
      help: 'Path to the project root (where pubspec.yaml lives).',
    )
    ..addMultiOption(
      'ignore',
      abbr: 'i',
      help: 'Package names to exclude from all checks.',
    )
    ..addOption(
      'stale-days',
      defaultsTo: '730',
      help: 'Flag packages whose latest release is older than this many days.',
    )
    ..addFlag(
      'offline',
      negatable: false,
      help: 'Skip pub.dev health checks (unused-dependency analysis only).',
    )
    ..addFlag(
      'fail-on-stale',
      negatable: false,
      help: 'Also return a non-zero exit code when stale packages are found.',
    )
    ..addFlag('json', negatable: false, help: 'Output the report as JSON.')
    ..addFlag(
      'fix',
      negatable: false,
      help: 'Apply safe fixes to pubspec.yaml: remove unused dependencies, '
          'move wrongly promoted ones, delete path/git overrides.',
    )
    ..addFlag(
      'fix-outdated',
      negatable: false,
      help: 'Also bump constraints that do not allow the latest release '
          '(may pull in breaking changes — review the diff).',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this usage information.',
    );

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(_usage(parser));
    return 2;
  }

  if (args.flag('help')) {
    stdout.writeln(_usage(parser));
    return 0;
  }

  final cliStaleDays = int.tryParse(args.option('stale-days')!);
  if (cliStaleDays == null || cliStaleDays <= 0) {
    stderr.writeln('--stale-days must be a positive integer.');
    return 2;
  }

  final root = Directory(args.option('path')!);

  try {
    // CLI flags win over config files; ignore lists are merged. Workspace
    // members inherit the root config, with their own config on top.
    final rootConfig = DoctorConfig.load(root);
    DoctorOptions optionsFor(Directory dir) {
      final config = dir.path == root.path
          ? rootConfig
          : rootConfig.mergedWith(DoctorConfig.load(dir));
      return DoctorOptions(
        ignore: {...config.ignore, ...args.multiOption('ignore')},
        staleDays: args.wasParsed('stale-days')
            ? cliStaleDays
            : config.staleDays ?? cliStaleDays,
        offline: args.flag('offline'),
      );
    }

    final failOnStale =
        args.flag('fail-on-stale') || (rootConfig.failOnStale ?? false);

    final results = await WorkspaceDoctor().diagnose(root, optionsFor);
    final isWorkspace = results.length > 1;

    if (args.flag('json')) {
      final json = isWorkspace
          ? {
              'workspace': [
                for (final r in results) {'path': r.path, ...r.report.toJson()},
              ],
            }
          : results.single.report.toJson();
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(json));
    } else {
      final annotate = Platform.environment['GITHUB_ACTIONS'] == 'true';
      for (final result in results) {
        if (isWorkspace) stdout.writeln('── ${result.path} ──');
        stdout.writeln(result.report.toConsole());
        if (isWorkspace) stdout.writeln();
        // Inside GitHub Actions, also emit findings as PR annotations.
        if (annotate) {
          result.report
              .toGithubAnnotations(pubspecFile: result.pubspecFile)
              .forEach(stdout.writeln);
        }
      }
    }
    if (args.flag('fix') || args.flag('fix-outdated')) {
      final fixer = Fixer();
      var fixedAny = false;
      for (final result in results) {
        final dir = result.path == '.'
            ? root
            : Directory('${root.path}${Platform.pathSeparator}${result.path}');
        final applied = fixer.apply(
          dir,
          result.report,
          safe: args.flag('fix'),
          outdated: args.flag('fix-outdated'),
        );
        if (applied.isEmpty) continue;
        fixedAny = true;
        stdout.writeln(isWorkspace
            ? 'Fixed ${result.pubspecFile}:'
            : 'Fixed pubspec.yaml:');
        for (final fix in applied) {
          stdout.writeln('  * $fix');
        }
      }
      if (fixedAny) {
        stdout.writeln(
            'Review the diff, then run `dart pub get` and your tests.');
      }
    }

    return results.any((r) => r.report.hasProblems(failOnStale: failOnStale))
        ? 1
        : 0;
  } on PubspecNotFoundException catch (e) {
    stderr.writeln(e);
    return 2;
  } on FormatException catch (e) {
    stderr.writeln('Failed to parse pubspec.yaml: ${e.message}');
    return 2;
  }
}

String _usage(ArgParser parser) => 'Audit pubspec.yaml dependencies: unused, '
    'discontinued and stale packages.\n\n'
    'Usage: pubspec_doctor [options]\n\n'
    '${parser.usage}';
