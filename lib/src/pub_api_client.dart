import 'dart:convert';

import 'package:http/http.dart' as http;

/// Health facts about a hosted package, as reported by the pub.dev API.
class PackageHealth {
  PackageHealth({
    required this.name,
    required this.isDiscontinued,
    required this.latestVersion,
    required this.publishedAt,
    this.replacedBy,
  });

  final String name;
  final bool isDiscontinued;
  final String? replacedBy;
  final String latestVersion;
  final DateTime publishedAt;

  Map<String, Object?> toJson() => {
        'name': name,
        'isDiscontinued': isDiscontinued,
        if (replacedBy != null) 'replacedBy': replacedBy,
        'latestVersion': latestVersion,
        'publishedAt': publishedAt.toIso8601String(),
      };
}

class PubApiException implements Exception {
  PubApiException(this.package, this.message);

  final String package;
  final String message;

  @override
  String toString() => '$package: $message';
}

/// Minimal client for `GET /api/packages/<name>` on pub.dev.
class PubApiClient {
  PubApiClient({http.Client? client, this.baseUrl = 'https://pub.dev'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<PackageHealth> fetch(String package) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/packages/$package'),
      headers: {'accept': 'application/json'},
    );
    if (response.statusCode == 404) {
      throw PubApiException(package, 'not found on pub.dev');
    }
    if (response.statusCode != 200) {
      throw PubApiException(
          package, 'pub.dev returned HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final latest = body['latest'] as Map<String, dynamic>;
    return PackageHealth(
      name: package,
      isDiscontinued: body['isDiscontinued'] as bool? ?? false,
      replacedBy: body['replacedBy'] as String?,
      latestVersion: latest['version'] as String,
      publishedAt: DateTime.parse(latest['published'] as String),
    );
  }

  void close() => _client.close();
}
