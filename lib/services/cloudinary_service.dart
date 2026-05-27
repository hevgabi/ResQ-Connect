import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Cloudinary upload service for ResQConnect.
///
/// SETUP (one-time):
/// 1. Go to https://cloudinary.com and create a FREE account
/// 2. From your dashboard, copy your Cloud Name
/// 3. Go to Settings → Upload → Add upload preset
///    - Set "Signing Mode" to UNSIGNED
///    - Copy the preset name
/// 4. Replace the two placeholders below
///
/// Free tier: 25GB storage + 25GB bandwidth/month
class CloudinaryService {
  static const String _cloudName = 'diozmzeak';
  static const String _uploadPreset = 'resqconnect_unsigned';

  static const int _maxVideoBytes = 100 * 1024 * 1024; // 100 MB
  static const int _maxImageBytes = 100 * 1024 * 1024; // 100 MB

  CloudinaryService._();
  static final CloudinaryService instance = CloudinaryService._();

  String get _baseUrl => 'https://api.cloudinary.com/v1_1/$_cloudName';

  String _resourceType(File file) {
    final ext = file.path.split('.').last.toLowerCase();
    const videoExts = {'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'};
    return videoExts.contains(ext) ? 'video' : 'image';
  }

  String _mimeType(File file) {
    final ext = file.path.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      '3gp': 'video/3gpp',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  void _validateSize(File file) {
    final bytes = file.lengthSync();
    final resourceType = _resourceType(file);
    if (resourceType == 'video' && bytes > _maxVideoBytes) {
      throw CloudinaryException(
        'Video file is too large. Maximum allowed size is 100 MB.',
      );
    }
    if (resourceType == 'image' && bytes > _maxImageBytes) {
      throw CloudinaryException(
        'Image file is too large. Maximum allowed size is 100 MB.',
      );
    }
  }

  /// Uploads a single [file] to Cloudinary under [folder].
  /// Optional [publicId] sets a fixed filename (without extension).
  /// e.g. publicId: 'gov_id' → saved as resqconnect/users/{uid}/gov_id.jpg
  Future<String> uploadFile(
    File file, {
    required String folder,
    String? publicId,
    void Function(double progress)? onProgress,
  }) async {
    _validateSize(file);

    final resourceType = _resourceType(file);
    final url = Uri.parse('$_baseUrl/$resourceType/upload');

    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = folder;

    // If publicId is given, Cloudinary saves as folder/publicId
    if (publicId != null) {
      request.fields['public_id'] = publicId;
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: _mediaType(_mimeType(file)),
      ),
    );

    onProgress?.call(0.05);

    final streamedResponse = await request.send();
    onProgress?.call(0.90);

    final responseBody = await streamedResponse.stream.bytesToString();
    onProgress?.call(1.0);

    if (streamedResponse.statusCode != 200) {
      final decoded = jsonDecode(responseBody);
      throw CloudinaryException(
        decoded['error']?['message'] ??
            'Upload failed (${streamedResponse.statusCode})',
      );
    }

    final decoded = jsonDecode(responseBody);
    return decoded['secure_url'] as String;
  }

  /// Uploads multiple files sequentially.
  /// Returns URLs in the same order as [files].
  Future<List<String>> uploadFiles(
    List<File> files, {
    required String folder,
    void Function(double progress)? onProgress,
  }) async {
    if (files.isEmpty) return [];

    final urls = <String>[];
    final total = files.length;

    for (int i = 0; i < total; i++) {
      final url = await uploadFile(
        files[i],
        folder: folder,
        onProgress: onProgress != null
            ? (p) => onProgress(((i + p) / total).clamp(0.0, 1.0))
            : null,
      );
      urls.add(url);
    }

    onProgress?.call(1.0);
    return urls;
  }

  MediaType _mediaType(String mime) {
    final parts = mime.split('/');
    return MediaType(parts[0], parts.length > 1 ? parts[1] : '*');
  }
}

/// Thrown when Cloudinary upload fails or validation fails.
class CloudinaryException implements Exception {
  final String message;
  const CloudinaryException(this.message);

  @override
  String toString() => 'CloudinaryException: $message';
}
