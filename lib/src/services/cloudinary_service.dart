import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';

class CloudinaryService {
  static const _uploadUrl = 'https://api.cloudinary.com/v1_1';

  Future<String?> uploadImage(Uint8List imageBytes) async {
    final cloudName = AppConstants.cloudinaryCloudName;
    final apiKey = AppConstants.cloudinaryApiKey;
    final apiSecret = AppConstants.cloudinaryApiSecret;

    if (cloudName == null || apiKey == null || apiSecret == null) {
      print('Cloudinary credentials not configured');
      return null;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Generate signature
      final paramsToSign = 'timestamp=$timestamp$apiSecret';
      final signature = sha1.convert(utf8.encode(paramsToSign)).toString();

      // Prepare multipart request
      final uri = Uri.parse('$_uploadUrl/$cloudName/image/upload');
      final request = http.MultipartRequest('POST', uri);

      // Add fields
      request.fields['timestamp'] = timestamp.toString();
      request.fields['api_key'] = apiKey;
      request.fields['signature'] = signature;

      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'upload.jpg',
        ),
      );

      print('Uploading image to Cloudinary...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        print('Cloudinary upload successful: $secureUrl');
        return secureUrl;
      } else {
        print('Cloudinary upload failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error uploading to Cloudinary: $e');
      return null;
    }
  }
}
