const { pool } = require('../config/database');

/**
 * Model Location - Operasi database untuk tabel locations (lokasi kantor/kampus).
 */
const Location = {
  /**
   * Ambil semua lokasi aktif.
   * Digunakan untuk validasi geofencing multi-lokasi.
   * @returns {Promise<Array>}
   */
  getAllActive: async () => {
    const [rows] = await pool.execute(
      'SELECT * FROM locations WHERE is_active = 1 ORDER BY created_at ASC'
    );
    if (rows.length > 0) return rows;

    // Fallback jika tidak ada yang is_active = 1, ambil semua lokasi
    const [fallbackRows] = await pool.execute(
      'SELECT * FROM locations ORDER BY id ASC'
    );
    return fallbackRows;
  },

  /**
   * Ambil lokasi aktif pertama (backward compatibility).
   * @returns {Promise<object|null>}
   */
  getActive: async () => {
    const allActive = await Location.getAllActive();
    return allActive[0] || null;
  },

  /**
   * Ambil semua lokasi.
   * @returns {Promise<Array>}
   */
  findAll: async () => {
    const [rows] = await pool.execute(
      'SELECT * FROM locations ORDER BY is_active DESC, created_at DESC'
    );
    return rows;
  },

  /**
   * Cari lokasi berdasarkan ID.
   * @param {number} id
   * @returns {Promise<object|null>}
   */
  findById: async (id) => {
    const [rows] = await pool.execute('SELECT * FROM locations WHERE id = ?', [id]);
    return rows[0] || null;
  },

  /**
   * Buat lokasi baru.
   * @param {object} data - { name, latitude, longitude, radius, is_active }
   * @returns {Promise<object>}
   */
  create: async ({ name, latitude, longitude, radius, is_active = 1 }) => {
    // Semua lokasi baru langsung aktif secara default (is_active: 1)
    const activeStatus = (is_active === 0 || is_active === false || is_active === '0') ? 0 : 1;
    const [result] = await pool.execute(
      'INSERT INTO locations (name, latitude, longitude, radius, is_active) VALUES (?, ?, ?, ?, ?)',
      [name, latitude, longitude, radius, activeStatus]
    );
    return { id: result.insertId, name, latitude, longitude, radius, is_active: activeStatus };
  },

  /**
   * Update lokasi.
   * @param {number} id
   * @param {object} data
   * @returns {Promise<object>}
   */
  update: async (id, { name, latitude, longitude, radius, is_active }) => {
    // Update lokasi tanpa menonaktifkan lokasi lain
    const [result] = await pool.execute(
      `UPDATE locations SET name = ?, latitude = ?, longitude = ?, radius = ?, is_active = ?, updated_at = NOW()
       WHERE id = ?`,
      [name, latitude, longitude, radius, is_active ? 1 : 0, id]
    );

    // Pastikan tetap ada minimal 1 lokasi aktif jika ada data
    const [active] = await pool.execute('SELECT id FROM locations WHERE is_active = 1 LIMIT 1');
    if (!active[0]) {
      await pool.execute('UPDATE locations SET is_active = 1 WHERE id = ?', [id]);
    }

    return result;
  },

  /**
   * Aktifkan lokasi tertentu
   * @param {number} id
   */
  setActive: async (id) => {
    await pool.execute('UPDATE locations SET is_active = 0');
    const [result] = await pool.execute('UPDATE locations SET is_active = 1 WHERE id = ?', [id]);
    return result;
  },

  /**
   * Hapus lokasi.
   * @param {number} id
   * @returns {Promise<object>}
   */
  delete: async (id) => {
    const [result] = await pool.execute('DELETE FROM locations WHERE id = ?', [id]);

    // Jika lokasi aktif terhapus, aktifkan lokasi lain yang masih ada
    const [active] = await pool.execute('SELECT id FROM locations WHERE is_active = 1 LIMIT 1');
    if (!active[0]) {
      const [remaining] = await pool.execute('SELECT id FROM locations ORDER BY id ASC LIMIT 1');
      if (remaining[0]) {
        await pool.execute('UPDATE locations SET is_active = 1 WHERE id = ?', [remaining[0].id]);
      }
    }

    return result;
  },
};

module.exports = Location;
