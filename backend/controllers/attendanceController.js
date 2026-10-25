const path = require('path');
const fs = require('fs');
const axios = require('axios');
const FormData = require('form-data');
const Attendance = require('../models/Attendance');
const User = require('../models/User');
const Location = require('../models/Location');
const haversine = require('../utils/haversine');
const { UPLOAD_DIR_FACES } = require('../config/multer');
const { compareFaces } = require('../utils/faceRecognition');

// URL Microservice AI Face Recognition (self-hosted)
const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://127.0.0.1:8000';

/**
 * AttendanceController - Menangani seluruh logika absensi.
 */
const attendanceController = {
  // ════════════════════════════════════════════════════════════════
  // POST /api/attendance/clock-in
  // Proses Clock In: geofencing → face recognition via AI → simpan log
  //
  // Flow:
  //   1. Ambil user_id, latitude, longitude, location_id dari body & file foto dari Multer
  //   2. Ambil data lokasi dari tabel locations berdasarkan location_id
  //   3. Hitung jarak Haversine → jika > radius → INSERT "Di Luar Radius"
  //   4. Ambil face_photo master dari tabel users
  //   5. Kirim captured_image + master_image ke AI service /compare
  //   6. Jika AI gagal deteksi wajah → INSERT "Gagal Verifikasi Wajah"
  //   7. Jika verified = false → INSERT "Wajah Tidak Cocok"
  //   8. Jika lolos → INSERT "Clock In" dengan distance, confidence, dsb.
  // ════════════════════════════════════════════════════════════════
  clockIn: async (req, res, next) => {
    try {
      const userId = req.user.id;

      // ──────────────────────────────────────────────
      // 1. Ambil data dari request
      // ──────────────────────────────────────────────
      const { latitude, longitude, location_id } = req.body;

      if (!req.file) {
        return res.status(400).json({
          success: false,
          message: 'Foto wajah wajib diunggah saat Clock In.',
        });
      }

      if (!latitude || !longitude) {
        fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Latitude dan longitude wajib disertakan.',
        });
      }

      if (!location_id) {
        fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Location ID wajib disertakan.',
        });
      }

      const lat = parseFloat(latitude);
      const lng = parseFloat(longitude);
      const locId = parseInt(location_id, 10);

      if (isNaN(lat) || isNaN(lng)) {
        fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Latitude dan longitude harus berupa angka yang valid.',
        });
      }

      const photoRelativePath = `attendance/${req.file.filename}`;

      // ──────────────────────────────────────────────
      // 2. Ambil data lokasi dari tabel locations
      // ──────────────────────────────────────────────
      const location = await Location.findById(locId);

      if (!location) {
        fs.unlinkSync(req.file.path);
        return res.status(404).json({
          success: false,
          message: 'Lokasi tidak ditemukan. Hubungi admin.',
        });
      }

      // ──────────────────────────────────────────────
      // 3. Hitung jarak Haversine
      // ──────────────────────────────────────────────
      const distance = haversine(lat, lng, location.latitude, location.longitude);
      const radius = location.radius || parseInt(process.env.DEFAULT_RADIUS_METERS, 10) || 100;

      // ──────────────────────────────────────────────
      // 3a. Jika di luar radius → simpan log & return error
      // ──────────────────────────────────────────────
      if (distance > radius) {
        const attendanceLog = await Attendance.create({
          user_id: userId,
          latitude: lat,
          longitude: lng,
          distance,
          face_confidence: null,
          status: 'Di Luar Radius',
          photo: photoRelativePath,
          location_id: locId,
        });

        return res.status(400).json({
          success: false,
          message: `Anda berada di luar radius. Jarak Anda: ${distance} meter, radius maksimum: ${radius} meter.`,
          data: {
            id: attendanceLog.id,
            status: 'Di Luar Radius',
            distance,
            radius,
            timestamp: new Date().toISOString(),
          },
        });
      }

      // ──────────────────────────────────────────────
      // 4. Ambil foto master wajah dari tabel users
      // ──────────────────────────────────────────────
      const facePhoto = await User.getFacePhoto(userId);

      if (!facePhoto) {
        fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Foto master wajah belum terdaftar. Hubungi admin untuk mendaftarkan foto wajah Anda.',
        });
      }

      // Path absolut ke foto master (disimpan di uploads/<face_photo>)
      // Strip prefix 'uploads/' jika sudah ada di database untuk mencegah double path
      const cleanFacePhoto = facePhoto.replace(/^uploads[\/\\]/, '');
      const masterPhotoPath = path.join(__dirname, '..', 'uploads', cleanFacePhoto);

      if (!fs.existsSync(masterPhotoPath)) {
        fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'File foto master wajah tidak ditemukan di server. Hubungi admin.',
        });
      }

      // ──────────────────────────────────────────────
      // 5. Kirim ke Microservice AI untuk verifikasi wajah
      // ──────────────────────────────────────────────
      let aiResult;

      try {
        const formData = new FormData();
        formData.append('captured_image', fs.createReadStream(req.file.path));
        formData.append('master_image', fs.createReadStream(masterPhotoPath));

        const aiResponse = await axios.post(`${AI_SERVICE_URL}/compare`, formData, {
          headers: {
            ...formData.getHeaders(),
          },
          timeout: 60000, // 60 detik timeout (model inference bisa lambat)
          // Terima semua status code agar kita bisa handle response 400 dari AI
          validateStatus: (status) => status < 500,
        });

        aiResult = aiResponse.data;
      } catch (aiError) {
        // ──────────────────────────────────────────────
        // 6. Jika AI service tidak bisa dihubungi / error
        // ──────────────────────────────────────────────
        console.error('❌ Gagal menghubungi AI Service:', aiError.message);

        const attendanceLog = await Attendance.create({
          user_id: userId,
          latitude: lat,
          longitude: lng,
          distance,
          face_confidence: null,
          status: 'Gagal Verifikasi Wajah',
          photo: photoRelativePath,
          location_id: locId,
        });

        return res.status(500).json({
          success: false,
          message: 'Gagal menghubungi layanan verifikasi wajah. Silakan coba lagi.',
          data: {
            id: attendanceLog.id,
            status: 'Gagal Verifikasi Wajah',
            timestamp: new Date().toISOString(),
          },
        });
      }

      // ──────────────────────────────────────────────
      // 6. Jika AI gagal mendeteksi wajah pada foto
      // ──────────────────────────────────────────────
      if (!aiResult.success) {
        const attendanceLog = await Attendance.create({
          user_id: userId,
          latitude: lat,
          longitude: lng,
          distance,
          face_confidence: null,
          status: 'Gagal Verifikasi Wajah',
          photo: photoRelativePath,
          location_id: locId,
        });

        return res.status(400).json({
          success: false,
          message: aiResult.error || 'Gagal memverifikasi wajah. Pastikan foto menampilkan wajah dengan jelas.',
          data: {
            id: attendanceLog.id,
            status: 'Gagal Verifikasi Wajah',
            timestamp: new Date().toISOString(),
          },
        });
      }

      // ──────────────────────────────────────────────
      // 7. Jika wajah tidak cocok (berdasarkan keputusan AI Service)
      // ──────────────────────────────────────────────
      if (!aiResult.verified) {
        const attendanceLog = await Attendance.create({
          user_id: userId,
          latitude: lat,
          longitude: lng,
          distance,
          face_confidence: aiResult.confidence,
          status: 'Wajah Tidak Cocok',
          photo: photoRelativePath,
          location_id: locId,
        });

        return res.status(400).json({
          success: false,
          message: `Wajah tidak cocok. Confidence: ${aiResult.confidence}%.`,
          data: {
            id: attendanceLog.id,
            status: 'Wajah Tidak Cocok',
            face_confidence: aiResult.confidence,
            distance,
            timestamp: new Date().toISOString(),
          },
        });
      }

      // ──────────────────────────────────────────────
      // 8. Lolos verifikasi → simpan sebagai Clock In
      // ──────────────────────────────────────────────
      const attendanceLog = await Attendance.create({
        user_id: userId,
        latitude: lat,
        longitude: lng,
        distance,
        face_confidence: aiResult.confidence,
        status: 'Clock In',
        photo: photoRelativePath,
        location_id: locId,
      });

      const now = new Date();
      const timeStr = now
        .toLocaleTimeString('id-ID', {
          hour: '2-digit',
          minute: '2-digit',
          timeZone: 'Asia/Jakarta',
        })
        .replace('.', ':');

      return res.status(200).json({
        success: true,
        message: `Clock In berhasil pada pukul ${timeStr}.`,
        data: {
          id: attendanceLog.id,
          status: 'Clock In',
          time: timeStr,
          distance,
          radius,
          face_confidence: aiResult.confidence,
          photo: photoRelativePath,
          location: location.name,
          timestamp: now.toISOString(),
        },
      });
    } catch (error) {
      // Cleanup file jika terjadi error tak terduga
      if (req.file && fs.existsSync(req.file.path)) {
        fs.unlinkSync(req.file.path);
      }
      next(error);
    }
  },

  /**
   * POST /api/attendance
   * Proses absensi legacy: upload foto, geofencing, face recognition, simpan log.
   *
   * Flow:
   *   1. Validasi JWT (sudah dilakukan oleh authMiddleware)
   *   2. Validasi koordinat (latitude & longitude)
   *   3. Ambil lokasi kantor/kampus dari database
   *   4. Hitung jarak menggunakan Haversine
   *   5. Jika di luar radius → status "Di Luar Radius"
   *   6. Jika dalam radius → bandingkan wajah dengan foto master
   *   7. Jika wajah cocok → status "Hadir"
   *   8. Jika tidak cocok → status "Wajah Tidak Cocok"
   *   9. Simpan log absensi
   */
  submitAttendance: async (req, res, next) => {
    try {
      const userId = req.user.id;

      // ──────────────────────────────────────────────
      // 1. Validasi tipe absensi ('in' atau 'out')
      // ──────────────────────────────────────────────
      const type = (req.body.type || 'in').toLowerCase();
      if (!['in', 'out'].includes(type)) {
        if (req.file) fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Tipe presensi tidak valid. Harus "in" (Clock In) atau "out" (Clock Out).',
        });
      }

      // ──────────────────────────────────────────────
      // 2. Validasi Aturan Harian (1x per hari per aksi)
      // ──────────────────────────────────────────────
      const todayStatus = await Attendance.getTodayStatus(userId);

      // Jika user sudah melakukan izin hari ini, Clock In dan Clock Out tidak dapat dilakukan
      if (todayStatus.hasLeaveToday) {
        if (req.file) fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Anda sudah mengajukan izin hari ini, sehingga tidak dapat melakukan Clock In maupun Clock Out.',
        });
      }

      if (type === 'in' && todayStatus.hasClockedIn) {
        if (req.file) fs.unlinkSync(req.file.path);
        const inTime = (todayStatus.clockIn.time || (todayStatus.clockIn.time || new Date(todayStatus.clockIn.created_at).toLocaleTimeString('id-ID', {
          hour: '2-digit',
          minute: '2-digit',
          timeZone: 'Asia/Jakarta',
          timeZone: 'Asia/Jakarta',
        })).replace('.', ':')).replace('.', ':');
        return res.status(400).json({
          success: false,
          message: `Anda sudah melakukan Clock In hari ini pada pukul ${inTime}.`,
        });
      }

      if (type === 'in' && todayStatus.hasPendingReview) {
        if (req.file) fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Presensi Anda sebelumnya sedang menunggu review approval admin. Silakan tunggu konfirmasi dari admin.',
        });
      }

      if (type === 'in' && todayStatus.hasRejectedToday) {
        if (req.file) fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Presensi Anda hari ini telah ditolak oleh admin (Wajah Tidak Cocok / Terhitung Alpha).',
        });
      }

      if (type === 'out') {
        if (!todayStatus.hasClockedIn) {
          if (req.file) fs.unlinkSync(req.file.path);
          return res.status(400).json({
            success: false,
            message: 'Anda belum melakukan Clock In hari ini. Silakan Clock In terlebih dahulu.',
          });
        }
        if (todayStatus.hasClockedOut) {
          if (req.file) fs.unlinkSync(req.file.path);
          const outTime = (todayStatus.clockOut.time || (todayStatus.clockOut.time || new Date(todayStatus.clockOut.created_at).toLocaleTimeString('id-ID', {
            hour: '2-digit',
            minute: '2-digit',
            timeZone: 'Asia/Jakarta',
            timeZone: 'Asia/Jakarta',
          })).replace('.', ':')).replace('.', ':');
          return res.status(400).json({
            success: false,
            message: `Anda sudah melakukan Clock Out hari ini pada pukul ${outTime}.`,
          });
        }
      }

      // ──────────────────────────────────────────────
      // 3. Validasi file foto (Wajib hanya untuk Clock In, Clock Out tanpa foto)
      // ──────────────────────────────────────────────
      if (type === 'in' && !req.file) {
        return res.status(400).json({
          success: false,
          message: 'Foto identifikasi wajah wajib diunggah saat Clock In.',
        });
      }

      // ──────────────────────────────────────────────
      // 4. Validasi koordinat GPS
      // ──────────────────────────────────────────────
      const { latitude, longitude } = req.body;

      if (!latitude || !longitude) {
        if (req.file) fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Latitude dan longitude wajib disertakan.',
        });
      }

      const lat = parseFloat(latitude);
      const lng = parseFloat(longitude);

      if (isNaN(lat) || isNaN(lng)) {
        if (req.file) fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Latitude dan longitude harus berupa angka yang valid.',
        });
      }

      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        if (req.file) fs.unlinkSync(req.file.path);
        return res.status(400).json({
          success: false,
          message: 'Koordinat di luar rentang valid. Latitude: -90 s/d 90, Longitude: -180 s/d 180.',
        });
      }

      // ──────────────────────────────────────────────
      // 5. Ambil SEMUA lokasi aktif dari database
      // ──────────────────────────────────────────────
      const allLocations = await Location.getAllActive();

      if (!allLocations || allLocations.length === 0) {
        if (req.file) fs.unlinkSync(req.file.path);
        return res.status(404).json({
          success: false,
          message: 'Lokasi kantor/kampus belum dikonfigurasi. Hubungi admin.',
        });
      }

      // ──────────────────────────────────────────────
      // 6. Hitung jarak ke setiap lokasi dan cari yang terdekat dalam radius
      // ──────────────────────────────────────────────
      let matchedLocation = null;
      let shortestDistance = Infinity;

      for (const loc of allLocations) {
        const dist = haversine(lat, lng, loc.latitude, loc.longitude);
        const locRadius = loc.radius || parseInt(process.env.DEFAULT_RADIUS_METERS, 10) || 100;

        if (dist <= locRadius && dist < shortestDistance) {
          matchedLocation = loc;
          shortestDistance = dist;
        }
      }

      // ──────────────────────────────────────────────
      // 7. Cek geofencing - Jika tidak berada dalam radius lokasi manapun
      // ──────────────────────────────────────────────
      if (!matchedLocation) {
        // Hitung jarak ke lokasi terdekat untuk ditampilkan di pesan error
        let closestLoc = allLocations[0];
        let closestDist = haversine(lat, lng, allLocations[0].latitude, allLocations[0].longitude);
        for (let i = 1; i < allLocations.length; i++) {
          const dist = haversine(lat, lng, allLocations[i].latitude, allLocations[i].longitude);
          if (dist < closestDist) {
            closestLoc = allLocations[i];
            closestDist = dist;
          }
        }
        const closestRadius = closestLoc.radius || parseInt(process.env.DEFAULT_RADIUS_METERS, 10) || 100;

        const photoRelativePath = req.file ? `attendance/${req.file.filename}` : null;

        const attendanceLog = await Attendance.create({
          user_id: userId,
          latitude: lat,
          longitude: lng,
          distance: closestDist,
          face_confidence: null,
          status: 'Di Luar Radius',
          photo: photoRelativePath,
          location_id: closestLoc.id,
        });

        return res.status(200).json({
          success: false,
          message: `Anda berada di luar radius semua lokasi terdaftar. Lokasi terdekat: "${closestLoc.name}" (jarak: ${closestDist} meter, radius: ${closestRadius} meter).`,
          data: {
            id: attendanceLog.id,
            status: 'Di Luar Radius',
            distance: closestDist,
            radius: closestRadius,
            closestLocation: closestLoc.name,
            timestamp: new Date().toISOString(),
          },
        });
      }

      // Gunakan lokasi yang cocok (terdekat dalam radius)
      const location = matchedLocation;
      const distance = shortestDistance;
      const radius = location.radius || parseInt(process.env.DEFAULT_RADIUS_METERS, 10) || 100;

      // ──────────────────────────────────────────────
      // 8. Face Recognition
      // Clock In: komparasi wajah aktif. Jika tidak cocok (not match) -> status 'pending'
      // Clock Out: tidak membutuhkan foto/wajah, langsung simpan.
      // ──────────────────────────────────────────────
      let faceConfidence = null;
      let faceStatus = type === 'in' ? 'Clock In' : 'Clock Out';
      let isFaceMatch = true;

      if (type === 'in') {
        const facePhotoRelative = await User.getFacePhoto(userId);

        if (!facePhotoRelative) {
          faceConfidence = 0;
          faceStatus = 'pending';
          isFaceMatch = false;
        } else {
          const masterFacePath = path.join(UPLOAD_DIR_FACES, path.basename(facePhotoRelative));
          const attendanceFacePath = req.file.path;

          if (!fs.existsSync(masterFacePath)) {
            faceConfidence = 0;
            faceStatus = 'pending';
            isFaceMatch = false;
          } else {
            try {
              // Cek parameter manual/mock override untuk testing
              if (
                req.body.is_match === 'false' ||
                req.body.not_match === 'true' ||
                req.body.force_not_match === 'true' ||
                req.query.not_match === 'true'
              ) {
                faceConfidence = 38.5;
                faceStatus = 'pending';
                isFaceMatch = false;
              } else {
                const faceResult = await compareFaces(masterFacePath, attendanceFacePath);
                faceConfidence = faceResult.confidence;
                const confidenceThreshold = faceResult.thresholds
                  ? (faceResult.thresholds['1e-3'] || 60)
                  : 60;

                if (faceConfidence >= confidenceThreshold) {
                  faceStatus = 'Clock In';
                  isFaceMatch = true;
                } else {
                  // Not match: Wajah tidak cocok -> status 'pending'
                  faceStatus = 'pending';
                  isFaceMatch = false;
                }
              }
            } catch (faceErr) {
              console.error('Face comparison error (status diset ke pending):', faceErr.message);
              faceConfidence = 0;
              faceStatus = 'pending';
              isFaceMatch = false;
            }
          }
        }
      }

      // ──────────────────────────────────────────────
      // 7. Simpan log absensi dengan status final
      // ──────────────────────────────────────────────
      const photoRelativePath = req.file ? `attendance/${req.file.filename}` : null;

      const attendanceLog = await Attendance.create({
        user_id: userId,
        latitude: lat,
        longitude: lng,
        distance,
        face_confidence: faceConfidence,
        status: faceStatus,
        photo: photoRelativePath,
        location_id: location.id,
      });

      // ──────────────────────────────────────────────
      // 10. Response
      // ──────────────────────────────────────────────
      const isSuccess = faceStatus === 'Clock In' || faceStatus === 'Clock Out';
      const statusCode = 200;
      const actionLabel = type === 'in' ? 'Clock In' : 'Clock Out';
      const now = new Date();
      const timeStr = now.toLocaleTimeString('id-ID', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'Asia/Jakarta',
      }).replace('.', ':');

      let message = '';
      if (faceStatus === 'pending') {
        message = `Wajah tidak cocok (Akurasi: ${faceConfidence ? faceConfidence + '%' : 'Not Match'}). Presensi Anda berstatus pending dan sedang menunggu review approval dari admin.`;
      } else if (isSuccess) {
        message = `${actionLabel} berhasil pada pukul ${timeStr}.`;
      } else {
        message = `${actionLabel} gagal.`;
      }

      return res.status(statusCode).json({
        success: isSuccess,
        status: faceStatus,
        message,
        data: {
          id: attendanceLog.id,
          status: faceStatus,
          time: timeStr,
          distance,
          radius,
          face_confidence: faceConfidence,
          photo: photoRelativePath,
          location: location.name,
          timestamp: now.toISOString(),
        },
      });
    } catch (error) {
      // Cleanup file jika terjadi error
      if (req.file && fs.existsSync(req.file.path)) {
        fs.unlinkSync(req.file.path);
      }
      next(error);
    }
  },

  /**
   * GET /api/attendance/history
   * Ambil riwayat absensi user yang sedang login.
   */
  getMyHistory: async (req, res, next) => {
    try {
      const userId = req.user.id;
      const page = parseInt(req.query.page, 10) || 1;
      const limit = parseInt(req.query.limit, 10) || 100;
      const { date, month, year, date_from, date_to } = req.query;

      const result = await Attendance.findByUserId(userId, {
        page,
        limit,
        date,
        month,
        year,
        date_from,
        date_to,
      });

      return res.status(200).json({
        success: true,
        message: 'Riwayat absensi berhasil diambil.',
        data: result.data,
        pagination: {
          total: result.total,
          page: result.page,
          totalPages: result.totalPages,
          limit,
        },
      });
    } catch (error) {
      next(error);
    }
  },

  /**
   * GET /api/attendance/statistics
   * Mengambil ringkasan statistik diagram batang untuk user yang login:
   * - ci_and_co : Clock In & Clock Out
   * - ci_not_co : Clock In tanpa Clock Out
   * - izin      : Izin disetujui / log izin
   * - alpha     : Hari kerja tanpa absensi & izin
   * Query params: date (YYYY-MM-DD), month (1-12), year (YYYY)
   */
  getMyStatistics: async (req, res, next) => {
    try {
      const userId = req.user.id;
      const { date, month, year } = req.query;

      const now = new Date();
      const nowWIBStr = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(now);
      const currentYear = parseInt(nowWIBStr.split('-')[0], 10);
      const currentMonth = parseInt(nowWIBStr.split('-')[1], 10);

      let startDateStr, endDateStr;

      if (date && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
        startDateStr = date;
        endDateStr = date;
      } else {
        const filterYear = year ? parseInt(year, 10) : currentYear;
        if (month && parseInt(month, 10) >= 1 && parseInt(month, 10) <= 12) {
          const filterMonth = parseInt(month, 10);
          const mm = String(filterMonth).padStart(2, '0');
          const lastDay = new Date(filterYear, filterMonth, 0).getDate();
          startDateStr = `${filterYear}-${mm}-01`;
          endDateStr = `${filterYear}-${mm}-${String(lastDay).padStart(2, '0')}`;
        } else {
          // Seluruh tahun
          startDateStr = `${filterYear}-01-01`;
          endDateStr = `${filterYear}-12-31`;
        }
      }

      const { pool } = require('../config/database');
      const [logs] = await pool.execute(
        `SELECT DATE(created_at) as log_date, status, created_at
         FROM attendance_logs
         WHERE user_id = ?
           AND created_at >= ? AND created_at <= ?
           AND status IN ('Clock In', 'Clock Out', 'Izin')
         ORDER BY created_at ASC`,
        [userId, `${startDateStr} 00:00:00`, `${endDateStr} 23:59:59`]
      );

      const [leaves] = await pool.execute(
        `SELECT DATE(created_at) as leave_date, reason, status
         FROM leave_requests
         WHERE user_id = ?
           AND status = 'approved'
           AND created_at >= ? AND created_at <= ?`,
        [userId, `${startDateStr} 00:00:00`, `${endDateStr} 23:59:59`]
      );

      const dateMap = new Map();

      logs.forEach((log) => {
        const dStr = log.log_date instanceof Date
          ? new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(log.log_date)
          : String(log.log_date).slice(0, 10);

        if (!dateMap.has(dStr)) {
          dateMap.set(dStr, { hasClockIn: false, hasClockOut: false, hasLeave: false });
        }
        const entry = dateMap.get(dStr);
        if (log.status === 'Clock In') entry.hasClockIn = true;
        if (log.status === 'Clock Out') entry.hasClockOut = true;
        if (log.status === 'Izin') entry.hasLeave = true;
      });

      leaves.forEach((l) => {
        const dStr = l.leave_date instanceof Date
          ? new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(l.leave_date)
          : String(l.leave_date).slice(0, 10);

        if (!dateMap.has(dStr)) {
          dateMap.set(dStr, { hasClockIn: false, hasClockOut: false, hasLeave: false });
        }
        dateMap.get(dStr).hasLeave = true;
      });

      let ciAndCo = 0;
      let ciNotCo = 0;
      let izinCount = 0;
      let alphaCount = 0;

      for (const [_, entry] of dateMap.entries()) {
        if (entry.hasClockIn && entry.hasClockOut) {
          ciAndCo++;
        } else if (entry.hasClockIn && !entry.hasClockOut) {
          ciNotCo++;
        } else if (!entry.hasClockIn && entry.hasLeave) {
          izinCount++;
        }
      }

      const parseDate = (str) => {
        const [y, m, d] = str.split('-').map(Number);
        return new Date(y, m - 1, d);
      };

      const startD = parseDate(startDateStr);
      const endD = parseDate(endDateStr);
      const todayD = parseDate(nowWIBStr);

      const effectiveEnd = endD > todayD ? todayD : endD;
      let cur = new Date(startD);

      while (cur <= effectiveEnd) {
        const yyyy = cur.getFullYear();
        const mm = String(cur.getMonth() + 1).padStart(2, '0');
        const dd = String(cur.getDate()).padStart(2, '0');
        const dStr = `${yyyy}-${mm}-${dd}`;
        const dayOfWeek = cur.getDay(); // 0: Minggu, 6: Sabtu

        const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;
        const entry = dateMap.get(dStr);
        const hasActivity = entry && (entry.hasClockIn || entry.hasLeave);

        if (!hasActivity) {
          if (startDateStr === endDateStr) {
            alphaCount++;
          } else if (!isWeekend) {
            alphaCount++;
          }
        }

        cur.setDate(cur.getDate() + 1);
      }

      return res.status(200).json({
        success: true,
        message: 'Statistik absensi berhasil dihitung.',
        data: {
          ci_and_co: ciAndCo,
          ci_not_co: ciNotCo,
          izin: izinCount,
          alpha: alphaCount,
          start_date: startDateStr,
          end_date: endDateStr,
        },
      });
    } catch (error) {
      next(error);
    }
  },

  /**
   * GET /api/attendance
   * Ambil semua log absensi (admin only).
   * Query params: page, limit, user_id, status, date_from, date_to
   */
  getAllAttendance: async (req, res, next) => {
    try {
      const { page, limit, user_id, status, date_from, date_to, location_id } = req.query;

      const result = await Attendance.findAll({
        page: parseInt(page, 10) || 1,
        limit: parseInt(limit, 10) || 20,
        user_id: user_id ? parseInt(user_id, 10) : undefined,
        status,
        date_from,
        date_to,
        location_id: location_id ? parseInt(location_id, 10) : undefined,
      });

      return res.status(200).json({
        success: true,
        message: 'Data absensi berhasil diambil.',
        data: result.data,
        pagination: {
          total: result.total,
          page: result.page,
          totalPages: result.totalPages,
          limit: parseInt(limit, 10) || 20,
        },
      });
    } catch (error) {
      next(error);
    }
  },

  /**
   * GET /api/attendance/:id
   * Ambil detail absensi berdasarkan ID.
   */
  getAttendanceById: async (req, res, next) => {
    try {
      const { id } = req.params;
      const attendance = await Attendance.findById(parseInt(id, 10));

      if (!attendance) {
        return res.status(404).json({
          success: false,
          message: 'Data absensi tidak ditemukan.',
        });
      }

      // User biasa hanya bisa lihat absensinya sendiri
      if (req.user.role !== 'admin' && attendance.user_id !== req.user.id) {
        return res.status(403).json({
          success: false,
          message: 'Anda tidak memiliki akses ke data absensi ini.',
        });
      }

      return res.status(200).json({
        success: true,
        message: 'Detail absensi berhasil diambil.',
        data: attendance,
      });
    } catch (error) {
      next(error);
    }
  },

  getTodayStatus: async (req, res, next) => {
    try {
      const userId = req.user.id;
      const status = await Attendance.getTodayStatus(userId);
      return res.status(200).json({
        success: true,
        data: status,
      });
    } catch (error) {
      next(error);
    }
  },

  /**
   * PATCH /api/attendance/:id/status
   * Update status verifikasi kehadiran / face approval (admin only).
   */
  updateStatus: async (req, res, next) => {
    try {
      const { id } = req.params;
      const { status, notes } = req.body;

      if (!status) {
        return res.status(400).json({
          success: false,
          message: 'Status wajib diisi.',
        });
      }

      await Attendance.updateStatus(parseInt(id, 10), { status, notes });

      return res.status(200).json({
        success: true,
        message: 'Status absensi berhasil diperbarui.',
      });
    } catch (error) {
      next(error);
    }
  },
};

module.exports = attendanceController;
