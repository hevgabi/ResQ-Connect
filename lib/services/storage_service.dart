import 'dart:io';
import 'cloudinary_service.dart';

/// Unified storage service for ResQConnect.
/// Delegates all uploads to Cloudinary — no Firebase Storage needed.
///
/// Folder structure:
/// resqconnect/
/// └── users/
///       └── {uid}/
///             ├── avatar      ← profile photo
///             ├── gov_id      ← government ID
///             └── reports/
///                   └── {reportId}/   ← if reportId provided
///                         └── files
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final _cloudinary = CloudinaryService.instance;

  /// Uploads a profile photo for [uid].
  /// Saved as: resqconnect/users/{uid}/avatar
  Future<String> uploadProfilePhoto(
    String uid,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    return _cloudinary.uploadFile(
      file,
      folder: 'resqconnect/users/$uid',
      publicId: 'avatar',
      onProgress: onProgress,
    );
  }

  /// Uploads a government ID for [uid].
  /// Saved as: resqconnect/users/{uid}/gov_id
  Future<String> uploadGovId(
    String uid,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    return _cloudinary.uploadFile(
      file,
      folder: 'resqconnect/users/$uid',
      publicId: 'gov_id',
      onProgress: onProgress,
    );
  }

  /// Uploads multiple media files for a report or community post.
  /// If [reportId] is provided: resqconnect/users/{uid}/reports/{reportId}/
  /// Otherwise:                 resqconnect/users/{uid}/reports/
  Future<List<String>> uploadReportMedia(
    String uid,
    List<File> files, {
    String? reportId,
    void Function(double progress)? onProgress,
  }) async {
    final folder = reportId != null
        ? 'resqconnect/users/$uid/reports/$reportId'
        : 'resqconnect/users/$uid/reports';
    return _cloudinary.uploadFiles(
      files,
      folder: folder,
      onProgress: onProgress,
    );
  }
}
