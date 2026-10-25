import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_constants.dart';

class AuthService {
  /// Melakukan login ke backend Express.js dengan Email/NIP dan Password
  /// Endpoint: POST /api/auth/login
  static Future<Map<String, dynamic>> login({
    required String identifier, // Email atau NIP
    required String password,
  }) async {
    final uri = Uri.parse(ApiConstants.loginUrl);

    try {
      final trimmed = identifier.trim();
      final body = jsonEncode({
        'identifier': trimmed,
        'email': trimmed,
        'nip': trimmed,
        'password': password,
      });

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Client': 'mobile',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final token = data['token'] ?? data['data']?['token'];
        final user = data['user'] ?? data['data']?['user'] ?? {};

        // Simpan token JWT dan identitas user ke SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (token != null) {
          await prefs.setString('auth_token', token.toString());
        }
        await prefs.setInt('user_id', (user['id'] as num?)?.toInt() ?? 0);
        await prefs.setString('user_name', user['name']?.toString() ?? 'Karyawan');
        await prefs.setString('user_nip', user['nip']?.toString() ?? identifier);
        await prefs.setString('user_email', user['email']?.toString() ?? '');
        await prefs.setString('user_role', user['role']?.toString() ?? 'user');
        await prefs.setString('user_divisi', user['divisi']?.toString() ?? '');
        if (user['face_photo'] != null) {
          await prefs.setString('user_face_photo', user['face_photo'].toString());
        }

        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Login gagal. Periksa kembali NIP/Email dan kata sandi Anda.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal menghubungi server (${ApiConstants.baseUrl}): $e',
      };
    }
  }

  /// Cek apakah user sudah login sebelumnya
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return token != null && token.isNotEmpty;
  }

  /// Mengambil token aktif
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  /// Mengambil data user yang tersimpan di lokal
  static Future<Map<String, String>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString('user_name') ?? 'Karyawan',
      'nip': prefs.getString('user_nip') ?? '-',
      'email': prefs.getString('user_email') ?? '-',
      'role': prefs.getString('user_role') ?? 'user',
      'divisi': prefs.getString('user_divisi') ?? '',
      'face_photo': prefs.getString('user_face_photo') ?? '',
    };
  }

  /// Refresh profil user dari server: GET /api/auth/profile
  static Future<Map<String, dynamic>?> fetchProfile() async {
    try {
      final token = await getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse(ApiConstants.profileUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final user = decoded['data'] as Map<String, dynamic>?;
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_name', user['name']?.toString() ?? 'Karyawan');
          await prefs.setString('user_nip', user['nip']?.toString() ?? '');
          await prefs.setString('user_email', user['email']?.toString() ?? '');
          await prefs.setString('user_role', user['role']?.toString() ?? 'user');
          await prefs.setString('user_divisi', user['divisi']?.toString() ?? '');
          if (user['face_photo'] != null) {
            await prefs.setString('user_face_photo', user['face_photo'].toString());
          }
          return user;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Mengunggah foto master wajah user sendiri: POST /api/auth/face
  static Future<Map<String, dynamic>> uploadMasterFace(XFile photoFile) async {
    final uri = Uri.parse(ApiConstants.uploadFaceUrl);
    final request = http.MultipartRequest('POST', uri);

    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final bytes = await photoFile.readAsBytes();
    final multipartFile = http.MultipartFile.fromBytes(
      'face_photo',
      bytes,
      filename: photoFile.name.isNotEmpty ? photoFile.name : 'master_face.jpg',
      contentType: MediaType('image', 'jpeg'),
    );
    request.files.add(multipartFile);

    try {
      final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamedResponse);
      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200 && decoded['success'] == true) {
        final facePhoto = decoded['data']?['face_photo'];
        if (facePhoto != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_face_photo', facePhoto.toString());
        }
        return {'success': true, 'message': decoded['message'] ?? 'Foto wajah berhasil disimpan.'};
      } else {
        return {'success': false, 'message': decoded['message'] ?? 'Gagal mengunggah foto wajah.'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Gagal menghubungi server: $e'};
    }
  }

  /// Logout dan bersihkan data sesi (namun tetap pertahankan custom server URL)
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString('custom_base_url');
    await prefs.clear();
    if (customUrl != null) {
      await prefs.setString('custom_base_url', customUrl);
    }
  }
}
