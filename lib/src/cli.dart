import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'doctor.dart';
import 'pubspec_info.dart';

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

  final staleDays = int.tryParse(args.option('stale-days')!);
  if (staleDays == null || staleDays <= 0) {
    stderr.writeln('--stale-days must be a positive integer.');
    return 2;
  }

  final options = DoctorOptions(
    ignore: args.multiOption('ignore').toSet(),
    staleDays: staleDays,
    offline: args.flag('offline'),
  );

  try {
    final report =
        await Doctor().diagnose(Directory(args.option('path')!), options);
    if (args.flag('json')) {
      stdout
          .writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    } else {
      stdout.writeln(report.toConsole());
    }
    return report.hasProblems(failOnStale: args.flag('fail-on-stale')) ? 1 : 0;
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
