import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_overlay.dart';

class ReportIncidentScreen extends StatefulWidget {
  const ReportIncidentScreen({super.key});

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  final _firestoreService = FirestoreService.instance;
  final _storageService = StorageService.instance;
  final _locationService = LocationService.instance;
  final _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();

  String? _selectedType;
  final List<XFile> _mediaFiles = [];
  double? _lat;
  double? _lng;
  String? _locationText;
  bool _loading = false;
  bool _locationLoading = true;
  double _uploadProgress = 0;

  static const _maxVideoBytes = 50 * 1024 * 1024; // 50 MB
  static const _maxImageBytes = 10 * 1024 * 1024; // 10 MB
  static const _maxMediaCount = 5;

  static const List<String> _incidentTypes = [
    'Flood',
    'Fire',
    'Rescue Needed',
    'Road Damage',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted) return;
      if (pos == null) {
        setState(() {
          _locationText = 'Location permissions denied or GPS off';
          _locationLoading = false;
        });
        return;
      }
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locationText =
            '📍 ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        _locationLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationText = 'Could not get location';
        _locationLoading = false;
      });
    }
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    if (_mediaFiles.length >= _maxMediaCount) {
      _showSnack('Maximum $_maxMediaCount files allowed.', isError: true);
      return;
    }
    try {
      XFile? picked;
      if (isVideo) {
        picked = await _imagePicker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 3),
        );
      } else {
        picked = await _imagePicker.pickImage(source: source, imageQuality: 75);
      }
      if (picked == null) return;

      // File size validation
      final bytes = await picked.length();
      final limit = isVideo ? _maxVideoBytes : _maxImageBytes;
      final limitLabel = isVideo ? '50 MB' : '10 MB';
      if (bytes > limit) {
        if (mounted)
          _showSnack('File too large. Max $limitLabel allowed.', isError: true);
        return;
      }

      setState(() => _mediaFiles.add(picked!));
    } catch (e) {
      if (mounted) _showSnack('Could not pick file: $e', isError: true);
    }
  }

  void _showMediaOptions({bool isVideo = false}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isVideo ? 'Add Video' : 'Add Photo',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isVideo ? Icons.videocam_outlined : Icons.camera_alt_outlined,
                  color: AppTheme.primaryBlue,
                ),
              ),
              title: Text(isVideo ? 'Record Video' : 'Take Photo'),
              subtitle: const Text('Use camera'),
              onTap: () {
                Navigator.pop(context);
                _pickMedia(ImageSource.camera, isVideo: isVideo);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isVideo
                      ? Icons.video_library_outlined
                      : Icons.photo_library_outlined,
                  color: AppTheme.primaryBlue,
                ),
              ),
              title: Text(isVideo ? 'Choose Video' : 'Choose Photo'),
              subtitle: const Text('From gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickMedia(ImageSource.gallery, isVideo: isVideo);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _removeMedia(int index) => setState(() => _mediaFiles.removeAt(index));

  bool _isVideoFile(XFile file) {
    final ext = file.name.toLowerCase().split('.').last;
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) {
      _showSnack('Please select an incident type.', isError: true);
      return;
    }
    if (_lat == null || _lng == null) {
      _showSnack('Location not available yet.', isError: true);
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;
    final uid = firebaseUser.uid;

    setState(() {
      _loading = true;
      _uploadProgress = 0;
    });

    try {
      // Fetch reporter name from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final d = userDoc.data();
      final firstName = (d?['first_name'] as String?) ?? '';
      final lastName = (d?['last_name'] as String?) ?? '';
      final reporterName = '$firstName $lastName'.trim();

      // Generate reportId upfront so media folder matches Firestore doc
      final reportId = FirebaseFirestore.instance
          .collection('reports')
          .doc()
          .id;

      // Upload media to Cloudinary
      List<String> photoUrls = [];
      if (_mediaFiles.isNotEmpty) {
        final files = _mediaFiles.map((x) => File(x.path)).toList();
        photoUrls = await _storageService.uploadReportMedia(
          uid,
          files,
          reportId: reportId,
          onProgress: (p) {
            if (mounted) setState(() => _uploadProgress = p);
          },
        );
      }

      // Build category from selected type
      final category = _selectedType!.toLowerCase().replaceAll(' ', '_');

      // Save report with correct field names matching ReportModel + FirestoreService
      await _firestoreService.createReport({
        'report_id': reportId,
        'reporter_id': uid,
        'reporter_name': reporterName,
        'title': _selectedType!,
        'body': _descController.text.trim(),
        'category': category,
        'latitude': _lat,
        'longitude': _lng,
        'photo_urls': photoUrls,
        'ai_score': null,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showSnack('Report submitted! It will be reviewed by a moderator.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Submission failed: $e', isError: true);
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
          _uploadProgress = 0;
        });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.dangerRed : AppTheme.successGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _loading,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          title: const Text(
            'Report Incident',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          elevation: 0,
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Incident Type ─────────────────────────────────────────
                _sectionLabel('Incident Type'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedType,
                      isExpanded: true,
                      hint: const Text('Select incident type'),
                      items: _incidentTypes
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedType = v),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // ── Description ───────────────────────────────────────────
                _sectionLabel('Description'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: 'Describe the incident in detail...',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryBlue,
                        width: 1.8,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Please enter a description.';
                    if (v.trim().length < 10)
                      return 'Description too short (min 10 characters).';
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // ── Media ─────────────────────────────────────────────────
                Row(
                  children: [
                    _sectionLabel('Media Attachments'),
                    const SizedBox(width: 8),
                    Text(
                      '${_mediaFiles.length}/$_maxMediaCount',
                      style: TextStyle(
                        fontSize: 12,
                        color: _mediaFiles.length >= _maxMediaCount
                            ? AppTheme.dangerRed
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Photos up to 10 MB · Videos up to 50 MB',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _mediaAddButton(
                      icon: Icons.photo_camera_outlined,
                      label: 'Photo',
                      onTap: () => _showMediaOptions(),
                    ),
                    const SizedBox(width: 10),
                    _mediaAddButton(
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      onTap: () => _showMediaOptions(isVideo: true),
                    ),
                  ],
                ),

                if (_mediaFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _mediaFiles.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final file = _mediaFiles[index];
                        final isVideo = _isVideoFile(file);
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: isVideo
                                  ? Container(
                                      width: 100,
                                      height: 100,
                                      color: Colors.black26,
                                      child: const Center(
                                        child: Icon(
                                          Icons.play_circle_outline,
                                          size: 36,
                                          color: Colors.white,
                                        ),
                                      ),
                                    )
                                  : Image.file(
                                      File(file.path),
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => _removeMedia(index),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.dangerRed,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                            if (isVideo)
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'VIDEO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],

                // ── Upload Progress ───────────────────────────────────────
                if (_loading && _uploadProgress > 0 && _uploadProgress < 1) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _uploadProgress,
                            backgroundColor: Colors.grey.shade200,
                            color: AppTheme.primaryBlue,
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${(_uploadProgress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),

                // ── Location ──────────────────────────────────────────────
                _sectionLabel('Location'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _locationLoading
                      ? const Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('Getting your location...'),
                          ],
                        )
                      : Row(
                          children: [
                            Icon(
                              _lat != null
                                  ? Icons.location_on
                                  : Icons.location_off,
                              size: 18,
                              color: _lat != null
                                  ? AppTheme.primaryBlue
                                  : AppTheme.dangerRed,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _locationText ?? 'Location unavailable',
                                style: TextStyle(
                                  color: _lat != null
                                      ? AppTheme.primaryBlue
                                      : AppTheme.dangerRed,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (_lat == null)
                              TextButton(
                                onPressed: () {
                                  setState(() => _locationLoading = true);
                                  _captureLocation();
                                },
                                child: const Text('Retry'),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 28),

                // ── Submit ────────────────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text(
                    'Submit Report',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 15,
      color: Colors.black87,
    ),
  );

  Widget _mediaAddButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final disabled = _mediaFiles.length >= _maxMediaCount;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.grey.shade100
              : AppTheme.primaryBlue.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: disabled
                ? Colors.grey.shade300
                : AppTheme.primaryBlue.withAlpha(76),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: disabled ? Colors.grey : AppTheme.primaryBlue,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: disabled ? Colors.grey : AppTheme.primaryBlue,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
