const express = require('express');
const router = express.Router();
const attendanceController = require('../controllers/attendanceController');
const { authMiddleware, adminOnly } = require('../middlewares/authMiddleware');
const { uploadAttendance } = require('../config/multer');

/**
 * Routes Absensi
 *
 * POST   /api/attendance          - Submit absensi (user, upload foto + GPS)
 * GET    /api/attendance          - Ambil semua log absensi (admin only)
 * GET    /api/attendance/history  - Riwayat absensi user yang login
 * GET    /api/attendance/:id      - Detail absensi berdasarkan ID
 */

// Submit absensi - User mengirim foto wajah + koordinat GPS
router.post(
  '/',
  authMiddleware,
  uploadAttendance.single('photo'),
  attendanceController.submitAttendance
);

// Riwayat absensi user yang sedang login
router.get('/history', authMiddleware, attendanceController.getMyHistory);

// Statistik diagram batang absensi user yang sedang login
router.get('/statistics', authMiddleware, attendanceController.getMyStatistics);

// Semua log absensi (admin only)
router.get('/', authMiddleware, adminOnly, attendanceController.getAllAttendance);

// Status absensi hari ini (Clock In & Clock Out) user yang login
router.get('/today', authMiddleware, attendanceController.getTodayStatus);

// Detail absensi (user bisa lihat milik sendiri, admin bisa lihat semua)
router.get('/:id', authMiddleware, attendanceController.getAttendanceById);

// Update status verifikasi absensi / kecocokan wajah (admin only)
router.patch('/:id/status', authMiddleware, adminOnly, attendanceController.updateStatus);

module.exports = router;
