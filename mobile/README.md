# Aplikasi Mobile Absensi Karyawan (Flutter) & Integrasi Backend

Aplikasi mobile Flutter untuk presensi karyawan dengan verifikasi biometrik wajah (kamera depan) dan geofencing GPS akurat yang terintegrasi penuh dengan Backend Express.js & Database MySQL.

---

## 🚀 Endpoint Backend yang Terintegrasi

| Fitur | Method | Endpoint | Keterangan |
|---|---|---|---|
| **Autentikasi** | `POST` | `/api/auth/login` | Login menggunakan Email/NIP dan Password |
| **Profil User** | `GET` | `/api/auth/profile` | Sinkronisasi data user aktif |
| **Master Wajah** | `POST` | `/api/auth/face` | Pendaftaran/pembaruan foto master wajah dari mobile |
| **Lokasi Kantor** | `GET` | `/api/locations/active` | Mendapatkan koordinat dan radius aktif kantor secara real-time |
| **Submit Presensi** | `POST` | `/api/attendance` | Mengirim foto selfie wajah (multipart) & koordinat GPS |
| **Riwayat Presensi** | `GET` | `/api/attendance/history` | Mengambil catatan kehadiran user yang sedang login |
| **Health Check** | `GET` | `/api/health` | Verifikasi konektivitas server backend |

---

## 🔑 Akun Uji Coba (Demo Credentials)

| Peran (Role) | Email | NIP | Password | Keterangan |
|---|---|---|---|---|
| **Karyawan** | `karyawan@absensi.com` | `KARYAWAN001` | `karyawan123` | Sudah memiliki foto master wajah & siap presensi |
| **Administrator** | `admin@absensi.com` | `ADMIN001` | `admin123` | Akun admin untuk web dashboard & kelola lokasi |

---

## 🛠️ Dependensi Utama (`pubspec.yaml`)
- `camera`: Mengakses kamera depan dan mengambil foto selfie wajah.
- `geolocator`: Mendeteksi koordinat GPS pengguna dan validasi `isMocked` (anti Fake-GPS).
- `http` & `http_parser`: Mengirimkan request multipart form-data (`MediaType('image', 'jpeg')`) dan Bearer token JWT.
- `shared_preferences`: Menyimpan token JWT, profil, dan URL server kustom secara persisten.
- `intl`: Format tanggal dan jam Indonesia (`id_ID`).

---

## 📱 Konfigurasi URL Server Backend (`ApiConstants`)
Aplikasi mobile mendukung pergantian alamat IP backend secara dinamis langsung dari layar aplikasi (ikon DNS / Server di pojok kanan atas layar login & profil):
- **Default Server**: `http://163.52.135.187:5000`
- **Kustomisasi**: Anda dapat mengubah URL backend langsung lewat dialog server URL pada aplikasi jika diperlukan.

---

## 🏃 Cara Menjalankan

### 1. Jalankan Backend Express.js
```bash
cd backend
npm install
npm run dev
# Server akan berjalan di http://localhost:5000
```

### 2. Jalankan Aplikasi Mobile (Flutter)
```bash
cd mobile
flutter pub get

# Jalankan di Android Emulator / Device:
flutter run

# Atau jalankan di Web:
flutter run -d edge
```
