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
  final FirestoreService _firestoreService = FirestoreService.instance;

  // SOLUSYON: Ginamit ang tamang named constructor/singleton pattern ng StorageService mo
  final StorageService _storageService = StorageService.instance;
  final LocationService _locationService = LocationService.instance;
  final ImagePicker _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();

  String? _selectedType;
  final List<XFile> _mediaFiles = [];
  double? _lat;
  double? _lng;
  String? _locationText;
  bool _loading = false;
  bool _locationLoading = true;

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
    try {
      XFile? picked;
      if (isVideo) {
        picked = await _imagePicker.pickVideo(source: source);
      } else {
        picked = await _imagePicker.pickImage(source: source, imageQuality: 75);
      }
      if (picked == null) return;
      setState(() => _mediaFiles.add(picked!));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Media pick error: $e')));
      }
    }
  }

  void _removeMedia(int index) {
    setState(() => _mediaFiles.removeAt(index));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an incident type.')),
      );
      return;
    }
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available yet.')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loading = true);

    try {
      final List<File> filesToUpload = _mediaFiles
          .map((xFile) => File(xFile.path))
          .toList();

      final List<String> mediaUrls = await _storageService.uploadReportMedia(
        uid,
        filesToUpload,
      );

      await _firestoreService.createReport({
        'author_id': uid,
        'type': _selectedType,
        'description': _descController.text.trim(),
        'media_urls': mediaUrls,
        'lat': _lat,
        'lng': _lng,
        'ai_score': null,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted for review'),
          backgroundColor: AppTheme.successGreen,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: $e'),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
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
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter a description.';
                    }
                    if (v.trim().length < 10) {
                      return 'Description too short (min 10 characters).';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 18),

                _sectionLabel('Media Attachments'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _mediaAddButton(
                      icon: Icons.photo_library_outlined,
                      label: 'Add Photo',
                      onTap: () => _pickMedia(ImageSource.gallery),
                    ),
                    const SizedBox(width: 10),
                    _mediaAddButton(
                      icon: Icons.videocam_outlined,
                      label: 'Add Video',
                      onTap: () =>
                          _pickMedia(ImageSource.gallery, isVideo: true),
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
                        final isVideo = file.name.toLowerCase().endsWith(
                          '.mp4',
                        );
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
                                          Icons.videocam,
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
                          ],
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 18),

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
                      : Text(
                          _locationText ?? 'Location unavailable',
                          style: TextStyle(
                            color: _lat != null
                                ? AppTheme.primaryBlue
                                : AppTheme.dangerRed,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),

                const SizedBox(height: 28),

                ElevatedButton.icon(
                  onPressed: _submit,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryBlue, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.primaryBlue,
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
