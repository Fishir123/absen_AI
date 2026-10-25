import React, { useState, useEffect } from 'react';
import { fetchLocations, createLocation, updateOfficeLocation, deleteLocation, setActiveLocation } from '../../services/api';

export default function TambahLokasiPage({ onBack, onLogout }) {
  const [locations, setLocations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [notification, setNotification] = useState(null);

  // Modal State (Add & Edit)
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingLocation, setEditingLocation] = useState(null);
  const [formData, setFormData] = useState({
    name: '',
    latitude: '',
    longitude: '',
    radius: 100,
    address: '',
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [detectingGps, setDetectingGps] = useState(false);
  const [modalError, setModalError] = useState('');

  const showNotif = (type, message) => {
    setNotification({ type, message });
    setTimeout(() => setNotification(null), 3500);
  };

  const loadLocations = async () => {
    setLoading(true);
    try {
      const res = await fetchLocations();
      if (res && res.data) {
        setLocations(res.data);
      } else {
        setLocations([]);
      }
    } catch (err) {
      setLocations([]);
      showNotif('error', 'Gagal memuat titik lokasi dari database: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadLocations();
  }, []);

  // Set Lokasi Aktif Utama
  const handleSetActive = async (loc) => {
    try {
      await setActiveLocation(loc.id);
      setLocations((prev) =>
        prev.map((l) => ({
          ...l,
          is_active: l.id === loc.id ? 1 : 0,
        }))
      );
      showNotif('success', `Lokasi "${loc.name}" sekarang menjadi lokasi aktif utama.`);
    } catch (err) {
      showNotif('error', 'Gagal mengubah lokasi aktif: ' + err.message);
    }
  };

  // Buka modal untuk Tambah Lokasi Baru
  const handleOpenAddModal = () => {
    setEditingLocation(null);
    setModalError('');
    setFormData({
      name: '',
      latitude: '',
      longitude: '',
      radius: 100,
      address: '',
    });
    setIsModalOpen(true);
  };

  // Buka modal untuk Edit Lokasi
  const handleOpenEditModal = (loc) => {
    setEditingLocation(loc);
    setModalError('');
    setFormData({
      name: loc.name || '',
      latitude: loc.latitude !== undefined ? String(loc.latitude) : '',
      longitude: loc.longitude !== undefined ? String(loc.longitude) : '',
      radius: loc.radius || 100,
      address: loc.address || '',
    });
    setIsModalOpen(true);
  };

  // Tutup Modal
  const handleCloseModal = () => {
    setIsModalOpen(false);
    setEditingLocation(null);
    setModalError('');
  };

  // Input Change Handler dengan Auto-Sanitize Koma & Format GPS
  const handleInputChange = (e) => {
    let { name, value } = e.target;

    // Jika user paste format koordinat gabungan "lat, lng" (misal: -7.471183, 112.575646)
    if ((name === 'latitude' || name === 'longitude') && value.includes(',')) {
      const parts = value.split(',').map((s) => s.trim());
      if (parts.length === 2 && !isNaN(Number(parts[0])) && !isNaN(Number(parts[1]))) {
        setFormData((prev) => ({
          ...prev,
          latitude: parts[0],
          longitude: parts[1],
        }));
        return;
      }
      // Ganti tanda koma menjadi titik desimal standar
      value = value.replace(/,/g, '.');
    }

    setFormData((prev) => ({
      ...prev,
      [name]: value,
    }));
  };

  // Ambil GPS perangkat saat ini dengan auto fallback & error handling komprehensif
  const handleGetCurrentLocation = () => {
    if (!navigator.geolocation) {
      const msg = 'Browser Anda tidak mendukung Geolocation API.';
      setModalError(msg);
      showNotif('error', msg);
      return;
    }

    setDetectingGps(true);
    setModalError('');

    // Langkah 1: Coba High Accuracy (Satelit / GPS perangkat mobile)
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setFormData((prev) => ({
          ...prev,
          latitude: String(position.coords.latitude.toFixed(6)),
          longitude: String(position.coords.longitude.toFixed(6)),
        }));
        setDetectingGps(false);
        setModalError('');
        showNotif('success', 'Berhasil mendeteksi koordinat GPS saat ini!');
      },
      (errorHigh) => {
        // Jika izin lokasi ditolak oleh user di browser
        if (errorHigh.code === errorHigh.PERMISSION_DENIED) {
          setDetectingGps(false);
          const msg = 'Izin akses lokasi ditolak oleh browser. Silakan klik ikon perizinan/gembok di URL bar browser Anda untuk mengizinkan akses lokasi.';
          setModalError(msg);
          showNotif('error', msg);
          return;
        }

        // Langkah 2: Fallback ke Low Accuracy (berbasis IP / Wi-Fi, cocok untuk laptop/PC tanpa chip GPS satelit)
        navigator.geolocation.getCurrentPosition(
          (position) => {
            setFormData((prev) => ({
              ...prev,
              latitude: String(position.coords.latitude.toFixed(6)),
              longitude: String(position.coords.longitude.toFixed(6)),
            }));
            setDetectingGps(false);
            setModalError('');
            showNotif('success', 'Berhasil mendeteksi lokasi perangkat!');
          },
          (errorLow) => {
            setDetectingGps(false);
            let msg = 'Gagal mendeteksi lokasi.';
            if (errorLow.code === errorLow.PERMISSION_DENIED) {
              msg = 'Izin akses lokasi ditolak oleh pengguna pada browser.';
            } else if (errorLow.code === errorLow.POSITION_UNAVAILABLE) {
              msg = 'Sinyal lokasi tidak tersedia (komputer PC/laptop umumnya tidak memiliki chip GPS fisik). Silakan salin koordinat langsung dari Google Maps.';
            } else if (errorLow.code === errorLow.TIMEOUT) {
              msg = 'Waktu pencarian lokasi GPS habis. Silakan coba lagi atau masukkan koordinat secara manual dari Google Maps.';
            } else {
              msg = 'Gagal mengambil koordinat: ' + (errorLow.message || 'Error tidak diketahui');
            }
            setModalError(msg);
            showNotif('error', msg);
          },
          { enableHighAccuracy: false, timeout: 8000, maximumAge: 60000 }
        );
      },
      { enableHighAccuracy: true, timeout: 5000, maximumAge: 10000 }
    );
  };

  // Submit Simpan (Tambah / Edit)
  const handleSubmit = async (e) => {
    e.preventDefault();
    setModalError('');

    if (!formData.name.trim()) {
      setModalError('Nama lokasi kantor wajib diisi.');
      showNotif('error', 'Nama lokasi kantor wajib diisi.');
      return;
    }

    if (!String(formData.latitude).trim() || !String(formData.longitude).trim()) {
      setModalError('Longitude dan Latitude wajib diisi. Silakan gunakan tombol GPS atau masukkan koordinat secara manual.');
      showNotif('error', 'Longitude dan Latitude wajib diisi.');
      return;
    }

    // Normalisasi format desimal (ganti koma dengan titik dan bersihkan spasi)
    let rawLat = String(formData.latitude).trim().replace(/,/g, '.');
    let rawLng = String(formData.longitude).trim().replace(/,/g, '.');

    // Jika longitude tidak sengaja tidak memiliki tanda titik (contoh: 1125756... -> 112.5756...)
    if (!rawLng.includes('.') && rawLng.startsWith('112') && rawLng.length > 5) {
      rawLng = rawLng.slice(0, 3) + '.' + rawLng.slice(3);
    }
    // Jika latitude tidak sengaja tidak memiliki tanda titik (contoh: -747118... -> -7.47118...)
    if (!rawLat.includes('.') && rawLat.startsWith('-7') && rawLat.length > 4) {
      rawLat = rawLat.slice(0, 2) + '.' + rawLat.slice(2);
    }

    const lat = Number(rawLat);
    const lng = Number(rawLng);

    if (isNaN(lat) || lat < -90 || lat > 90) {
      const msg = 'Latitude harus berupa angka antara -90 dan 90 (gunakan tanda titik "." untuk desimal).';
      setModalError(msg);
      showNotif('error', msg);
      return;
    }

    if (isNaN(lng) || lng < -180 || lng > 180) {
      const msg = 'Longitude harus berupa angka antara -180 dan 180 (gunakan tanda titik "." untuk desimal).';
      setModalError(msg);
      showNotif('error', msg);
      return;
    }

    setIsSubmitting(true);

    try {
      const payload = {
        name: formData.name.trim(),
        latitude: lat,
        longitude: lng,
        radius: Number(formData.radius) || 100,
        address: formData.address.trim(),
        is_active: editingLocation ? (editingLocation.is_active !== undefined ? editingLocation.is_active : 1) : 1,
      };

      if (editingLocation) {
        // Edit lokasi
        await updateOfficeLocation({ ...payload, id: editingLocation.id });
        showNotif('success', `Lokasi "${payload.name}" berhasil diperbarui.`);
      } else {
        // Tambah lokasi baru
        await createLocation(payload);
        showNotif('success', `Titik lokasi "${payload.name}" berhasil ditambahkan!`);
      }

      await loadLocations();
      handleCloseModal();
    } catch (err) {
      const errMsg = 'Gagal menyimpan lokasi: ' + (err.response?.data?.message || err.message);
      setModalError(errMsg);
      showNotif('error', errMsg);
    } finally {
      setIsSubmitting(false);
    }
  };

  // Hapus Lokasi
  const handleDelete = async (loc) => {
    if (window.confirm(`Yakin ingin menghapus titik lokasi "${loc.name}"?`)) {
      try {
        await deleteLocation(loc.id);
        await loadLocations();
        showNotif('success', `Titik lokasi "${loc.name}" telah dihapus.`);
      } catch (err) {
        showNotif('error', 'Gagal menghapus lokasi: ' + err.message);
      }
    }
  };

  return (
    <div style={styles.wrapper}>
      {/* Top Header Bar */}
      <header style={styles.header}>
        <div style={styles.headerInner}>
          <div style={styles.headerLeft}>
            {onBack && (
              <button
                onClick={onBack}
                style={styles.backBtn}
                title="Kembali ke Menu Utama"
                onMouseEnter={(e) => (e.currentTarget.style.background = 'rgba(30,90,138,0.08)')}
                onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
              >
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#1e5a8a" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="15 18 9 12 15 6" />
                </svg>
              </button>
            )}
            <div style={styles.headerLogo}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <rect x="4" y="2" width="16" height="20" rx="2" ry="2" />
                <path d="M9 22v-4h6v4" />
                <path d="M8 6h.01" /><path d="M16 6h.01" /><path d="M12 6h.01" />
                <path d="M12 10h.01" /><path d="M12 14h.01" />
                <path d="M16 10h.01" /><path d="M16 14h.01" />
                <path d="M8 10h.01" /><path d="M8 14h.01" />
              </svg>
            </div>
            <div>
              <h1 style={styles.headerTitle}>PT Poca Jaringan Solusi</h1>
              <p style={styles.headerSubtitle}>Sistem Absensi Karyawan</p>
            </div>
          </div>

          {onLogout && (
            <button
              onClick={onLogout}
              style={styles.logoutBtn}
              title="Keluar"
              onMouseEnter={(e) => (e.currentTarget.style.background = 'rgba(255,255,255,0.15)')}
              onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
                <polyline points="16 17 21 12 16 7" />
                <line x1="21" y1="12" x2="9" y2="12" />
              </svg>
            </button>
          )}
        </div>
      </header>

      {/* Main Content Area */}
      <main style={styles.main}>
        {/* Toast Notification */}
        {notification && (
          <div
            style={{
              ...styles.toast,
              background: notification.type === 'error' ? '#fef2f2' : notification.type === 'success' ? '#f0fdf4' : '#eff6ff',
              borderColor: notification.type === 'error' ? '#fecaca' : notification.type === 'success' ? '#bbf7d0' : '#bfdbfe',
              color: notification.type === 'error' ? '#dc2626' : notification.type === 'success' ? '#16a34a' : '#1d4ed8',
            }}
          >
            <span>{notification.message}</span>
            <button onClick={() => setNotification(null)} style={styles.toastClose}>✕</button>
          </div>
        )}

        {/* Page Title & Add Button */}
        <div style={styles.titleRow}>
          <div style={styles.titleLeft}>
            <div style={styles.titleIcon}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#1e5a8a" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z" />
                <circle cx="12" cy="9" r="2.5" />
              </svg>
            </div>
            <div>
              <h2 style={styles.pageTitle}>Titik Lokasi Kantor</h2>
              <p style={styles.pageSubtitle}>Daftar koordinat longitude dan latitude tiap kantor</p>
            </div>
          </div>

          <button
            onClick={handleOpenAddModal}
            style={styles.addBtn}
            onMouseEnter={(e) => (e.currentTarget.style.background = '#144670')}
            onMouseLeave={(e) => (e.currentTarget.style.background = '#1a5695')}
          >
            + Tambah Titik Lokasi
          </button>
        </div>

        {/* Data Table Card */}
        <div style={styles.tableCard}>
          <div style={styles.tableScroll}>
            <table style={styles.table}>
              <thead>
                <tr style={styles.tableHead}>
                  <th style={{ ...styles.th, width: 60, textAlign: 'center' }}>NO</th>
                  <th style={{ ...styles.th, minWidth: 200 }}>LOKASI KANTOR</th>
                  <th style={{ ...styles.th, minWidth: 140 }}>LONGITUDE</th>
                  <th style={{ ...styles.th, minWidth: 140 }}>LATITUDE</th>
                  <th style={{ ...styles.th, width: 120, textAlign: 'center' }}>ACTION</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr>
                    <td colSpan="5" style={styles.emptyCell}>
                      <div style={styles.spinner} />
                      <span style={{ color: '#8c9ab0', fontSize: 13, marginTop: 8 }}>Memuat data titik lokasi kantor...</span>
                    </td>
                  </tr>
                ) : locations.length === 0 ? (
                  <tr>
                    <td colSpan="5" style={styles.emptyCell}>
                      <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#c4cdd8" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z" />
                        <circle cx="12" cy="9" r="2.5" />
                      </svg>
                      <span style={{ color: '#8c9ab0', fontSize: 13, marginTop: 8 }}>Belum ada data titik lokasi kantor</span>
                    </td>
                  </tr>
                ) : (
                  locations.map((loc, index) => (
                    <tr
                      key={loc.id || index}
                      style={styles.tableRow}
                      onMouseEnter={(e) => (e.currentTarget.style.background = '#f9fafb')}
                      onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
                    >
                      {/* NO */}
                      <td style={{ ...styles.td, textAlign: 'center', color: '#64748b' }}>
                        {index + 1}
                      </td>

                      {/* LOKASI KANTOR */}
                      <td style={styles.td}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#1e5a8a" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                            <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z" />
                            <circle cx="12" cy="9" r="2.5" />
                          </svg>
                          <span style={styles.locationNameText}>{loc.name}</span>
                        </div>
                      </td>

                      {/* LONGITUDE */}
                      <td style={styles.td}>
                        <span style={styles.coordBadge}>
                          {loc.longitude !== undefined ? Number(loc.longitude).toFixed(6) : '-'}
                        </span>
                      </td>

                      {/* LATITUDE */}
                      <td style={styles.td}>
                        <span style={styles.coordBadge}>
                          {loc.latitude !== undefined ? Number(loc.latitude).toFixed(6) : '-'}
                        </span>
                      </td>

                      {/* ACTION (Edit & Delete) */}
                      <td style={{ ...styles.td, textAlign: 'center' }}>
                        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
                          {/* Edit Button */}
                          <button
                            onClick={() => handleOpenEditModal(loc)}
                            style={styles.actionBtnEdit}
                            title="Edit Titik Lokasi"
                            onMouseEnter={(e) => {
                              e.currentTarget.style.background = '#dbeafe';
                              e.currentTarget.style.transform = 'scale(1.05)';
                            }}
                            onMouseLeave={(e) => {
                              e.currentTarget.style.background = '#eaf2fd';
                              e.currentTarget.style.transform = 'scale(1)';
                            }}
                          >
                            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#2563eb" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                              <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
                              <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
                            </svg>
                          </button>

                          {/* Delete Button */}
                          <button
                            onClick={() => handleDelete(loc)}
                            style={styles.actionBtnDelete}
                            title="Hapus Titik Lokasi"
                            onMouseEnter={(e) => {
                              e.currentTarget.style.background = '#fee2e2';
                              e.currentTarget.style.transform = 'scale(1.05)';
                            }}
                            onMouseLeave={(e) => {
                              e.currentTarget.style.background = '#fef2f2';
                              e.currentTarget.style.transform = 'scale(1)';
                            }}
                          >
                            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#dc2626" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                              <polyline points="3 6 5 6 21 6" />
                              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
                            </svg>
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      </main>

      {/* Modal Tambah / Edit Lokasi */}
      {isModalOpen && (
        <div style={styles.modalOverlay} onClick={handleCloseModal}>
          <div style={styles.modalContent} onClick={(e) => e.stopPropagation()}>
            <div style={styles.modalHeader}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <div style={styles.modalHeaderIcon}>
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#1e5a8a" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z" />
                    <circle cx="12" cy="9" r="2.5" />
                  </svg>
                </div>
                <div>
                  <h3 style={styles.modalTitle}>
                    {editingLocation ? 'Edit Titik Lokasi Kantor' : 'Tambah Titik Lokasi Kantor'}
                  </h3>
                  <p style={styles.modalSubtitle}>
                    {editingLocation ? 'Perbarui koordinat target kantor' : 'Tambahkan kantor baru untuk validasi geofencing absensi'}
                  </p>
                </div>
              </div>
              <button onClick={handleCloseModal} style={styles.modalCloseBtn}>✕</button>
            </div>

            <form onSubmit={handleSubmit} style={styles.modalBody}>
              {/* Alert Error / Peringatan di Dalam Modal */}
              {modalError && (
                <div style={styles.modalAlert}>
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#dc2626" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0, marginTop: 1 }}>
                    <circle cx="12" cy="12" r="10" />
                    <line x1="12" y1="8" x2="12" y2="12" />
                    <line x1="12" y1="16" x2="12.01" y2="16" />
                  </svg>
                  <div style={{ flex: 1, fontSize: 12.5, lineHeight: 1.45, color: '#991b1b' }}>
                    {modalError}
                  </div>
                  <button type="button" onClick={() => setModalError('')} style={styles.modalAlertClose}>✕</button>
                </div>
              )}

              {/* Nama Lokasi */}
              <div style={styles.formGroup}>
                <label style={styles.formLabel}>Nama Lokasi Kantor *</label>
                <input
                  type="text"
                  name="name"
                  value={formData.name}
                  onChange={handleInputChange}
                  placeholder="Contoh: Poca Surabaya, Poca Bali"
                  required
                  style={styles.modalInput}
                />
              </div>

              {/* Grid Longitude & Latitude */}
              <div style={styles.grid2}>
                <div style={styles.formGroup}>
                  <label style={styles.formLabel}>Longitude *</label>
                  <input
                    type="number"
                    step="any"
                    name="longitude"
                    value={formData.longitude}
                    onChange={handleInputChange}
                    placeholder="Contoh: 112.738198"
                    required
                    style={styles.modalInput}
                  />
                </div>
                <div style={styles.formGroup}>
                  <label style={styles.formLabel}>Latitude *</label>
                  <input
                    type="number"
                    step="any"
                    name="latitude"
                    value={formData.latitude}
                    onChange={handleInputChange}
                    placeholder="Contoh: -7.257472"
                    required
                    style={styles.modalInput}
                  />
                </div>
              </div>

              {/* Tombol Ambil GPS Saat Ini & Google Maps Shortcut */}
              <div style={{ display: 'flex', gap: 8, marginTop: 2 }}>
                <button
                  type="button"
                  onClick={handleGetCurrentLocation}
                  disabled={detectingGps}
                  style={{ ...styles.gpsBtn, flex: 1 }}
                >
                  {detectingGps ? (
                    <>
                      <div style={styles.buttonSpinner} />
                      <span>Mendeteksi Lokasi GPS...</span>
                    </>
                  ) : (
                    <>
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#1e5a8a" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <circle cx="12" cy="12" r="10" />
                        <line x1="22" y1="12" x2="18" y2="12" />
                        <line x1="6" y1="12" x2="2" y2="12" />
                        <line x1="12" y1="6" x2="12" y2="2" />
                        <line x1="12" y1="22" x2="12" y2="18" />
                      </svg>
                      <span>Gunakan GPS Sekarang</span>
                    </>
                  )}
                </button>
                <button
                  type="button"
                  onClick={() => window.open('https://www.google.com/maps', '_blank')}
                  style={styles.mapsBtn}
                  title="Buka Google Maps di tab baru untuk mengambil koordinat titik kantor"
                >
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#15803d" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6" />
                    <line x1="8" y1="2" x2="8" y2="18" />
                    <line x1="16" y1="6" x2="16" y2="22" />
                  </svg>
                  <span>Buka Maps</span>
                </button>
              </div>

              {/* Tips Salin Koordinat */}
              <div style={styles.mapsTip}>
                💡 <b>Tips Koordinat:</b> Di Google Maps, klik kanan titik kantor Anda lalu klik angka koordinat paling atas untuk copy. Cukup Paste di kolom Longitude atau Latitude di atas, kedua kolom akan terisi otomatis.
              </div>

              {/* Radius Toleransi */}
              <div style={{ ...styles.formGroup, marginTop: 14 }}>
                <label style={styles.formLabel}>Radius Toleransi Presensi (Meter)</label>
                <input
                  type="number"
                  name="radius"
                  value={formData.radius}
                  onChange={handleInputChange}
                  min={1}
                  max={5000}
                  required
                  style={styles.modalInput}
                />
              </div>

              {/* Alamat */}
              <div style={styles.formGroup}>
                <label style={styles.formLabel}>Alamat Kantor (Opsional)</label>
                <textarea
                  name="address"
                  value={formData.address}
                  onChange={handleInputChange}
                  placeholder="Jl. Pemuda No. 45, Genteng, Surabaya"
                  rows={2}
                  style={styles.modalTextarea}
                />
              </div>

              {/* Modal Footer */}
              <div style={styles.modalFooter}>
                <button
                  type="button"
                  onClick={handleCloseModal}
                  style={styles.modalCancelBtn}
                >
                  Batal
                </button>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  style={{
                    ...styles.modalSubmitBtn,
                    opacity: isSubmitting ? 0.75 : 1,
                  }}
                >
                  {isSubmitting ? 'Menyimpan...' : (editingLocation ? 'Perbarui Lokasi' : 'Simpan Lokasi')}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Embedded Animations */}
      <style>{`
        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @keyframes fadeInUp {
          from { opacity: 0; transform: translateY(12px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes slideDown {
          from { opacity: 0; transform: translateY(-10px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
}

const styles = {
  wrapper: {
    minHeight: '100vh',
    background: '#dce6f0',
    display: 'flex',
    flexDirection: 'column',
    fontFamily: "'DM Sans', 'Inter', -apple-system, BlinkMacSystemFont, sans-serif",
  },
  header: {
    background: 'transparent',
    padding: '20px 32px',
    animation: 'slideDown 0.4s ease-out both',
  },
  headerInner: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    maxWidth: 1200,
    margin: '0 auto',
    width: '100%',
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: 12,
  },
  backBtn: {
    background: 'transparent',
    border: 'none',
    cursor: 'pointer',
    padding: 8,
    borderRadius: 10,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'all 0.2s ease',
  },
  headerLogo: {
    width: 40,
    height: 40,
    borderRadius: 12,
    background: '#1e5a8a',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    boxShadow: '0 3px 10px rgba(30, 90, 138, 0.25)',
  },
  headerTitle: {
    fontSize: 15,
    fontWeight: 700,
    color: '#1a1a2e',
    margin: 0,
    lineHeight: 1.2,
  },
  headerSubtitle: {
    fontSize: 11,
    color: '#8c9ab0',
    margin: 0,
  },
  logoutBtn: {
    background: 'transparent',
    border: 'none',
    color: '#6b7a90',
    cursor: 'pointer',
    padding: 10,
    borderRadius: 10,
    display: 'flex',
    alignItems: 'center',
    transition: 'all 0.2s ease',
  },
  main: {
    flex: 1,
    padding: '0 32px 40px',
    maxWidth: 1200,
    margin: '0 auto',
    width: '100%',
    animation: 'fadeInUp 0.5s ease-out 0.1s both',
  },
  toast: {
    position: 'fixed',
    top: 24,
    right: 24,
    zIndex: 99999,
    padding: '12px 18px',
    borderRadius: 12,
    border: '1px solid',
    fontSize: 13,
    fontWeight: 500,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    boxShadow: '0 10px 25px rgba(0, 0, 0, 0.15)',
    animation: 'slideDown 0.3s ease-out both',
    maxWidth: '90vw',
  },
  toastClose: {
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    fontSize: 14,
    color: 'inherit',
    opacity: 0.6,
    padding: '0 4px',
  },
  titleRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 22,
    flexWrap: 'wrap',
    gap: 16,
  },
  titleLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: 14,
  },
  titleIcon: {
    width: 44,
    height: 44,
    borderRadius: 12,
    background: '#eaf0f7',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    boxShadow: '0 1px 4px rgba(0,0,0,0.03)',
  },
  pageTitle: {
    fontSize: 22,
    fontWeight: 700,
    color: '#1a1a2e',
    margin: 0,
    letterSpacing: '-0.02em',
  },
  pageSubtitle: {
    fontSize: 13,
    color: '#8c9ab0',
    margin: '3px 0 0',
    fontWeight: 400,
  },
  addBtn: {
    padding: '11px 20px',
    background: '#1a5695',
    color: '#ffffff',
    border: 'none',
    borderRadius: 10,
    fontSize: 13.5,
    fontWeight: 600,
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    boxShadow: '0 3px 12px rgba(26, 86, 149, 0.25)',
    fontFamily: 'inherit',
  },
  tableCard: {
    background: '#ffffff',
    borderRadius: 16,
    border: '1px solid #e8ecf1',
    boxShadow: '0 2px 16px rgba(0, 0, 0, 0.04)',
    overflow: 'hidden',
  },
  tableScroll: {
    overflowX: 'auto',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse',
    textAlign: 'left',
  },
  tableHead: {
    background: '#f8fafc',
    borderBottom: '1.5px solid #edf2f7',
  },
  th: {
    padding: '16px 18px',
    fontSize: 11,
    fontWeight: 700,
    color: '#64748b',
    textTransform: 'uppercase',
    letterSpacing: '0.06em',
  },
  tableRow: {
    borderBottom: '1px solid #f1f5f9',
    transition: 'background 0.15s ease',
  },
  td: {
    padding: '16px 18px',
    fontSize: 13.5,
    verticalAlign: 'middle',
  },
  locationNameText: {
    fontWeight: 700,
    color: '#1a1a2e',
    fontSize: 14,
  },
  coordBadge: {
    display: 'inline-block',
    padding: '5px 12px',
    background: '#f8fafc',
    border: '1px solid #e2e8f0',
    borderRadius: 8,
    fontSize: 13,
    fontWeight: 500,
    color: '#334155',
    fontFamily: "'IBM Plex Mono', 'Menlo', monospace",
  },
  actionBtnEdit: {
    width: 32,
    height: 32,
    borderRadius: 8,
    background: '#eaf2fd',
    border: '1px solid #dbeafe',
    cursor: 'pointer',
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'all 0.15s ease',
  },
  actionBtnDelete: {
    width: 32,
    height: 32,
    borderRadius: 8,
    background: '#fef2f2',
    border: '1px solid #fee2e2',
    cursor: 'pointer',
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'all 0.15s ease',
  },
  emptyCell: {
    padding: '48px 20px',
    textAlign: 'center',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
  },
  spinner: {
    width: 28,
    height: 28,
    border: '3px solid #e2e8f0',
    borderTopColor: '#1e5a8a',
    borderRadius: '50%',
    animation: 'spin 0.8s linear infinite',
  },
  modalOverlay: {
    position: 'fixed',
    inset: 0,
    background: 'rgba(15, 23, 42, 0.45)',
    backdropFilter: 'blur(3px)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 1000,
    padding: 20,
    animation: 'fadeIn 0.2s ease-out',
  },
  modalContent: {
    background: '#ffffff',
    borderRadius: 16,
    width: '100%',
    maxWidth: 520,
    boxShadow: '0 20px 40px rgba(0, 0, 0, 0.15)',
    overflow: 'hidden',
    animation: 'fadeInUp 0.25s ease-out',
  },
  modalHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '18px 24px',
    borderBottom: '1px solid #f1f5f9',
  },
  modalHeaderIcon: {
    width: 36,
    height: 36,
    borderRadius: 10,
    background: '#eaf0f7',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  modalTitle: {
    fontSize: 16,
    fontWeight: 700,
    color: '#1a1a2e',
    margin: 0,
  },
  modalSubtitle: {
    fontSize: 12,
    color: '#64748b',
    margin: '2px 0 0',
  },
  modalCloseBtn: {
    background: 'transparent',
    border: 'none',
    fontSize: 16,
    color: '#94a3b8',
    cursor: 'pointer',
    padding: 4,
    borderRadius: 6,
  },
  modalBody: {
    padding: '22px 24px',
  },
  formGroup: {
    marginBottom: 14,
  },
  formLabel: {
    display: 'block',
    fontSize: 12.5,
    fontWeight: 600,
    color: '#334155',
    marginBottom: 6,
  },
  modalInput: {
    width: '100%',
    padding: '10px 14px',
    borderRadius: 10,
    border: '1.5px solid #cbd5e1',
    fontSize: 13.5,
    color: '#1e293b',
    background: '#ffffff',
    outline: 'none',
    boxSizing: 'border-box',
    fontFamily: 'inherit',
    transition: 'border-color 0.2s ease',
  },
  modalTextarea: {
    width: '100%',
    padding: '10px 14px',
    borderRadius: 10,
    border: '1.5px solid #cbd5e1',
    fontSize: 13.5,
    color: '#1e293b',
    background: '#ffffff',
    outline: 'none',
    boxSizing: 'border-box',
    fontFamily: 'inherit',
    resize: 'vertical',
  },
  grid2: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 12,
  },
  gpsBtn: {
    width: '100%',
    padding: '9px 12px',
    background: '#eaf2fd',
    border: '1px solid #bfdbfe',
    borderRadius: 8,
    color: '#1e5a8a',
    fontSize: 12.5,
    fontWeight: 600,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    transition: 'all 0.2s ease',
  },
  buttonSpinner: {
    width: 14,
    height: 14,
    border: '2px solid #bfdbfe',
    borderTopColor: '#1e5a8a',
    borderRadius: '50%',
    animation: 'spin 0.8s linear infinite',
  },
  modalFooter: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 10,
    marginTop: 22,
  },
  modalCancelBtn: {
    padding: '10px 18px',
    background: '#f1f5f9',
    color: '#475569',
    border: 'none',
    borderRadius: 8,
    fontSize: 13.5,
    fontWeight: 600,
    cursor: 'pointer',
  },
  modalSubmitBtn: {
    padding: '10px 20px',
    background: '#1a5695',
    color: '#ffffff',
    border: 'none',
    borderRadius: 8,
    fontSize: 13.5,
    fontWeight: 600,
    cursor: 'pointer',
    boxShadow: '0 2px 8px rgba(26, 86, 149, 0.25)',
  },
  modalAlert: {
    padding: '10px 14px',
    background: '#fef2f2',
    border: '1px solid #fecaca',
    borderRadius: 8,
    marginBottom: 14,
    display: 'flex',
    alignItems: 'flex-start',
    gap: 10,
    animation: 'fadeIn 0.2s ease-out',
  },
  modalAlertClose: {
    background: 'none',
    border: 'none',
    color: '#991b1b',
    cursor: 'pointer',
    fontSize: 13,
    padding: '0 2px',
    opacity: 0.7,
  },
  mapsBtn: {
    padding: '9px 12px',
    background: '#f0fdf4',
    border: '1px solid #bbf7d0',
    borderRadius: 8,
    color: '#15803d',
    fontSize: 12.5,
    fontWeight: 600,
    cursor: 'pointer',
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    whiteSpace: 'nowrap',
    transition: 'all 0.2s ease',
  },
  mapsTip: {
    marginTop: 8,
    fontSize: 11.5,
    color: '#64748b',
    lineHeight: 1.45,
    background: '#f8fafc',
    padding: '8px 10px',
    borderRadius: 6,
    border: '1px dashed #cbd5e1',
  },
};
