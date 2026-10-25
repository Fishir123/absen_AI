import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/attendance_service.dart';
import '../widgets/liquid_glass.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _historyList = [];
  AttendanceStats _stats = const AttendanceStats();
  bool _isLoading = true;
  String? _errorMessage;

  // State Filter
  // filterMode: 'month' (default), 'date', 'year', 'all'
  String _filterMode = 'month';
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  DateTime? _selectedDate;

  final List<String> _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  /// Mengambil data statistik dan riwayat absensi berdasarkan filter yang aktif
  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? dateParam;
      int? monthParam;
      int? yearParam;

      if (_filterMode == 'date' && _selectedDate != null) {
        dateParam = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      } else if (_filterMode == 'month') {
        monthParam = _selectedMonth;
        yearParam = _selectedYear;
      } else if (_filterMode == 'year') {
        yearParam = _selectedYear;
      }

      // Ambil statistik diagram dan list riwayat secara paralel
      final results = await Future.wait([
        AttendanceService.getMyStatistics(
          date: dateParam,
          month: monthParam,
          year: yearParam,
        ),
        AttendanceService.getMyHistory(
          limit: 100,
          date: dateParam,
          month: monthParam,
          year: yearParam,
        ),
      ]);

      if (mounted) {
        setState(() {
          _stats = results[0] as AttendanceStats;
          _historyList = results[1] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  /// Label teks filter yang sedang aktif
  String get _currentFilterLabel {
    if (_filterMode == 'date' && _selectedDate != null) {
      return DateFormat('d MMMM yyyy', 'id_ID').format(_selectedDate!);
    } else if (_filterMode == 'month') {
      return '${_monthNames[_selectedMonth - 1]} $_selectedYear';
    } else if (_filterMode == 'year') {
      return 'Tahun $_selectedYear';
    }
    return 'Semua Data';
  }

  /// Modal dialog pemilih tanggal / bulan / tahun
  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        int tempYear = _selectedYear;
        int tempMonth = _selectedMonth;
        String tempMode = _filterMode;
        DateTime? tempDate = _selectedDate ?? DateTime.now();

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header Modal
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filter Log & Grafik',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Segmented Filter Mode
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _buildModeTab('Per Bulan', 'month', tempMode, () {
                          setModalState(() => tempMode = 'month');
                        }),
                        _buildModeTab('Per Tanggal', 'date', tempMode, () {
                          setModalState(() => tempMode = 'date');
                        }),
                        _buildModeTab('Per Tahun', 'year', tempMode, () {
                          setModalState(() => tempMode = 'year');
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Konten sesuai Mode
                  if (tempMode == 'month') ...[
                    // Pilihan Tahun
                    const Text('Pilih Tahun', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [DateTime.now().year - 1, DateTime.now().year, DateTime.now().year + 1].map((y) {
                          final isSel = tempYear == y;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('$y'),
                              selected: isSel,
                              selectedColor: const Color(0xFF1E5A8A),
                              labelStyle: TextStyle(
                                color: isSel ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (_) => setModalState(() => tempYear = y),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pilihan Bulan
                    const Text('Pilih Bulan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(12, (index) {
                        final mIndex = index + 1;
                        final isSel = tempMonth == mIndex;
                        return ChoiceChip(
                          label: Text(_monthNames[index]),
                          selected: isSel,
                          selectedColor: const Color(0xFF1E5A8A),
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : Colors.black87,
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (_) => setModalState(() => tempMonth = mIndex),
                        );
                      }),
                    ),
                  ] else if (tempMode == 'date') ...[
                    // Pilihan Tanggal Spesifik
                    const Text('Pilih Tanggal Tertentu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: tempDate ?? DateTime.now(),
                          firstDate: DateTime(2023),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setModalState(() => tempDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 20, color: Color(0xFF1E5A8A)),
                            const SizedBox(width: 12),
                            Text(
                              tempDate != null
                                  ? DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(tempDate!)
                                  : 'Ketuk untuk memilih tanggal',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (tempMode == 'year') ...[
                    // Pilihan Tahun Penuh
                    const Text('Pilih Tahun (12 Bulan Penuh)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: [2024, 2025, 2026, 2027].map((y) {
                        final isSel = tempYear == y;
                        return ChoiceChip(
                          label: Text('Tahun $y', style: TextStyle(fontSize: 13, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: isSel ? Colors.white : Colors.black87)),
                          selected: isSel,
                          selectedColor: const Color(0xFF1E5A8A),
                          onSelected: (_) => setModalState(() => tempYear = y),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Tombol Terapkan & Reset
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _filterMode = 'month';
                              _selectedMonth = DateTime.now().month;
                              _selectedYear = DateTime.now().year;
                              _selectedDate = null;
                            });
                            _fetchData();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          child: const Text('Bulan Ini', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _filterMode = tempMode;
                              _selectedYear = tempYear;
                              _selectedMonth = tempMonth;
                              _selectedDate = tempDate;
                            });
                            _fetchData();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E5A8A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('Terapkan Filter', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModeTab(String label, String mode, String currentMode, VoidCallback onTap) {
    final isSelected = mode == currentMode;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF1E5A8A) : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color text;
    IconData icon;

    switch (status) {
      case 'Clock In':
      case 'Hadir':
        bg = const Color(0xFFDCFCE7);
        text = const Color(0xFF15803D);
        icon = Icons.login_rounded;
        break;
      case 'Clock Out':
        bg = const Color(0xFFE0F2FE);
        text = const Color(0xFF0369A1);
        icon = Icons.logout_rounded;
        break;
      case 'Izin':
        bg = const Color(0xFFF3E8FF);
        text = const Color(0xFF7E22CE);
        icon = Icons.event_note_rounded;
        break;
      case 'Di Luar Radius':
        bg = const Color(0xFFFFE4E6);
        text = const Color(0xFFBE123C);
        icon = Icons.location_off_outlined;
        break;
      default:
        bg = const Color(0xFFFEF3C7);
        text = const Color(0xFFB45309);
        icon = Icons.warning_amber_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: text, size: 12),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(color: text, fontSize: 10.5, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Widget Diagram Batang yang dibuat persis seperti gambar pengguna
  Widget _buildBarChartCard() {
    // 4 Kategori seperti di sketsa pengguna
    final items = [
      {'label': 'ci&co', 'value': _stats.ciAndCo, 'desc': 'Clock In & Clock Out'},
      {'label': 'ci not co', 'value': _stats.ciNotCo, 'desc': 'Clock In Tanpa Clock Out'},
      {'label': 'izin', 'value': _stats.izin, 'desc': 'Izin Disetujui'},
      {'label': 'alpha', 'value': _stats.alpha, 'desc': 'Alpha / Tidak Hadir'},
    ];

    final int maxVal = _stats.maxVal > 0 ? _stats.maxVal : 1;
    const double chartPlotHeight = 150.0;
    const Color barColor = Color(0xFF1E5A8A); // Warna biru tua persis di gambar

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card: Judul & Filter Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: barColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bar_chart_rounded, color: barColor, size: 20),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Diagram Absensi',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              // Tombol filter interaktif
              InkWell(
                onTap: _showFilterBottomSheet,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 13, color: barColor),
                      const SizedBox(width: 5),
                      Text(
                        _currentFilterLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: barColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 16, color: barColor),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Area Diagram Batang Sesuai Gambar
          SizedBox(
            height: chartPlotHeight + 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Sumbu Y Vertikal dengan label "jumlah"
                Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              'jumlah',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Garis Sumbu Vertikal Hitam / Abu Gelap
                          Container(
                            width: 2,
                            color: const Color(0xFF334155),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26), // Ruang sejajar sumbu X label
                  ],
                ),

                // 2. Plot Area Batang & Sumbu X
                Expanded(
                  child: Column(
                    children: [
                      // Batang & Angka di Atasnya
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: items.map((item) {
                            final int val = item['value'] as int;
                            // Rasio tinggi batang (minimal 4px jika val > 0 agar tetap terlihat)
                            final double heightFactor = val / maxVal;
                            final double barHeight = val == 0
                                ? 2.0
                                : (heightFactor * (chartPlotHeight - 32)).clamp(6.0, chartPlotHeight - 20);

                            return Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Angka di atas batang (persis seperti 15, 11, 4, 1 di gambar)
                                  Text(
                                    '$val',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: val > 0 ? const Color(0xFF0F172A) : Colors.grey.shade400,
                                    ),
                                  ),
                                  const SizedBox(height: 4),

                                  // Batang Biru Tua (Animated)
                                  TweenAnimationBuilder<double>(
                                    tween: Tween<double>(begin: 0, end: barHeight),
                                    duration: const Duration(milliseconds: 600),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, animatedH, _) {
                                      return Container(
                                        width: 36,
                                        height: animatedH,
                                        decoration: BoxDecoration(
                                          color: barColor,
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                          boxShadow: val > 0
                                              ? [
                                                  BoxShadow(
                                                    color: barColor.withValues(alpha: 0.25),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      // Garis Sumbu Horizontal Hitam
                      Container(
                        height: 2,
                        color: const Color(0xFF334155),
                      ),

                      const SizedBox(height: 6),

                      // Label Kategori di Bawah: ci&co, ci not co, izin, alpha
                      Row(
                        children: items.map((item) {
                          final label = item['label'] as String;
                          return Expanded(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: 10),

          // Keterangan / Ringkasan Mini Badge di bawah chart
          Row(
            children: [
              _buildMiniBadge('ci&co', '${_stats.ciAndCo}', const Color(0xFF0284C7)),
              const SizedBox(width: 6),
              _buildMiniBadge('ci not co', '${_stats.ciNotCo}', const Color(0xFFD97706)),
              const SizedBox(width: 6),
              _buildMiniBadge('izin', '${_stats.izin}', const Color(0xFF9333EA)),
              const SizedBox(width: 6),
              _buildMiniBadge('alpha', '${_stats.alpha}', const Color(0xFFDC2626)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String title, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              val,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: LiquidGlassAppBar(
        title: 'Riwayat Presensi',
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: _showFilterBottomSheet,
            tooltip: 'Filter Tanggal',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
            tooltip: 'Muat Ulang',
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'lib/asset/baground/BG.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: const Color(0xFF365C4A)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.20),
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.30),
                ],
              ),
            ),
          ),
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF365C4A)))
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_off, size: 48, color: Colors.white70),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13, color: Colors.white),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _fetchData,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E5A8A),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Coba Lagi'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchData,
                        color: const Color(0xFF1E5A8A),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          children: [
                            // 1. KARTU DIAGRAM BATANG
                            _buildBarChartCard(),

                            const SizedBox(height: 16),

                            // 2. SUBHEADER LOG PRESENSI
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Log Riwayat',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${_historyList.length}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  _currentFilterLabel,
                                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // 3. DAFTAR LOG PRESENSI
                            if (_historyList.isEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.event_busy_outlined, size: 44, color: Colors.black26),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tidak ada catatan presensi pada $_currentFilterLabel.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _historyList.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = _historyList[index];
                                  final createdAt = item['created_at'] != null
                                      ? DateTime.tryParse(item['created_at'])?.toLocal()
                                      : null;

                                  final dateStr = createdAt != null
                                      ? DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(createdAt)
                                      : '-';
                                  final timeStr = createdAt != null
                                      ? DateFormat('HH:mm:ss').format(createdAt)
                                      : '-';

                                  final status = item['status']?.toString() ?? 'Hadir';
                                  final isClockOut = status == 'Clock Out';
                                  final distance = item['distance'];
                                  final confidence = item['face_confidence'];

                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                dateStr,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF242721),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildStatusBadge(status),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time, size: 14, color: Colors.black38),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$timeStr WIB',
                                              style: const TextStyle(fontSize: 12, color: Colors.black54, fontFamily: 'monospace'),
                                            ),
                                            if (!isClockOut && distance != null) ...[
                                              const Spacer(),
                                              const Icon(Icons.near_me_outlined, size: 14, color: Colors.black38),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  'Jarak: ${(distance as num).toStringAsFixed(0)} m',
                                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (!isClockOut && confidence != null) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Kemiripan Wajah: ${(confidence as num).toStringAsFixed(1)}%',
                                            style: const TextStyle(fontSize: 11, color: Colors.black45),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
