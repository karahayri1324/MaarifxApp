import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

class ImageUploadService {
  /// Uploads an image file to the backend and returns the image path
  /// Returns null if upload fails
  Future<String?> uploadImage(File imageFile) async {
    try {
      final uri = Uri.parse('${AppConfig.apiUrl}${AppConfig.uploadEndpoint}');

      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      final streamedResponse = await request.send().timeout(
            AppConfig.connectionTimeout,
          );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['path'] as String?;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Checks if the backend server is reachable
  Future<bool> checkServerStatus() async {
    try {
      final uri = Uri.parse('${AppConfig.apiUrl}${AppConfig.statusEndpoint}');

      final response = await http.get(uri).timeout(
            AppConfig.connectionTimeout,
          );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
