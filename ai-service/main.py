"""
AI Face Recognition Microservice
=================================
Microservice mandiri (self-hosted) untuk verifikasi wajah menggunakan
FastAPI dan DeepFace dengan model SFace dan metrik cosine.

Endpoint:
  POST /compare  — Menerima dua gambar (captured_image & master_image)
                    dan mengembalikan hasil verifikasi wajah.

Jalankan:
  uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

import os
import sys
import uuid
import shutil
import logging
import asyncio
from functools import partial
from contextlib import asynccontextmanager
from concurrent.futures import ThreadPoolExecutor

# Pastikan UTF-8 encoding untuk console Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from PIL import Image, ImageOps
from deepface import DeepFace

# ──────────────────────────────────────────────
# Konfigurasi Logging
# ──────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  [%(levelname)s]  %(message)s",
)
logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────
# Direktori untuk file sementara
# ──────────────────────────────────────────────
TEMP_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "temp")

# ──────────────────────────────────────────────
# Model yang digunakan (pre-load saat startup)
# ──────────────────────────────────────────────
MODEL_NAME = "Facenet512"
DISTANCE_METRIC = "cosine"

# ════════════════════════════════════════════════════════════════════════
# 🚀 OPTIMASI AGRESIF untuk CPU-only:
#    - 'opencv'  : Detector TERCEPAT (~0.05s), cukup akurat untuk selfie
#    - 'ssd'     : Lebih akurat, tapi lebih lambat (~0.5-1s)
#    - 'retinaface': Paling akurat, tapi SANGAT lambat di CPU (~5-15s)
# ════════════════════════════════════════════════════════════════════════
DETECTOR_BACKEND = "mtcnn"

# ════════════════════════════════════════════════════════════════════════
# 🎯 PENGATURAN TINGKAT AKURASI / KEMIRIPAN WAJAH (0 s/d 100%)
# ════════════════════════════════════════════════════════════════════════
MIN_CONFIDENCE_PERCENT = 60.0

# ════════════════════════════════════════════════════════════════════════
# 🚀 OPTIMASI: Maksimum resolusi gambar sebelum inferensi
#    Model hanya butuh 160x160px. 320px sangat cukup dan hemat waktu.
# ════════════════════════════════════════════════════════════════════════
MAX_IMAGE_DIMENSION = 640

# ════════════════════════════════════════════════════════════════════════
# 🚀 OPTIMASI: Thread pool untuk CPU-bound tasks (DeepFace inference)
#    Agar tidak memblok event loop async FastAPI
# ════════════════════════════════════════════════════════════════════════
_executor = ThreadPoolExecutor(max_workers=2)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan handler — dipanggil saat server startup & shutdown.
    Digunakan untuk pre-load model DeepFace agar request pertama tidak lambat.
    """
    # ── Startup ──
    os.makedirs(TEMP_DIR, exist_ok=True)
    logger.info("📁 Direktori temp siap: %s", TEMP_DIR)

    logger.info("⏳ Memuat model %s & detector %s ...", MODEL_NAME, DETECTOR_BACKEND)
    try:
        DeepFace.build_model(MODEL_NAME)
        logger.info("✅ Model %s berhasil dimuat.", MODEL_NAME)
    except Exception as exc:
        logger.warning("⚠️ Gagal pre-load model: %s (akan dimuat saat request pertama)", exc)

    # 🚀 Pre-load detector dengan dummy verification agar cold start tidak lambat
    try:
        logger.info("⏳ Pre-loading detector %s ...", DETECTOR_BACKEND)
        # Buat dummy image untuk trigger detector loading
        dummy_path = os.path.join(TEMP_DIR, "_dummy_preload.jpg")
        dummy_img = Image.new("RGB", (100, 100), color=(128, 128, 128))
        dummy_img.save(dummy_path, "JPEG")
        try:
            DeepFace.verify(
                img1_path=dummy_path,
                img2_path=dummy_path,
                model_name=MODEL_NAME,
                distance_metric=DISTANCE_METRIC,
                detector_backend=DETECTOR_BACKEND,
                enforce_detection=False,
                align=True,
            )
        except Exception:
            pass  # Dummy image mungkin gagal deteksi, tidak masalah
        finally:
            if os.path.exists(dummy_path):
                os.remove(dummy_path)
        logger.info("✅ Detector %s siap digunakan.", DETECTOR_BACKEND)
    except Exception as exc:
        logger.warning("⚠️ Gagal pre-load detector: %s", exc)

    yield  # ← Server berjalan di sini

    # ── Shutdown ──
    _executor.shutdown(wait=False)
    # Bersihkan folder temp jika masih ada sisa file
    if os.path.exists(TEMP_DIR):
        shutil.rmtree(TEMP_DIR, ignore_errors=True)
        logger.info("🧹 Direktori temp dibersihkan.")


# ──────────────────────────────────────────────
# Inisialisasi FastAPI App
# ──────────────────────────────────────────────
app = FastAPI(
    title="Face Recognition Microservice",
    description="Verifikasi wajah menggunakan DeepFace (SFace + Cosine)",
    version="1.1.0",
    lifespan=lifespan,
)

# Integrasi CORS agar backend, frontend (port 3000), dan mobile dapat mengakses service ini
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ──────────────────────────────────────────────
# Helper: Resize gambar agar tidak terlalu besar
# ──────────────────────────────────────────────
def resize_image_if_needed(filepath: str) -> None:
    """
    🚀 OPTIMASI: Resize gambar ke maks MAX_IMAGE_DIMENSION px pada sisi terpanjang.
    Foto dari kamera HP bisa 3000x4000px+, tapi model face recognition
    hanya membutuhkan resolusi kecil. Ini menghemat waktu inferensi secara drastis.
    """
    try:
        with Image.open(filepath) as img:
            w, h = img.size
            if max(w, h) > MAX_IMAGE_DIMENSION:
                ratio = MAX_IMAGE_DIMENSION / max(w, h)
                new_size = (int(w * ratio), int(h * ratio))
                resized = img.resize(new_size, Image.LANCZOS)
                resized.save(filepath, "JPEG", quality=85)
                logger.debug("📐 Gambar di-resize: %dx%d → %dx%d", w, h, *new_size)
    except Exception as e:
        logger.debug("Info resize: %s", e)


# ──────────────────────────────────────────────
# Helper: Simpan UploadFile ke disk sementara
# ──────────────────────────────────────────────
async def save_temp_file(upload: UploadFile) -> str:
    """Simpan UploadFile ke folder temp, koreksi rotasi EXIF, resize, dan kembalikan path absolutnya."""
    ext = os.path.splitext(upload.filename or "image.jpg")[1] or ".jpg"
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(TEMP_DIR, filename)

    contents = await upload.read()
    with open(filepath, "wb") as f:
        f.write(contents)

    # Pastikan orientasi foto tegak (normalisasi rotasi EXIF dari kamera HP/selfie)
    try:
        with Image.open(filepath) as img:
            transposed = ImageOps.exif_transpose(img)
            if transposed is not None and transposed != img:
                transposed.save(filepath, quality=95)
    except Exception as rot_err:
        logger.debug("Info orientasi EXIF: %s", rot_err)

    # 🚀 OPTIMASI: Resize setelah EXIF correction
    resize_image_if_needed(filepath)

    return filepath


def cleanup_files(*paths: str):
    """Hapus file-file sementara dari disk."""
    for p in paths:
        try:
            if p and os.path.exists(p):
                os.remove(p)
        except OSError:
            pass


# ──────────────────────────────────────────────
# Helper: Jalankan DeepFace.verify di thread pool
# ──────────────────────────────────────────────
def _run_verify(captured_path: str, master_path: str) -> dict:
    """
    🚀 OPTIMASI: Fungsi synchronous untuk dijalankan di thread pool.
    Ini mencegah CPU-bound inference memblok event loop async.
    """
    return DeepFace.verify(
        img1_path=captured_path,
        img2_path=master_path,
        model_name=MODEL_NAME,
        distance_metric=DISTANCE_METRIC,
        detector_backend=DETECTOR_BACKEND,
        enforce_detection=False,
        align=True,
    )


# ──────────────────────────────────────────────
# Health Check
# ──────────────────────────────────────────────
@app.get("/")
@app.get("/health")
async def health_check():
    return {
        "success": True,
        "message": "Face Recognition Microservice berjalan.",
        "model": MODEL_NAME,
        "detector": DETECTOR_BACKEND,
        "metric": DISTANCE_METRIC,
        "threshold": MIN_CONFIDENCE_PERCENT,
    }


# ──────────────────────────────────────────────
# Endpoint Utama: POST /compare
# ──────────────────────────────────────────────
@app.post("/compare")
async def compare_faces(
    captured_image: UploadFile | None = File(None, description="Foto wajah yang baru diambil (absensi)"),
    master_image: UploadFile | None = File(None, description="Foto master / referensi wajah user"),
    image_file1: UploadFile | None = File(None, description="Foto master (alias compatibility)"),
    image_file2: UploadFile | None = File(None, description="Foto absensi (alias compatibility)"),
):
    """
    Membandingkan dua gambar wajah dan mengembalikan hasil verifikasi.
    Mendukung input captured_image & master_image maupun alias image_file1 & image_file2.

    Returns:
        JSON:
            - success    (bool)  : Apakah proses berhasil tanpa error
            - verified   (bool)  : Apakah wajah cocok
            - distance   (float) : Jarak cosine antar embedding wajah
            - confidence (float) : Skor kemiripan 0 – 100
            - threshold  (float) : Batas minimal kemiripan wajah
            - thresholds (dict)  : Thresholds kompatibilitas sistem absensi
    """
    # Resolusi file: fleksibel mendukung format form-data backend / mobile / frontend
    target_captured = captured_image or image_file2
    target_master = master_image or image_file1

    if not target_captured or not target_master:
        return JSONResponse(
            status_code=400,
            content={
                "success": False,
                "verified": False,
                "distance": None,
                "confidence": 0.0,
                "error": "Dua foto wajah wajib diunggah: captured_image dan master_image.",
                "message": "Dua foto wajah wajib diunggah: captured_image dan master_image.",
            },
        )

    captured_path: str | None = None
    master_path: str | None = None

    try:
        # 1. Simpan file yang diupload ke disk sementara (termasuk resize otomatis)
        captured_path = await save_temp_file(target_captured)
        master_path = await save_temp_file(target_master)

        logger.info(
            "🔍 Memproses verifikasi wajah — captured: %s, master: %s",
            os.path.basename(captured_path),
            os.path.basename(master_path),
        )

        # 2. 🚀 OPTIMASI: Jalankan verifikasi di thread pool agar tidak block event loop
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            _executor,
            partial(_run_verify, captured_path, master_path),
        )

        # 3. Ekstrak hasil
        distance: float = round(result.get("distance", 1.0), 6)

        # Hitung skor kemiripan wajah (0 s/d 100%)
        # Untuk cosine distance: 0.0 = 100% cocok, 1.0 = 0% cocok
        raw_confidence = (1.0 - distance) * 100.0
        confidence = round(max(0.0, min(100.0, raw_confidence)), 2)

        # Wajah dinyatakan COCOK jika skor kemiripan >= MIN_CONFIDENCE_PERCENT
        verified: bool = bool(confidence >= MIN_CONFIDENCE_PERCENT)

        logger.info(
            "✅ Hasil verifikasi — verified=%s, confidence=%.2f%% (Minimal: %.2f%%), distance=%.6f",
            verified, confidence, MIN_CONFIDENCE_PERCENT, distance,
        )

        return JSONResponse(content={
            "success": True,
            "verified": verified,
            "distance": distance,
            "threshold": MIN_CONFIDENCE_PERCENT,
            "confidence": confidence,
            "thresholds": {
                "1e-3": MIN_CONFIDENCE_PERCENT,
                "1e-4": 70.0,
                "1e-5": 80.0,
            },
        })

    except ValueError as ve:
        # DeepFace melempar ValueError jika wajah tidak terdeteksi
        error_msg = str(ve)
        logger.warning("⚠️ Wajah tidak terdeteksi: %s", error_msg)
        return JSONResponse(
            status_code=400,
            content={
                "success": False,
                "verified": False,
                "distance": None,
                "confidence": 0.0,
                "thresholds": {
                    "1e-3": MIN_CONFIDENCE_PERCENT,
                    "1e-4": 70.0,
                    "1e-5": 80.0,
                },
                "error": "Wajah tidak terdeteksi pada gambar. Pastikan foto menampilkan wajah dengan jelas.",
                "message": "Wajah tidak terdeteksi pada gambar. Pastikan foto menampilkan wajah dengan jelas.",
            },
        )

    except Exception as exc:
        logger.error("❌ Error saat verifikasi wajah: %s", exc, exc_info=True)
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "verified": False,
                "distance": None,
                "confidence": 0.0,
                "thresholds": {
                    "1e-3": MIN_CONFIDENCE_PERCENT,
                    "1e-4": 70.0,
                    "1e-5": 80.0,
                },
                "error": f"Terjadi kesalahan saat memproses verifikasi wajah: {str(exc)}",
                "message": f"Terjadi kesalahan saat memproses verifikasi wajah: {str(exc)}",
            },
        )

    finally:
        # 4. Selalu hapus file sementara setelah pemrosesan selesai
        cleanup_files(captured_path, master_path)
        logger.info("🧹 File sementara dibersihkan.")


# ──────────────────────────────────────────────
# Entry point (untuk menjalankan langsung: python main.py)
# ──────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
    )
