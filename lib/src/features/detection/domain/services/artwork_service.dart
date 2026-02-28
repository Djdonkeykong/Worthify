import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../../core/constants/app_constants.dart';
import '../models/artwork_result.dart';

class ArtworkService {
  ArtworkService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Sends [imageUrl] (a public Cloudinary URL) to the artwork identification
  /// server and returns a structured [ArtworkResult].
  Future<ArtworkResult> identifyArtwork(String imageUrl) async {
    if (imageUrl.isEmpty) {
      throw ArgumentError('imageUrl must not be empty');
    }

    final uri = Uri.parse(AppConstants.artworkIdentifyEndpoint);
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'image_url': imageUrl}),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return ArtworkResult.fromJson(json);
    }

    // Surface the server's error detail if available
    String detail;
    try {
      final body = jsonDecode(response.body);
      detail = (body['detail'] is Map)
          ? (body['detail']['error'] ?? body['detail'].toString())
          : body['detail']?.toString() ?? response.body;
    } catch (_) {
      detail = response.body;
    }

    throw Exception('Artwork identification failed (${response.statusCode}): $detail');
  }
}
