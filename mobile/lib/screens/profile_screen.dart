import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../config/api_constants.dart';
import '../services/auth_service.dart';
import '../widgets/liquid_glass.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const ProfileScreen({super.key, required this.cameras});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, String> _userData = {
    'name': '...',
    'nip': '...',
    'email': '...',
    'role': '...',
    'face_photo': '',
  };
  bool _isLoading = true;
  bool _isUploadingFace = false;
  int _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final localData = await AuthService.getUserData();
    if (mounted) {
      setState(() {
        _userData = localData;
        _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;
        _isLoading = false;
      });
    }

    // Ambil data terbaru dari server
    final serverData = await AuthService.fetchProfile();
    if (serverData != null && mounted) {
      final updatedLocal = await AuthService.getUserData();
      setState(() {
        _userData = updatedLocal;
        _avatarCacheKey = DateTime.now().millisecondsSinceEpoch;
      });
    }
  }

  String? _getFacePhotoUrl() {
    final photo = _userData['face_photo']?.trim();
    if (photo == null || photo.isEmpty) return null;
    if (photo.startsWith('http://') || photo.startsWith('https://')) {
      return photo;
    }
    final cleanPath = photo.replaceAll(r'\', '/').replaceAll(RegExp(r'^/+'), '');
    return '${ApiConstants.baseUrl}/$cleanPath?v=$_avatarCacheKey';
  }

  void _showPhotoPreviewDialog(String photoUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Master Biometrik Wajah',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF242721)),
                        ),
                        Text(
                          'Foto acuan untuk presensi biometrik',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF365C4A)));
                    },
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade100,
                      child: const Center(
                        child: Text('Gagal memuat foto master wajah', style: TextStyle(color: Colors.black54)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? photoUrl, bool hasMasterFace) {
    final initialLetter = (_userData['name'] ?? 'K').trim().isNotEmpty
        ? (_userData['name']!.trim().substring(0, 1).toUpperCase())
        : 'U';

    return Center(
      child: GestureDetector(
        onTap: () {
          if (hasMasterFace && photoUrl != null) {
            _showPhotoPreviewDialog(photoUrl);
          }
        },
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF365C4A),
                Color(0xFF10B981),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF365C4A).withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(3.5),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            padding: const EdgeInsets.all(2.5),
            child: ClipOval(
              child: (hasMasterFace && photoUrl != null)
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      width: 92,
                      height: 92,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 92,
                          height: 92,
                          color: const Color(0xFF365C4A).withValues(alpha: 0.1),
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF365C4A),
                              ),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return _buildInitialFallback(initialLetter);
                      },
                    )
                  : _buildInitialFallback(initialLetter),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialFallback(String initialLetter) {
    return Container(
      width: 92,
      height: 92,
      color: const Color(0xFF365C4A).withValues(alpha: 0.12),
      child: Center(
        child: Text(
          initialLetter,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: Color(0xFF365C4A),
          ),
        ),
      ),
    );
  }

  Future<void> _handleUploadFacePhoto() async {
    if (widget.cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada kamera terdeteksi pada perangkat.')),
      );
      return;
    }

    final frontCamera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    final controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await controller.initialize();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menginisialisasi kamera: $e')),
        );
      }
      return;
    }

    if (!mounted) return;

    final XFile? capturedFile = await showDialog<XFile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Ambil Foto Master Wajah', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CameraPreview(controller),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Pastikan wajah menghadap depan dengan pencahayaan cukup.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                controller.dispose();
                Navigator.pop(ctx, null);
              },
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF365C4A),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                try {
                  final photo = await controller.takePicture();
                  controller.dispose();
                  if (ctx.mounted) Navigator.pop(ctx, photo);
                } catch (err) {
                  controller.dispose();
                  if (ctx.mounted) Navigator.pop(ctx, null);
                }
              },
              child: const Text('Ambil Foto'),
            ),
          ],
        );
      },
    );

    if (capturedFile != null) {
      setState(() => _isUploadingFace = true);
      final result = await AuthService.uploadMasterFace(capturedFile);
      setState(() => _isUploadingFace = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? ''),
            backgroundColor: result['success'] == true ? Colors.green : Colors.red,
          ),
        );
        _loadUserData();
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Konfirmasi Keluar'),
        content: const Text('Apakah Anda yakin ingin keluar dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginScreen(cameras: widget.cameras)),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMasterFace = (_userData['face_photo'] ?? '').isNotEmpty;
    final photoUrl = _getFacePhotoUrl();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: LiquidGlassAppBar(
        title: 'Profil Saya',
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _handleLogout,
            tooltip: 'Keluar',
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'lib/asset/baground/BG.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: const Color(0xFF365C4A)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.20),
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.30),
                ],
              ),
            ),
          ),
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF365C4A)))
                : RefreshIndicator(
                    onRefresh: _loadUserData,
                    color: const Color(0xFF365C4A),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                      children: [
                        // User Avatar & Name Card
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                          ),
                          child: Column(
                            children: [
                              _buildAvatar(photoUrl, hasMasterFace),
                              const SizedBox(height: 14),
                              Text(
                                _userData['name'] ?? '-',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF242721),
                                  letterSpacing: 0.2,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'NIP: ${_userData['nip'] ?? '-'}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (hasMasterFace)
                                    Container(
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.verified_rounded, size: 13, color: Color(0xFF10B981)),
                                          SizedBox(width: 4),
                                          Text(
                                            'BIOMETRIK AKTIF',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF10B981),
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                  // Connection & Info Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Informasi Akun',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF242721)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Email/Username Akun', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _userData['email'] ?? '-',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),

                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Divisi', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                (_userData['divisi'] ?? '').isNotEmpty
                                    ? _userData['divisi']!
                                    : 'Belum ditentukan',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: (_userData['divisi'] ?? '').isNotEmpty
                                      ? const Color(0xFF242721)
                                      : Colors.black38,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
