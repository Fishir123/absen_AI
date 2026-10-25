import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../widgets/liquid_glass.dart';
import 'login_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AttendanceScreen({super.key, required this.cameras});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCameraLoading = true;
  String? _cameraErrorMessage;
  bool _isLoading = false;
  String _loadingMessage = '';
  Position? _currentPosition;
  List<OfficeLocation> _officeLocations = [];
  OfficeLocation? _officeLocation; // Lokasi terdekat dalam radius
  TodayAttendanceStatus? _todayStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAttendanceScreen();
  }

  /// Inisialisasi awal layar: cek status absensi terlebih dahulu
  Future<void> _initAttendanceScreen() async {
    _fetchQuickLocation();
    _fetchOfficeLocations();
    await _fetchTodayStatus();

    // Matikan / jangan nyalakan kamera jika sudah Clock In atau sudah Izin hari ini
    if (mounted) {
      if (_todayStatus?.hasClockedIn == true || _todayStatus?.hasLeaveToday == true) {
        setState(() {
          _isCameraLoading = false;
        });
      } else {
        _initFrontCamera();
      }
    }
  }

  /// Ambil status absensi hari ini (apakah sudah Clock In / Izin)
  Future<void> _fetchTodayStatus() async {
    try {
      final status = await AttendanceService.getTodayStatus();
      if (mounted) {
        setState(() {
          _todayStatus = status;
        });
        if (status?.hasClockedIn == true || status?.hasLeaveToday == true) {
          await _disposeCamera();
        }
      }
    } catch (_) {}
  }

  /// Ambil semua lokasi kantor aktif untuk geofencing multi-lokasi
  Future<void> _fetchOfficeLocations() async {
    final offices = await AttendanceService.getActiveOfficeLocations();
    if (mounted) {
      setState(() {
        _officeLocations = offices;
        _updateClosestLocation();
      });
    }
  }

  /// Update lokasi terdekat berdasarkan posisi GPS saat ini
  void _updateClosestLocation() {
    if (_currentPosition == null || _officeLocations.isEmpty) {
      _officeLocation = _officeLocations.isNotEmpty ? _officeLocations.first : null;
      return;
    }

    OfficeLocation? closest;
    double shortestDist = double.infinity;

    for (final loc in _officeLocations) {
      final dist = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        loc.latitude,
        loc.longitude,
      );
      if (dist <= loc.radius && dist < shortestDist) {
        closest = loc;
        shortestDist = dist;
      }
    }

    // Jika tidak ada yang dalam radius, tampilkan yang paling dekat
    if (closest == null) {
      double minDist = double.infinity;
      for (final loc in _officeLocations) {
        final dist = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          loc.latitude,
          loc.longitude,
        );
        if (dist < minDist) {
          closest = loc;
          minDist = dist;
        }
      }
    }

    _officeLocation = closest;
  }

  double? get _distanceToOffice {
    if (_currentPosition == null || _officeLocation == null) return null;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _officeLocation!.latitude,
      _officeLocation!.longitude,
    );
  }

  /// Mematikan dan melepaskan resource kamera hardware
  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
        _isCameraLoading = false;
        _cameraErrorMessage = null;
      });
    }
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('Error disposing camera: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!(_todayStatus?.hasClockedIn ?? false) && !(_todayStatus?.hasLeaveToday ?? false)) {
        _initFrontCamera();
      }
    }
  }

  /// Inisialisasi kamera depan untuk selfie presensi real-time
  Future<void> _initFrontCamera() async {
    // Jangan inisialisasi jika pengguna sudah Clock In, sudah Izin, sedang menunggu review, atau ditolak
    if (_todayStatus?.hasClockedIn == true || _todayStatus?.hasLeaveToday == true || _todayStatus?.hasPendingReview == true || _todayStatus?.hasRejectedToday == true) {
      if (mounted) {
        setState(() {
          _isCameraLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isCameraLoading = true;
        _cameraErrorMessage = null;
      });
    }

    List<CameraDescription> cams = widget.cameras;

    // Jika daftar kamera kosong dari startup, coba deteksi ulang
    if (cams.isEmpty) {
      try {
        cams = await availableCameras();
      } catch (e) {
        debugPrint('availableCameras error: $e');
        if (mounted) {
          setState(() {
            _isCameraLoading = false;
            _cameraErrorMessage = 'Kamera tidak dapat dibaca. Pastikan izin kamera aktif dan tidak sedang digunakan oleh aplikasi lain.';
          });
        }
        return;
      }
    }

    if (cams.isEmpty) {
      if (mounted) {
        setState(() {
          _isCameraLoading = false;
          _cameraErrorMessage = 'Tidak ada perangkat kamera yang terdeteksi di perangkat Anda.';
        });
      }
      return;
    }

    // Cari kamera depan atau kamera pertama yang tersedia
    final frontCamera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );

    final controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      if (!mounted) return;
      // Jika ternyata sebelum kamera selesai diinit pengguna sudah clock in, batalkan
      if (_todayStatus?.hasClockedIn == true) {
        await controller.dispose();
        setState(() {
          _isCameraLoading = false;
        });
        return;
      }

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
        _isCameraLoading = false;
        _cameraErrorMessage = null;
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _isCameraLoading = false;
          _cameraErrorMessage = 'Gagal mengakses kamera: $e.\n\nTips: Tutup aplikasi lain yang sedang memakai webcam lalu klik Coba Lagi.';
        });
      }
    }
  }

  /// Pre-fetch lokasi GPS pengguna di latar belakang
  Future<void> _fetchQuickLocation() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _updateClosestLocation();
        });
      }
    } catch (_) {}
  }

  /// Alur Utama Presensi ():
  /// 1. Verifikasi kamera siap
  /// 2. Ambil foto wajah secara real-time
  /// 3. Ambil koordinat GPS akurat & validasi anti Fake-GPS
  /// 4. Kirim ke backend dengan type 'in' atau 'out'
  /// 5. Tampilkan pop up hasil presensi pada jam sekian
  /// 6. Perbarui state tombol harian
  Future<void> _handleTakeAttendance({required String type}) async {
    final isClockIn = type == 'in';
    final actionLabel = isClockIn ? 'Clock In' : 'Clock Out';

    if (isClockIn && (_cameraController == null || !_cameraController!.value.isInitialized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kamera belum siap, mohon tunggu sebentar.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = isClockIn
          ? 'Mengambil foto identifikasi wajah...'
          : 'Memproses Clock Out...';
    });

    try {
      // ──────────────────────────────────────────────
      // 1. Ambil foto wajah secara real-time HANYA untuk Clock In
      // ──────────────────────────────────────────────
      XFile? image;
      if (isClockIn) {
        image = await _cameraController!.takePicture();
      }

      // ──────────────────────────────────────────────
      // 2. Ambil koordinat GPS akurat & validasi Anti-Fake GPS
      // ──────────────────────────────────────────────
      setState(() {
        _loadingMessage = isClockIn
            ? 'Mendeteksi koordinat GPS akurat...'
            : 'Mendeteksi lokasi Clock Out...';
      });

      final Position position = await LocationService.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _updateClosestLocation();
      });

      // ──────────────────────────────────────────────
      // 3. Kirim multipart request ke backend
      // ──────────────────────────────────────────────
      setState(() {
        _loadingMessage = isClockIn
            ? 'Memverifikasi wajah & lokasi di server...'
            : 'Menyimpan Clock Out ke server...';
      });

      final result = await AttendanceService.submitAttendance(
        photoFile: image,
        latitude: position.latitude,
        longitude: position.longitude,
        type: type,
      );

      // Refresh status absensi hari ini dari server
      await _fetchTodayStatus();

      // Jika Clock In berhasil atau berstatus pending review, segera matikan kamera
      final isClockInFinished = isClockIn && (result.isSuccess || result.status == 'Clock In' || result.status == 'pending' || (_todayStatus?.hasClockedIn ?? false) || (_todayStatus?.hasPendingReview ?? false));
      if (isClockInFinished) {
        await _disposeCamera();
      }

      // ──────────────────────────────────────────────
      // 4. Tampilkan pop up hasil presensi
      // ──────────────────────────────────────────────
      if (mounted) {
        _showAttendanceResultDialog(result, type);
      }
    } on MockLocationDetectedException catch (mockError) {
      if (mounted) {
        _showErrorDialog(
          title: 'Lokasi Palsu Terdeteksi!',
          message: mockError.message,
          icon: Icons.security,
          color: Colors.red,
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog(
          title: '$actionLabel Gagal',
          message: e.toString().replaceAll('Exception: ', ''),
          icon: Icons.error_outline,
          color: Colors.orange,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
      }
    }
  }

  /// Pop-up Dialog Hasil Presensi Sesuai Permintaan
  void _showAttendanceResultDialog(AttendanceResult result, String type) {
    final isPresent = result.status == 'Clock In' || result.status == 'Clock Out' || result.isSuccess;
    final isPending = result.status == 'pending';
    final isOutOfRadius = result.status == 'Di Luar Radius';
    final isClockIn = type == 'in';
    final actionLabel = isClockIn ? 'Clock In' : 'Clock Out';

    // Waktu jam saat ini / jam dari response
    final displayTime = result.time ?? DateFormat('HH:mm').format(DateTime.now());

    Color primaryColor = isPresent
        ? const Color(0xFF10B981) // Emerald Green
        : isPending
            ? const Color(0xFFF59E0B) // Amber
            : isOutOfRadius
                ? const Color(0xFFEF4444)
                : const Color(0xFFEF4444);

    IconData statusIcon = isPresent
        ? Icons.check_circle_rounded
        : isPending
            ? Icons.hourglass_top_rounded
            : isOutOfRadius
                ? Icons.location_off_rounded
                : Icons.face_retouching_off_rounded;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lingkaran Icon Status
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: primaryColor, size: 44),
              ),
              const SizedBox(height: 16),

              // Judul Pop Up
              Text(
                isPresent
                    ? '$actionLabel Berhasil!'
                    : isPending
                        ? 'Menunggu Review Admin'
                        : '$actionLabel Gagal',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: isPresent ? const Color(0xFF0F172A) : primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // Pesan Waktu Presensi: "Clock In berhasil pada jam 08:30" atau Menunggu Review
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isPresent
                      ? const Color(0xFF10B981).withValues(alpha: 0.08)
                      : isPending
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.08)
                          : Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPending ? Icons.hourglass_bottom_rounded : Icons.access_time_filled_rounded,
                      size: 18,
                      color: isPresent
                          ? const Color(0xFF10B981)
                          : isPending
                              ? const Color(0xFFD97706)
                              : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isPresent
                            ? '$actionLabel berhasil pada jam $displayTime'
                            : isPending
                                ? 'Wajah tidak cocok (not match). Presensi pada jam $displayTime sedang menunggu persetujuan (review) admin.'
                                : result.message,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isPresent
                              ? const Color(0xFF065F46)
                              : isPending
                                  ? const Color(0xFFB45309)
                                  : Colors.red.shade800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Kartu Detail
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildPopupDetailRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Tanggal',
                      value: DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now()),
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildPopupDetailRow(
                      icon: Icons.verified_user_rounded,
                      label: 'Status',
                      value: result.status,
                      valueColor: primaryColor,
                    ),
                    if (result.locationName != null) ...[
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildPopupDetailRow(
                        icon: Icons.business_rounded,
                        label: 'Lokasi',
                        value: result.locationName!,
                      ),
                    ],
                    if (result.distance != null) ...[
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildPopupDetailRow(
                        icon: Icons.near_me_rounded,
                        label: 'Jarak GPS',
                        value: '${result.distance!.toStringAsFixed(0)} meter',
                      ),
                    ],
                    if (result.faceConfidence != null) ...[
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildPopupDetailRow(
                        icon: Icons.face_rounded,
                        label: 'Kecocokan Wajah',
                        value: '${result.faceConfidence!.toStringAsFixed(1)}%',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final isTokenExpired = result.message.toLowerCase().contains('kedaluwarsa') ||
                      result.message.toLowerCase().contains('login ulang');
                  if (isTokenExpired) {
                    await AuthService.logout();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => LoginScreen(cameras: widget.cameras)),
                      (route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  (result.message.toLowerCase().contains('kedaluwarsa') || result.message.toLowerCase().contains('login ulang'))
                      ? 'Login Ulang Sekarang'
                      : 'Mengerti',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPopupDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: valueColor ?? const Color(0xFF0F172A),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  void _showErrorDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasClockedIn = _todayStatus?.hasClockedIn ?? false;
    final hasClockedOut = _todayStatus?.hasClockedOut ?? false;
    final hasLeaveToday = _todayStatus?.hasLeaveToday ?? false;
    final hasPendingReview = _todayStatus?.hasPendingReview ?? false;
    final hasRejectedToday = _todayStatus?.hasRejectedToday ?? false;

    // Alur logika tombol:
    final bool canClockIn = !hasClockedIn && !hasLeaveToday && !hasPendingReview && !hasRejectedToday && !_isLoading;
    final bool canClockOut = hasClockedIn && !hasClockedOut && !hasLeaveToday && !_isLoading;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: LiquidGlassAppBar(
        title: 'Presensi Wajah & GPS',
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Perbarui Status',
            onPressed: () async {
              await _fetchTodayStatus();
              _fetchQuickLocation();
              if (!(_todayStatus?.hasClockedIn ?? false) &&
                  !(_todayStatus?.hasLeaveToday ?? false) &&
                  !(_todayStatus?.hasPendingReview ?? false) &&
                  !(_todayStatus?.hasRejectedToday ?? false) &&
                  _cameraController == null) {
                _initFrontCamera();
              }
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ─── 1. BACKGROUND LAYER ───
          // Sebelum Clock In & belum Izin/Pending/Ditolak dengan kamera aktif: FULL KAMERA
          if (!hasClockedIn && !hasLeaveToday && !hasPendingReview && !hasRejectedToday && _isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized) ...[
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
          ] else ...[
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
          ],
          // ─── 2. CONTENT LAYER SETELAH IZIN / CLOCK IN / ERROR / LOADING ───
          if (hasLeaveToday)
            // Tampilan Status jika user sudah mengajukan izin hari ini
            Positioned.fill(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 68,
              bottom: 185,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.event_busy_rounded,
                            color: Color(0xFFF59E0B),
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Anda Mengajukan Izin',
                          style: TextStyle(
                            color: Color(0xFF242721),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.assignment_rounded, size: 15, color: Color(0xFFD97706)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Alasan: ${_todayStatus?.leaveReason ?? "Izin"}',
                                  style: const TextStyle(color: Color(0xFFB45309), fontSize: 13, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.block_rounded, size: 16, color: Color(0xFFDC2626)),
                              SizedBox(width: 6),
                              Text(
                                'Clock In & Clock Out Dinonaktifkan',
                                style: TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Karena Anda telah mengajukan izin hari ini, presensi kehadiran dinonaktifkan. Anda hanya dapat mengedit izin dari menu Izin.',
                          style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.40),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (hasClockedIn)
            // Tampilan Status setelah Clock In: Kamera Dimatikan
            Positioned.fill(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 68,
              bottom: 185,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: (hasClockedOut ? const Color(0xFF10B981) : const Color(0xFF0284C7)).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            hasClockedOut ? Icons.task_alt_rounded : Icons.verified_user_rounded,
                            color: hasClockedOut ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          hasClockedOut ? 'Presensi Hari Ini Selesai' : 'Clock In Berhasil',
                          style: const TextStyle(
                            color: Color(0xFF242721),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF365C4A).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.access_time_rounded, size: 15, color: Color(0xFF365C4A)),
                              const SizedBox(width: 6),
                              Text(
                                hasClockedOut
                                    ? 'In: ${_todayStatus?.clockInTime ?? "-"}  •  Out: ${_todayStatus?.clockOutTime ?? "-"}'
                                    : 'Tercatat pukul ${_todayStatus?.clockInTime ?? "-"}',
                                style: const TextStyle(color: Color(0xFF242721), fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF64748B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_off_rounded, size: 16, color: Color(0xFF64748B)),
                              SizedBox(width: 6),
                              Text(
                                'Kamera Dinonaktifkan',
                                style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          hasClockedOut
                              ? 'Seluruh rangkaian presensi hari ini telah diselesaikan.'
                              : 'Kamera dimatikan setelah Clock In berhasil. Untuk Clock Out saat jam pulang, Anda hanya memerlukan verifikasi lokasi GPS.',
                          style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.40),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (hasPendingReview)
            // Tampilan Status saat menunggu review approval admin (Wajah Not Match)
            Positioned.fill(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 68,
              bottom: 185,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.hourglass_top_rounded,
                            color: Color(0xFFF59E0B),
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Menunggu Review Admin',
                          style: TextStyle(
                            color: Color(0xFF242721),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.access_time_rounded, size: 15, color: Color(0xFFD97706)),
                              const SizedBox(width: 6),
                              Text(
                                'Clock In diajukan pukul ${_todayStatus?.pendingTime ?? "-"}',
                                style: const TextStyle(color: Color(0xFFB45309), fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.face_retouching_off_rounded, size: 16, color: Color(0xFFD97706)),
                              SizedBox(width: 6),
                              Text(
                                'Verifikasi Wajah Not Match',
                                style: TextStyle(color: Color(0xFFB45309), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Data presensi Anda sedang diverifikasi secara manual oleh admin. Jika disetujui, jam masuk Anda otomatis tercatat sesuai waktu saat pengambilan foto di tanggal ini.',
                          style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.40),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (hasRejectedToday)
            // Tampilan Status saat presensi ditolak admin (Terhitung Alpha)
            Positioned.fill(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 68,
              bottom: 185,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.cancel_rounded,
                            color: Color(0xFFEF4444),
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Presensi Ditolak (Alpha)',
                          style: TextStyle(
                            color: Color(0xFF242721),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.report_problem_rounded, size: 15, color: Color(0xFFDC2626)),
                              SizedBox(width: 6),
                              Text(
                                'Status Hari Ini: Alpha',
                                style: TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Presensi Anda hari ini telah ditolak oleh admin karena verifikasi wajah tidak cocok. Hari ini terhitung Alpha dan tidak masuk ke riwayat log absen.',
                          style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.40),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (_cameraErrorMessage != null)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded, color: Color(0xFFF59E0B), size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Kamera Belum Terhubung',
                      style: TextStyle(color: Color(0xFF242721), fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _cameraErrorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _initFrontCamera,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF365C4A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Coba Sambungkan Lagi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          else
            Center(
              child: _isCameraLoading
                  ? const CircularProgressIndicator(color: Color(0xFF365C4A))
                  : const SizedBox.shrink(),
            ),

          // 2. Oval Face Guide Overlay (Frame Wajah Real-Time hanya tampil jika belum Clock In)
          if (!hasClockedIn && _isCameraInitialized && _cameraController != null)
            CustomPaint(
              painter: OvalHoleOverlayPainter(),
              child: Container(),
            ),

          // 3. Top Info Pill: Status Lokasi GPS & Geofencing Office Proximity
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _currentPosition != null ? Icons.my_location : Icons.location_searching,
                        color: _currentPosition != null ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentPosition != null
                              ? 'GPS: ${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}'
                              : 'Mencari sinyal GPS akurat...',
                          style: const TextStyle(color: Color(0xFF242721), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (_officeLocation != null && _currentPosition != null && _distanceToOffice != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _distanceToOffice! <= _officeLocation!.radius
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                          color: _distanceToOffice! <= _officeLocation!.radius
                              ? const Color(0xFF10B981)
                              : const Color(0xFFD97706),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${_officeLocation!.name}: ${_distanceToOffice!.toStringAsFixed(0)}m / ${_officeLocation!.radius}m (${_distanceToOffice! <= _officeLocation!.radius ? "Dalam Radius" : "Di Luar Radius"})',
                            style: TextStyle(
                              color: _distanceToOffice! <= _officeLocation!.radius
                                  ? const Color(0xFF047857)
                                  : const Color(0xFFB45309),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 4. Bottom Action & Instruction Guide
          Positioned(
            bottom: 86,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Instruction Guide Text (hanya tampil sebelum Clock In agar tidak menutupi kartu status di tengah)
                if (!hasClockedIn) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Posisikan wajah Anda tepat di dalam bingkai oval',
                      style: TextStyle(color: Color(0xFF242721), fontSize: 12, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // 5. Bottom Action: Pilihan "Clock In" dan "Clock Out"
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // ─── TOMBOL CLOCK IN (Absen Masuk) ───
                      Expanded(
                        child: _buildAttendanceButton(
                          title: 'Clock In',
                          subtitle: hasLeaveToday
                              ? 'Sedang Izin'
                              : (hasClockedIn
                                  ? 'Pukul ${_todayStatus?.clockInTime ?? "Selesai"}'
                                  : (hasPendingReview
                                      ? 'Menunggu Review'
                                      : (hasRejectedToday ? 'Ditolak (Alpha)' : 'Absen Masuk'))),
                          icon: hasLeaveToday
                              ? Icons.event_busy_rounded
                              : (hasClockedIn
                                  ? Icons.check_circle_rounded
                                  : (hasPendingReview
                                      ? Icons.hourglass_top_rounded
                                      : (hasRejectedToday ? Icons.cancel_rounded : Icons.login_rounded))),
                          isEnabled: canClockIn,
                          activeColor: const Color(0xFF10B981), // Emerald Green
                          onPressed: canClockIn
                              ? () => _handleTakeAttendance(type: 'in')
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // ─── TOMBOL CLOCK OUT (Absen Keluar) ───
                      Expanded(
                        child: _buildAttendanceButton(
                          title: 'Clock Out',
                          subtitle: hasLeaveToday
                              ? 'Sedang Izin'
                              : (hasClockedOut
                                  ? 'Pukul ${_todayStatus?.clockOutTime ?? "Selesai"}'
                                  : (hasClockedIn ? 'Absen Keluar' : 'Belum Clock In')),
                          icon: hasLeaveToday
                              ? Icons.event_busy_rounded
                              : (hasClockedOut ? Icons.check_circle_rounded : Icons.logout_rounded),
                          isEnabled: canClockOut,
                          activeColor: const Color(0xFFF97316), // Vibrant Orange
                          onPressed: canClockOut
                              ? () => _handleTakeAttendance(type: 'out')
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 6. Loading Modal Overlay saat proses berlangsung
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF365C4A)),
                      const SizedBox(height: 18),
                      Text(
                        _loadingMessage.isNotEmpty ? _loadingMessage : 'Memproses presensi...',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Helper Widget Pembuat Tombol Clock In & Clock Out
  Widget _buildAttendanceButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isEnabled,
    required Color activeColor,
    required VoidCallback? onPressed,
  }) {
    final Color bgColor = isEnabled ? activeColor : const Color(0xFFE2E8F0);
    final Color textColor = isEnabled ? Colors.white : const Color(0xFF94A3B8);
    final Color iconColor = isEnabled ? Colors.white : const Color(0xFF94A3B8);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onPressed : null,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled ? Colors.white24 : Colors.transparent,
              width: 1,
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: isEnabled ? Colors.white.withValues(alpha: 0.88) : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom Painter untuk membuat overlay gelap dengan lubang oval di tengah
class OvalHoleOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.40)
      ..style = PaintingStyle.fill;

    final ovalWidth = size.width * 0.72;
    final ovalHeight = size.height * 0.46;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: ovalWidth,
      height: ovalHeight,
    );

    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(ovalRect);
    final combinedPath = Path.combine(PathOperation.difference, backgroundPath, ovalPath);

    canvas.drawPath(combinedPath, backgroundPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF10B981) // Emerald Green border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
