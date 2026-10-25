import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_constants.dart';

class OfficeLocation {
  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final int radius;

  OfficeLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
  });

  factory OfficeLocation.fromJson(Map<String, dynamic> json) {
    return OfficeLocation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? 'Kantor',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radius: (json['radius'] as num?)?.toInt() ?? 100,
    );
  }
}

class TodayAttendanceStatus {
  final bool hasClockedIn;
  final bool hasClockedOut;
  final String? clockInTime;
  final String? clockOutTime;
  final bool hasPendingReview;
  final String? pendingTime;
  final bool hasRejectedToday;
  final bool hasLeaveToday;
  final String? leaveReason;
  final String? leaveStatus;
  final Map<String, dynamic>? todayLeave;

  TodayAttendanceStatus({
    required this.hasClockedIn,
    required this.hasClockedOut,
    this.clockInTime,
    this.clockOutTime,
    this.hasPendingReview = false,
    this.pendingTime,
    this.hasRejectedToday = false,
    this.hasLeaveToday = false,
    this.leaveReason,
    this.leaveStatus,
    this.todayLeave,
  });

  factory TodayAttendanceStatus.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final clockIn = data['clockIn'] as Map<String, dynamic>?;
    final clockOut = data['clockOut'] as Map<String, dynamic>?;
    final pending = data['pending'] as Map<String, dynamic>?;
    final todayLeave = data['todayLeave'] as Map<String, dynamic>?;

    String? formatTime(Map<String, dynamic>? record) {
      if (record == null) return null;
      if (record['time'] != null && record['time'].toString().isNotEmpty) {
        return record['time'].toString();
      }
      final dateStr = record['created_at']?.toString();
      if (dateStr == null) return null;
      try {
        final dt = DateTime.parse(dateStr).toLocal();
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        return '$h:$m';
      } catch (_) {
        return null;
      }
    }

    return TodayAttendanceStatus(
      hasClockedIn: data['hasClockedIn'] == true,
      hasClockedOut: data['hasClockedOut'] == true,
      clockInTime: formatTime(clockIn),
      clockOutTime: formatTime(clockOut),
      hasPendingReview: data['hasPendingReview'] == true || pending != null,
      pendingTime: formatTime(pending),
      hasRejectedToday: data['hasRejectedToday'] == true,
      hasLeaveToday: data['hasLeaveToday'] == true,
      leaveReason: todayLeave?['reason']?.toString(),
      leaveStatus: todayLeave?['status']?.toString(),
      todayLeave: todayLeave,
    );
  }
}

class AttendanceResult {
  final bool isSuccess;
  final String status;
  final String message;
  final String? type;
  final String? time;
  final double? distance;
  final int? radius;
  final double? faceConfidence;
  final String? timestamp;
  final String? locationName;

  AttendanceResult({
    required this.isSuccess,
    required this.status,
    required this.message,
    this.type,
    this.time,
    this.distance,
    this.radius,
    this.faceConfidence,
    this.timestamp,
    this.locationName,
  });

  factory AttendanceResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return AttendanceResult(
      isSuccess: json['success'] == true,
      status: data['status']?.toString() ?? (json['success'] == true ? 'Clock In' : 'Gagal'),
      message: json['message']?.toString() ?? 'Proses presensi selesai.',
      type: data['type']?.toString(),
      time: data['time']?.toString(),
      distance: data['distance'] != null ? (data['distance'] as num).toDouble() : null,
      radius: data['radius'] != null ? (data['radius'] as num).toInt() : null,
      faceConfidence: data['face_confidence'] != null ? (data['face_confidence'] as num).toDouble() : null,
      timestamp: data['timestamp']?.toString(),
      locationName: data['location']?.toString(),
    );
  }
}

class AttendanceStats {
  final int ciAndCo;
  final int ciNotCo;
  final int izin;
  final int alpha;
  final String? startDate;
  final String? endDate;

  const AttendanceStats({
    this.ciAndCo = 0,
    this.ciNotCo = 0,
    this.izin = 0,
    this.alpha = 0,
    this.startDate,
    this.endDate,
  });

  int get total => ciAndCo + ciNotCo + izin + alpha;
  int get maxVal {
    final vals = [ciAndCo, ciNotCo, izin, alpha];
    vals.sort();
    return vals.last;
  }

  factory AttendanceStats.fromJson(Map<String, dynamic> json) {
    return AttendanceStats(
      ciAndCo: (json['ci_and_co'] as num?)?.toInt() ?? 0,
      ciNotCo: (json['ci_not_co'] as num?)?.toInt() ?? 0,
      izin: (json['izin'] as num?)?.toInt() ?? 0,
      alpha: (json['alpha'] as num?)?.toInt() ?? 0,
      startDate: json['start_date']?.toString(),
      endDate: json['end_date']?.toString(),
    );
  }
}

class AttendanceService {
  /// Mengambil auth token JWT dari SharedPreferences lokal
  static Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  /// Mengambil data semua lokasi kantor/kampus aktif untuk geofencing multi-lokasi
  /// Endpoint: GET /api/locations/active
  static Future<List<OfficeLocation>> getActiveOfficeLocations() async {
    try {
      final uri = Uri.parse(ApiConstants.activeLocationUrl);
      final token = await _getAuthToken();

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['data'] != null) {
          final dataList = decoded['data'] as List<dynamic>;
          return dataList
              .map((item) => OfficeLocation.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Backward compatibility: mengambil lokasi aktif pertama
  static Future<OfficeLocation?> getActiveOfficeLocation() async {
    final locations = await getActiveOfficeLocations();
    return locations.isNotEmpty ? locations.first : null;
  }

  /// Mengambil status Clock In & Clock Out pengguna untuk hari ini
  /// Endpoint: GET /api/attendance/today
  static Future<TodayAttendanceStatus?> getTodayStatus() async {
    try {
      final uri = Uri.parse(ApiConstants.todayAttendanceUrl);
      final token = await _getAuthToken();

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          return TodayAttendanceStatus.fromJson(decoded);
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  /// Mengambil data permohonan izin hari ini milik user
  /// Endpoint: GET /api/leaves/today
  static Future<Map<String, dynamic>?> getTodayLeave() async {
    try {
      final uri = Uri.parse(ApiConstants.todayLeaveUrl);
      final token = await _getAuthToken();

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['data'] != null) {
          return decoded['data'] as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Mengirim data presensi multipart (foto wajah + latitude + longitude + type) ke Express.js
  /// Endpoint: POST /api/attendance
  /// Menggunakan XFile, fromBytes & MediaType('image', 'jpeg') agar kompatibel 100% dengan Web & Mobile.
  static Future<AttendanceResult> submitAttendance({
    XFile? photoFile,
    required double latitude,
    required double longitude,
    String type = 'in',
  }) async {
    final uri = Uri.parse(ApiConstants.submitAttendanceUrl);
    final request = http.MultipartRequest('POST', uri);

    // 1. Tambahkan Authorization Bearer Token
    final token = await _getAuthToken();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // 2. Tambahkan Text Fields koordinat GPS & type ('in' / 'out')
    request.fields['latitude'] = latitude.toString();
    request.fields['longitude'] = longitude.toString();
    request.fields['type'] = type;

    // 3. Tambahkan File Foto Wajah (wajib untuk Clock In, tanpa foto untuk Clock Out)
    if (photoFile != null) {
      final bytes = await photoFile.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: photoFile.name.isNotEmpty ? photoFile.name : 'attendance_face.jpg',
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);
    }

    // 4. Kirim Request
    try {
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 35),
        onTimeout: () {
          throw Exception('Koneksi timeout. Server tidak merespon dalam 35 detik.');
        },
      );

      final response = await http.Response.fromStream(streamedResponse);
      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return AttendanceResult.fromJson(responseData);
      } else {
        // Tangani error terstruktur dari backend
        final errorMsg = responseData['message'] ?? 'Gagal melakukan absensi (Kode: ${response.statusCode})';
        return AttendanceResult(
          isSuccess: false,
          status: responseData['data']?['status'] ?? 'Gagal',
          message: errorMsg,
          distance: responseData['data']?['distance'] != null
              ? (responseData['data']['distance'] as num).toDouble()
              : null,
          radius: responseData['data']?['radius'] != null
              ? (responseData['data']['radius'] as num).toInt()
              : null,
          faceConfidence: responseData['data']?['face_confidence'] != null
              ? (responseData['data']['face_confidence'] as num).toDouble()
              : null,
        );
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Terjadi kesalahan saat mengirim absensi: $e');
    }
  }

  /// Mengambil riwayat absensi pengguna yang sedang login dengan filter tanggal/bulan/tahun
  /// Endpoint: GET /api/attendance/history
  static Future<List<Map<String, dynamic>>> getMyHistory({
    int page = 1,
    int limit = 100,
    String? date,
    int? month,
    int? year,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (date != null && date.isNotEmpty) queryParams['date'] = date;
    if (month != null) queryParams['month'] = month.toString();
    if (year != null) queryParams['year'] = year.toString();

    final uri = Uri.parse(ApiConstants.attendanceHistoryUrl).replace(queryParameters: queryParams);
    final token = await _getAuthToken();

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final List<dynamic> list = decoded['data'] ?? [];
      return list.cast<Map<String, dynamic>>();
    } else {
      final decoded = jsonDecode(response.body);
      throw Exception(decoded['message'] ?? 'Gagal memuat riwayat presensi: ${response.statusCode}');
    }
  }

  /// Mengambil data statistik absensi untuk diagram batang
  /// Endpoint: GET /api/attendance/statistics
  static Future<AttendanceStats> getMyStatistics({
    String? date,
    int? month,
    int? year,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (date != null && date.isNotEmpty) queryParams['date'] = date;
      if (month != null) queryParams['month'] = month.toString();
      if (year != null) queryParams['year'] = year.toString();

      final uri = Uri.parse(ApiConstants.attendanceStatisticsUrl).replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      final token = await _getAuthToken();

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['data'] != null) {
          return AttendanceStats.fromJson(decoded['data'] as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    return const AttendanceStats();
  }
}
