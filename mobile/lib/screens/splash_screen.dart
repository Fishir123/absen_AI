import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:camera/camera.dart';

import 'login_screen.dart';
import 'welcome_screen.dart';
import '../services/auth_service.dart';

/// Splash screen pembuka aplikasi yang memutar video animasi selama 2 detik
/// sebelum berpindah ke halaman utama (jika sudah login) atau halaman login.
class SplashScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const SplashScreen({super.key, required this.cameras});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _videoController;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // Sembunyikan status bar & navigation bar untuk efek immersive
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.asset('assets/video/splash_video.mp4');

      await _videoController!.initialize();
      _videoController!.setLooping(false);
      _videoController!.setVolume(0); // Tidak ada suara

      if (mounted) {
        setState(() {});
        _videoController!.play();

        // Dengarkan saat video selesai diputar
        _videoController!.addListener(_onVideoUpdate);

        // Fallback timer: navigasi setelah 2.5 detik jika video belum selesai
        Future.delayed(const Duration(milliseconds: 2500), () {
          _navigateToNextScreen();
        });
      }
    } catch (e) {
      debugPrint('Gagal memuat video splash: $e');
      // Jika video gagal dimuat, tunggu 2 detik lalu lanjut
      await Future.delayed(const Duration(seconds: 2));
      _navigateToNextScreen();
    }
  }

  void _onVideoUpdate() {
    if (_videoController == null) return;

    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;

    // Navigasi saat video selesai diputar
    if (position >= duration && duration > Duration.zero) {
      _navigateToNextScreen();
    }
  }

  Future<void> _navigateToNextScreen() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    // Tampilkan kembali system UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    // Cek status login
    final bool loggedIn = await AuthService.isLoggedIn();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          if (loggedIn) {
            return WelcomeScreen(cameras: widget.cameras);
          } else {
            return LoginScreen(cameras: widget.cameras);
          }
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Animasi fade-in yang halus saat transisi dari splash ke halaman berikutnya
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _videoController != null && _videoController!.value.isInitialized
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController!.value.size.width,
                    height: _videoController!.value.size.height,
                    child: VideoPlayer(_videoController!),
                  ),
                ),
              )
            : // Fallback: tampilkan logo saat video belum siap
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/icon/app_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
