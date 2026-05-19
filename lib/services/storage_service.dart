import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

/// Singleton Firebase Storage service for ResQConnect.
/// Handles all file uploads — profile photos, gov IDs, and report media.
class StorageService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  StorageService._();
  static final StorageService instance = StorageService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Uploads a single [file] to [storagePath] and returns the public download URL.
  /// [onProgress] is called with values 0.0–1.0 as bytes transfer.
  Future<String> _uploadFile(
    String storagePath,
    File file, {
    String? contentType,
    void Function(double progress)? onProgress,
  }) async {
    final ref = _storage.ref(storagePath);

    final metadata = contentType != null
        ? SettableMetadata(contentType: contentType)
        : null;

    final uploadTask = metadata != null
        ? ref.putFile(file, metadata)
        : ref.putFile(file);

    // Wire up progress callback if provided.
    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (snapshot.totalBytes > 0) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress(progress.clamp(0.0, 1.0));
        }
      });
    }

    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  /// Returns the file's MIME type based on its extension.
  /// Falls back to 'application/octet-stream' for unknown types.
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
      'pdf': 'application/pdf',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Uploads a profile photo for [uid] to `profile_photos/{uid}`.
  ///
  /// Overwrites any existing photo for that user (one photo per UID).
  /// Returns the public download URL.
  Future<String> uploadProfilePhoto(
    String uid,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final path = 'profile_photos/$uid';
    return _uploadFile(
      path,
      file,
      contentType: _mimeType(file),
      onProgress: onProgress,
    );
  }

  /// Uploads a government ID for [uid] to `gov_ids/{uid}/{timestamp}`.
  ///
  /// Timestamped so re-submissions don't overwrite previous uploads,
  /// allowing admins to audit submission history.
  /// Returns the public download URL.
  Future<String> uploadGovId(
    String uid,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = file.path.split('.').last.toLowerCase();
    final path = 'gov_ids/$uid/${timestamp}.$ext';
    return _uploadFile(
      path,
      file,
      contentType: _mimeType(file),
      onProgress: onProgress,
    );
  }

  /// Uploads multiple media files for an incident report.
  ///
  /// Each file is stored at `reports/{uid}/{timestamp}_{index}.{ext}`.
  /// [onProgress] is called with aggregate progress across all files (0.0–1.0).
  ///
  /// Uploads run sequentially to avoid saturating the connection on low-end
  /// Android devices common in disaster scenarios.
  ///
  /// Returns a list of download URLs in the same order as [files].
  Future<List<String>> uploadReportMedia(
    String uid,
    List<File> files, {
    void Function(double progress)? onProgress,
  }) async {
    if (files.isEmpty) return [];

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[];
    final total = files.length;

    for (int i = 0; i < total; i++) {
      final file = files[i];
      final ext = file.path.split('.').last.toLowerCase();
      final path = 'reports/$uid/${timestamp}_$i.$ext';

      // Per-file progress mapped into the slice [i/total, (i+1)/total].
      void perFileProgress(double p) {
        if (onProgress != null) {
          final aggregate = (i + p) / total;
          onProgress(aggregate.clamp(0.0, 1.0));
        }
      }

      final url = await _uploadFile(
        path,
        file,
        contentType: _mimeType(file),
        onProgress: onProgress != null ? perFileProgress : null,
      );
      urls.add(url);
    }

    // Ensure we always signal 100% completion.
    onProgress?.call(1.0);
    return urls;
  }
}
