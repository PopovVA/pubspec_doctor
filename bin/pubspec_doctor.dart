import 'dart:io';

import 'package:pubspec_doctor/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments);
}
