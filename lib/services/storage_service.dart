import 'dart:io';
import 'cloudinary_service.dart';

/// Unified storage service for ResQConnect.
/// Delegates all uploads to Cloudinary — no Firebase Storage needed.
/// Public API is identical to the old Firebase version so no other files need changing.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final _cloudinary = CloudinaryService.instance;

  /// Uploads a profile photo for [uid].
  /// Returns the secure Cloudinary URL.
  Future<String> uploadProfilePhoto(
    String uid,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    return _cloudinary.uploadFile(
      file,
      folder: 'resqconnect/profiles/$uid',
      onProgress: onProgress,
    );
  }

  /// Uploads a government ID for [uid].
  /// Timestamped so re-submissions don't overwrite previous uploads.
  /// Returns the secure Cloudinary URL.
  Future<String> uploadGovId(
    String uid,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    return _cloudinary.uploadFile(
      file,
      folder: 'resqconnect/gov_ids/$uid',
      onProgress: onProgress,
    );
  }

  /// Uploads multiple media files (images/videos) for an incident report.
  /// Returns a list of secure Cloudinary URLs in the same order as [files].
  Future<List<String>> uploadReportMedia(
    String uid,
    List<File> files, {
    void Function(double progress)? onProgress,
  }) async {
    return _cloudinary.uploadFiles(
      files,
      folder: 'resqconnect/reports/$uid',
      onProgress: onProgress,
    );
  }
}
