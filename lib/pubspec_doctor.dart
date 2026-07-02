/// Audits pubspec.yaml dependencies: finds unused packages and flags
/// discontinued or stale ones using the pub.dev API.
library;

export 'src/doctor.dart';
export 'src/pub_api_client.dart';
export 'src/pubspec_info.dart';
export 'src/report.dart';
export 'src/usage_scanner.dart';
