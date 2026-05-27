import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/loading_overlay.dart';

// Max file size: 100MB in bytes
const int _maxFileSizeBytes = 100 * 1024 * 1024;

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _textCtrl = TextEditingController();
  final _picker = ImagePicker();

  String? _selectedType;

  // Each media item: { 'file': File, 'isVideo': bool, 'controller': VideoPlayerController? }
  final List<Map<String, dynamic>> _mediaItems = [];
  bool _isPosting = false;

  static const _primaryBlue = Color(0xFF0D47A1);
  static const _dangerRed = Color(0xFFD7263D);
  static const _successGreen = Color(0xFF1FAA59);
  static const _background = Color(0xFFF5F7FA);
  static const _maxItems = 6;

  static const _incidentTypes = [
    {'label': 'Flood', 'icon': Icons.water, 'color': Color(0xFF1565C0)},
    {
      'label': 'Fire',
      'icon': Icons.local_fire_department,
      'color': Color(0xFFD7263D),
    },
    {
      'label': 'Rescue Needed',
      'icon': Icons.health_and_safety,
      'color': Color(0xFFFF6B00),
    },
    {
      'label': 'Road Damage',
      'icon': Icons.warning_amber_rounded,
      'color': Color(0xFF6A1B9A),
    },
    {
      'label': 'Other',
      'icon': Icons.report_outlined,
      'color': Color(0xFF546E7A),
    },
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    for (final item in _mediaItems) {
      (item['controller'] as VideoPlayerController?)?.dispose();
    }
    super.dispose();
  }

  // ── File size check ────────────────────────────────────────────────────────
  Future<bool> _checkFileSize(File file) async {
    final bytes = await file.length();
    if (bytes > _maxFileSizeBytes) {
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      if (mounted) {
        _snack(
          'File too large (${mb}MB). Maximum allowed is 100MB.',
          isError: true,
        );
      }
      return false;
    }
    return true;
  }

  // ── Pick image ─────────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    if (_mediaItems.length >= _maxItems) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    final file = File(picked.path);
    if (!await _checkFileSize(file)) return;

    setState(
      () =>
          _mediaItems.add({'file': file, 'isVideo': false, 'controller': null}),
    );
  }

  // ── Pick video ─────────────────────────────────────────────────────────────
  Future<void> _pickVideo(ImageSource source) async {
    if (_mediaItems.length >= _maxItems) return;
    final picked = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked == null) return;

    final file = File(picked.path);
    if (!await _checkFileSize(file)) return;

    // Init video controller for thumbnail
    final controller = VideoPlayerController.file(file);
    await controller.initialize();

    setState(
      () => _mediaItems.add({
        'file': file,
        'isVideo': true,
        'controller': controller,
      }),
    );
  }

  void _removeItem(int index) {
    final item = _mediaItems[index];
    (item['controller'] as VideoPlayerController?)?.dispose();
    setState(() => _mediaItems.removeAt(index));
  }

  // ── Media picker sheet ─────────────────────────────────────────────────────
  void _showMediaSheet() {
    if (_mediaItems.length >= _maxItems) {
      _snack('Maximum $_maxItems files allowed.', isError: true);
      return;
    }
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
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            // 100MB notice
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B00).withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFF6B00).withAlpha(60),
                ),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 16, color: Color(0xFFFF6B00)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Maximum file size: 100MB per file',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFF6B00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _sourceItem(Icons.camera_alt_outlined, 'Take a Photo', () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            }),
            _sourceItem(Icons.photo_library_outlined, 'Photo from Gallery', () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            }),
            _sourceItem(Icons.videocam_outlined, 'Record a Video', () {
              Navigator.pop(context);
              _pickVideo(ImageSource.camera);
            }),
            _sourceItem(Icons.video_library_outlined, 'Video from Gallery', () {
              Navigator.pop(context);
              _pickVideo(ImageSource.gallery);
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sourceItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _primaryBlue.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _primaryBlue),
      ),
      title: Text(label),
      onTap: onTap,
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _snack('Please write something before posting.', isError: true);
      return;
    }
    setState(() => _isPosting = true);

    try {
      final auth = context.read<AuthProvider>();
      final uid = auth.user?.uid;
      if (uid == null) return;

      // Get author name from Firestore
      String authorName = 'Anonymous';
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final d = doc.data();
        if (d != null) {
          final first = d['first_name'] as String? ?? '';
          final last = d['last_name'] as String? ?? '';
          authorName = '$first $last'.trim().isEmpty
              ? 'Anonymous'
              : '$first $last'.trim();
        }
      } catch (_) {}

      // Upload media
      List<String> mediaUrls = [];
      if (_mediaItems.isNotEmpty) {
        final files = _mediaItems.map((m) => m['file'] as File).toList();
        final postId = FirebaseFirestore.instance
            .collection('community_feed')
            .doc()
            .id;
        mediaUrls = await StorageService.instance.uploadReportMedia(
          uid,
          files,
          reportId: postId,
        );
      }

      await FirestoreService.instance.createCommunityPost({
        'author_id': uid,
        'author_name': authorName,
        'text': text,
        'type': _selectedType ?? 'General',
        'media_urls': mediaUrls,
        'has_video': _mediaItems.any((m) => m['isVideo'] == true),
      });

      if (mounted) {
        _snack('Post submitted! Waiting for moderator approval.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack('Failed to post: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _dangerRed : _successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    return LoadingOverlay(
      isLoading: _isPosting,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
          title: const Text(
            'Create Post',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isPosting ? null : _submit,
                icon: _isPosting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isPosting ? 'Posting...' : 'Post to Community Feed',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Author ────────────────────────────────────────────────
              _AuthorHeader(auth: auth),
              const SizedBox(height: 16),

              // ── Text ──────────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: TextField(
                  controller: _textCtrl,
                  maxLines: 6,
                  minLines: 4,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(
                    hintText:
                        "What's on your mind? Share an update or incident...",
                    hintStyle: TextStyle(
                      color: Color(0xFF90A4AE),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Incident type ─────────────────────────────────────────
              const Text(
                'Tag Incident Type (optional)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF546E7A),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _incidentTypes.map((type) {
                  final label = type['label'] as String;
                  final icon = type['icon'] as IconData;
                  final color = type['color'] as Color;
                  final isSelected = _selectedType == label;
                  return GestureDetector(
                    onTap: () => setState(
                      () => _selectedType = isSelected ? null : label,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? color : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? color : const Color(0xFFCFD8DC),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 16,
                            color: isSelected ? Colors.white : color,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF37474F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ── Media section ─────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Photos / Videos',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF546E7A),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '${_mediaItems.length}/$_maxItems',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF90A4AE),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_mediaItems.length < _maxItems)
                        TextButton.icon(
                          onPressed: _showMediaSheet,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                          style: TextButton.styleFrom(
                            foregroundColor: _primaryBlue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // 100MB notice
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF546E7A).withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Color(0xFF546E7A),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Max 100MB per file · Up to 6 files',
                      style: TextStyle(fontSize: 11, color: Color(0xFF546E7A)),
                    ),
                  ],
                ),
              ),

              // Media grid
              if (_mediaItems.isEmpty)
                GestureDetector(
                  onTap: _showMediaSheet,
                  child: Container(
                    width: double.infinity,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFCFD8DC)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.perm_media_outlined,
                          color: _primaryBlue.withAlpha(150),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to add photos or videos',
                          style: TextStyle(
                            color: _primaryBlue.withAlpha(180),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount:
                        _mediaItems.length +
                        (_mediaItems.length < _maxItems ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      // Add button at end
                      if (index == _mediaItems.length) {
                        return GestureDetector(
                          onTap: _showMediaSheet,
                          child: Container(
                            width: 100,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFCFD8DC),
                              ),
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Color(0xFF90A4AE),
                            ),
                          ),
                        );
                      }

                      final item = _mediaItems[index];
                      final isVideo = item['isVideo'] as bool;
                      final file = item['file'] as File;
                      final controller =
                          item['controller'] as VideoPlayerController?;

                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child:
                                isVideo &&
                                    controller != null &&
                                    controller.value.isInitialized
                                ? AspectRatio(
                                    aspectRatio: controller.value.aspectRatio,
                                    child: VideoPlayer(controller),
                                  )
                                : Image.file(
                                    file,
                                    width: 100,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          // Video badge
                          if (isVideo)
                            Positioned(
                              bottom: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    SizedBox(width: 2),
                                    Text(
                                      'Video',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // Remove button
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removeItem(index),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
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

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// AUTHOR HEADER
// =============================================================================

class _AuthorHeader extends StatefulWidget {
  final AuthProvider auth;
  const _AuthorHeader({required this.auth});

  @override
  State<_AuthorHeader> createState() => _AuthorHeaderState();
}

class _AuthorHeaderState extends State<_AuthorHeader> {
  String _name = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final uid = widget.auth.user?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final d = doc.data();
      if (d != null && mounted) {
        final first = d['first_name'] as String? ?? '';
        final last = d['last_name'] as String? ?? '';
        setState(
          () => _name = '$first $last'.trim().isEmpty
              ? 'Anonymous'
              : '$first $last'.trim(),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _name = 'Anonymous');
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = _name
        .trim()
        .split(' ')
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join();

    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF0D47A1),
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _name,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Color(0xFF1A237E),
              ),
            ),
            const Text(
              'Posting to Community Feed',
              style: TextStyle(fontSize: 12, color: Color(0xFF546E7A)),
            ),
          ],
        ),
      ],
    );
  }
}
