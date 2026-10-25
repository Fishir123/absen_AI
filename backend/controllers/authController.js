const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const User = require('../models/User');
require('dotenv').config();

/**
 * AuthController - Menangani autentikasi (login, register, profil).
 */
const authController = {
  /**
   * POST /api/auth/register
   * Registrasi user baru (hanya admin yang bisa).
   */
  register: async (req, res, next) => {
    try {
      const { name, email, nip, password, role } = req.body;

      // Validasi input
      if (!name || !email || !nip || !password) {
        return res.status(400).json({
          success: false,
          message: 'Nama, email/nama pengguna, NIP, dan password wajib diisi.',
        });
      }

      // Cek email/username unik
      const existingEmail = await User.findByEmail(email);
      if (existingEmail) {
        return res.status(409).json({
          success: false,
          message: 'Email atau nama pengguna sudah terdaftar.',
        });
      }

      // Cek NIP unik
      const existingNip = await User.findByNip(nip);
      if (existingNip) {
        return res.status(409).json({
          success: false,
          message: 'NIP sudah terdaftar.',
        });
      }

      // Hash password
      const salt = await bcrypt.genSalt(12);
      const hashedPassword = await bcrypt.hash(password, salt);

      // Handle foto master wajah jika diunggah saat registrasi
      let facePhotoRelative = null;
      if (req.file) {
        facePhotoRelative = `faces/${req.file.filename}`;
      }

      // Buat user
      const user = await User.create({
        name,
        email,
        nip,
        password: hashedPassword,
        role: role || 'user',
        face_photo: facePhotoRelative,
      });

      return res.status(201).json({
        success: true,
        message: 'User berhasil didaftarkan.',
        data: {
          id: user.id,
          name: user.name,
          email: user.email,
          nip: user.nip,
          role: user.role,
          face_photo: user.face_photo,
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
   * POST /api/auth/login
   * Login menggunakan email/NIP + password.
   */
  login: async (req, res, next) => {
    try {
      const { email, nip, identifier, password } = req.body;
      const loginId = (identifier || email || nip || '').trim();

      if (!password || !loginId) {
        return res.status(400).json({
          success: false,
          message: 'Email/Username/NIP dan password wajib diisi.',
        });
      }

      // Cari user berdasarkan email / username (dengan atau tanpa @gmail.com)
      let user = await User.findByEmail(loginId);
      // Jika tidak ditemukan, coba cari berdasarkan NIP
      if (!user) {
        user = await User.findByNip(loginId);
      }

      if (!user) {
        return res.status(401).json({
          success: false,
          message: 'Email/Username/NIP atau password salah.',
        });
      }

      // Verifikasi password (mendukung bcrypt hash dan fallback plaintext jika diedit langsung di phpMyAdmin)
      let isPasswordValid = false;
      if (user.password && (user.password.startsWith('$2a$') || user.password.startsWith('$2b$'))) {
        isPasswordValid = await bcrypt.compare(password, user.password);
      } else {
        // Jika password diisi manual sebagai text biasa di phpMyAdmin
        isPasswordValid = (password === user.password);
        if (isPasswordValid) {
          // Otomatis upgrade ke hash bcrypt
          try {
            const salt = await bcrypt.genSalt(12);
            const hashedPassword = await bcrypt.hash(password, salt);
            await User.update(user.id, { password: hashedPassword });
          } catch (hashErr) {
            console.warn('Gagal auto-upgrade password hash:', hashErr.message);
          }
        }
      }

      if (!isPasswordValid) {
        return res.status(401).json({
          success: false,
          message: 'Email/NIP atau password salah.',
        });
      }

      // Generate JWT:
      // - Mobile / Karyawan: Tanpa batas waktu kedaluwarsa (aktif selamanya) agar presensi tidak terganggu
      // - Web Admin: Tetap memiliki batas waktu sesi (24 jam) demi keamanan
      const isMobileClient = req.headers['x-client'] === 'mobile' || req.body.platform === 'mobile' || user.role !== 'admin';
      const jwtOptions = isMobileClient ? {} : { expiresIn: process.env.JWT_EXPIRES_IN || '24h' };

      const token = jwt.sign(
        {
          id: user.id,
          email: user.email,
          role: user.role,
        },
        process.env.JWT_SECRET,
        jwtOptions
      );

      return res.status(200).json({
        success: true,
        message: 'Login berhasil.',
        data: {
          token,
          user: {
            id: user.id,
            name: user.name,
            email: user.email,
            nip: user.nip,
            role: user.role,
            face_photo: user.face_photo || null,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  },

  /**
   * GET /api/auth/profile
   * Ambil profil user yang sedang login.
   */
  getProfile: async (req, res, next) => {
    try {
      const user = await User.findById(req.user.id);

      if (!user) {
        return res.status(404).json({
          success: false,
          message: 'User tidak ditemukan.',
        });
      }

      return res.status(200).json({
        success: true,
        message: 'Profil berhasil diambil.',
        data: user,
      });
    } catch (error) {
      next(error);
    }
  },

  /**
   * POST /api/auth/face
   * Upload foto master wajah untuk user yang sedang login.
   */
  uploadMyFacePhoto: async (req, res, next) => {
    try {
      const fs = require('fs');
      const path = require('path');
      const { UPLOAD_DIR_FACES } = require('../config/multer');
      const id = req.user.id;

      if (!req.file) {
        return res.status(400).json({
          success: false,
          message: 'Foto wajah wajib diunggah.',
        });
      }

      const user = await User.findById(id);
      if (!user) {
        if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
        return res.status(404).json({
          success: false,
          message: 'User tidak ditemukan.',
        });
      }

      // Hapus foto lama jika ada
      if (user.face_photo) {
        const oldPhotoPath = path.join(UPLOAD_DIR_FACES, path.basename(user.face_photo));
        if (fs.existsSync(oldPhotoPath)) {
          fs.unlinkSync(oldPhotoPath);
        }
      }

      const facePhotoRelative = `faces/${req.file.filename}`;
      await User.update(id, { face_photo: facePhotoRelative });

      return res.status(200).json({
        success: true,
        message: 'Foto master wajah berhasil disimpan.',
        data: {
          face_photo: facePhotoRelative,
        },
      });
    } catch (error) {
      const fs = require('fs');
      if (req.file && fs.existsSync(req.file.path)) {
        fs.unlinkSync(req.file.path);
      }
      next(error);
    }
  },
};

module.exports = authController;
