import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../main.dart';

/// Halaman Selamat Datang minimalis setelah login berhasil pada mobile.
/// Menampilkan logo berukuran proporsional, tulisan selamat datang, dan tombol ke beranda
/// langsung di atas wallpaper background tanpa kotak kartu putih.
class WelcomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  final Map<String, dynamic>? initialUser;

  const WelcomeScreen({
    super.key,
    required this.cameras,
    this.initialUser,
  });

  void _navigateToHome(BuildContext context) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MainNavigationWrapper(cameras: cameras),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Wallpaper penuh
          Image.asset(
            'lib/asset/baground/BG.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFF365C4A),
            ),
          ),

          // Lapisan tipis transparan agar teks tetap jelas dan kontras
          Container(
            color: Colors.black.withValues(alpha: 0.15),
          ),

          // Konten Utama di Tengah Layar (Tanpa background card putih)
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Logo Aplikasi (Ukuran lebih besar)
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(100),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: Image.asset(
                          'lib/asset/icon/poca.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.shield_outlined,
                            color: Color(0xFF365C4A),
                            size: 58,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 2. Tulisan Selamat Datang
                    const Text(
                      'Selamat Datang',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            offset: Offset(0, 2),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // 3. Tombol Ke Beranda
                    SizedBox(
                      width: 200,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => _navigateToHome(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF365C4A),
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shadowColor: Colors.black.withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Ke Beranda',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 19,
                            ),
                          ],
                        ),
                      ),
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
}
