import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chargepath/Theme/app_colors.dart';
import 'package:chargepath/Theme/app_spacing.dart';
import 'package:chargepath/Widgets/app_card.dart';
import 'package:chargepath/Widgets/app_section_header.dart';

class BookStation extends StatefulWidget {
  final String? preSelectedStationId;
  final String? preSelectedStationName;
  final Map<String, dynamic>? stationData;

  const BookStation({
    super.key,
    this.preSelectedStationId,
    this.preSelectedStationName,
    this.stationData,
  });

  @override
  State<BookStation> createState() => _BookStationState();
}

class _BookStationState extends State<BookStation> {
  // --- STATION DROPDOWN STATE ---
  String? _selectedStationId;
  String? _selectedStationName;
  Map<String, dynamic>? _selectedStationData;
  List<Map<String, dynamic>> _allStations = [];
  bool _isLoadingStations = true;

  // --- DATE & TIME STATE ---
  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;

  @override

  void initState() {
    super.initState();
    if (widget.preSelectedStationId != null) {
      _selectedStationId = widget.preSelectedStationId;
      _selectedStationName = widget.preSelectedStationName;
      _selectedStationData = widget.stationData;
    }
    _loadAllStations();
  }

  // ── LOAD ALL STATIONS FROM FIREBASE ───────────────────────────────────────
  Future<void> _loadAllStations() async {
    try {
      final snapshot =
      await FirebaseFirestore.instance.collection('users').get();
      final List<Map<String, dynamic>> stations = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = data['station_name']?.toString() ?? 'Unknown Station';
        stations.add({'id': doc.id, 'name': name, 'data': data});
      }
      if (mounted) {
        setState(() {
          _allStations = stations;
          _isLoadingStations = false;
          if (_selectedStationId != null && _selectedStationData == null) {
            final match = stations.firstWhere(
                  (s) => s['id'] == _selectedStationId,
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              _selectedStationName = match['name'];
              _selectedStationData = match['data'];
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading stations: $e');
      if (mounted) setState(() => _isLoadingStations = false);
    }
  }

  // ── DURATION CALCULATION ──────────────────────────────────────────────────
  Duration? _getDuration() {
    if (_startDate == null ||
        _startTime == null ||
        _endDate == null ||
        _endTime == null) return null;
    final start = DateTime(
      _startDate!.year,
      _startDate!.month,
      _startDate!.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    final end = DateTime(
      _endDate!.year,
      _endDate!.month,
      _endDate!.day,
      _endTime!.hour,
      _endTime!.minute,
    );
    if (end.isAfter(start)) return end.difference(start);
    return null;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  double _getTotalCost(Duration d) {
    final double hourlyRate = double.tryParse(
        _selectedStationData?['price_per_hour']?.toString() ?? '12.50') ??
        12.50;
    return (d.inMinutes / 60.0) * hourlyRate;
  }

  double _getHourlyRate() {
    return double.tryParse(
        _selectedStationData?['price_per_hour']?.toString() ?? '12.50') ??
        12.50;
  }

  // ── DATE / TIME PICKERS ───────────────────────────────────────────────────
  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => _calendarTheme(ctx, child),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
      builder: (ctx, child) => _calendarTheme(ctx, child),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now()),
      firstDate: _startDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => _calendarTheme(ctx, child),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
      builder: (ctx, child) => _calendarTheme(ctx, child),
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  Widget _calendarTheme(BuildContext ctx, Widget? child) {
    return Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: AppColors.textPrimary,
        ),
        dialogBackgroundColor: Colors.white,
      ),
      child: child!,
    );
  }

  // ── VALIDATION ────────────────────────────────────────────────────────────
  bool _isFormValid() {
    return _selectedStationId != null &&
        _startDate != null &&
        _startTime != null &&
        _endDate != null &&
        _endTime != null &&
        _getDuration() != null;
  }

  // ── CONFIRMATION POPUP ────────────────────────────────────────────────────
  void _showConfirmationPopup() {
    final duration = _getDuration()!;
    final totalCost = _getTotalCost(duration);
    final deposit = totalCost * 0.10;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── SUCCESS ICON ─────────────────────────────────────────────
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 52,
                  color: Color(0xFF0253A4),
                ),
              ),
              const SizedBox(height: 20),

              // ── TITLE ────────────────────────────────────────────────────
              const Text(
                'Booking Confirmed!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your charging slot has been\nsuccessfully reserved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // ── BOOKING DETAILS BOX ───────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.lightFill,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _popupDetailRow(
                      Icons.ev_station_rounded,
                      'Station',
                      _selectedStationName ?? '',
                    ),
                    const SizedBox(height: 10),
                    _popupDetailRow(
                      Icons.calendar_today_rounded,
                      'Date',
                      '${_formatDate(_startDate!)} → ${_formatDate(_endDate!)}',
                    ),
                    const SizedBox(height: 10),
                    _popupDetailRow(
                      Icons.access_time_rounded,
                      'Time',
                      '${_startTime!.format(context)} → ${_endTime!.format(context)}',
                    ),
                    const SizedBox(height: 10),
                    _popupDetailRow(
                      Icons.timer_rounded,
                      'Duration',
                      _formatDuration(duration),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: Color(0xFF0253A4), thickness: 0.4),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Deposit Paid',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Rs.${deposit.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF0253A4),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Cost',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Rs.${totalCost.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── OK BUTTON ─────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    // ← FIXED: pop back to MainScreen instead of pushing
                    // FindStations directly, so the nav bar is preserved
                    Navigator.of(ctx).pop(); // close dialog
                    Navigator.of(context)
                        .popUntil((route) => route.isFirst); // back to MainScreen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 4,
                    shadowColor: AppColors.primary.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'OK, Got it!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _popupDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useWideLayout = constraints.maxWidth >= 900;

        if (useWideLayout) {
          return _buildWideLayout();
        }

        return _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    final Duration? duration = _getDuration();
    final double hourlyRate = _getHourlyRate();
    final double totalCost =
    duration != null ? _getTotalCost(duration) : 0;
    final double deposit = totalCost * 0.10;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildMobileHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  MediaQuery.of(context).padding.bottom + 110,
                ),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildStationSelectionCard(),
                    const SizedBox(height: AppSpacing.lg),
                    _buildTimePeriodCard(duration),
                    const SizedBox(height: AppSpacing.lg),
                    _buildPricingCard(
                      duration: duration,
                      hourlyRate: hourlyRate,
                      totalCost: totalCost,
                      deposit: deposit,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildConfirmButton(deposit),
                    const SizedBox(height: AppSpacing.md),
                    _buildBalanceNotice(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Material(
                color: Colors.white.withOpacity(0.15),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text(
                  'Book Station',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: 49),
            child: Text(
              'Choose a charging station and reserve a time slot.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.80),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    final Duration? duration = _getDuration();
    final double hourlyRate = _getHourlyRate();
    final double totalCost =
    duration != null ? _getTotalCost(duration) : 0;
    final double deposit = totalCost * 0.10;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 380,
              decoration: BoxDecoration(
                color: AppColors.white,
                border: Border(
                  right: BorderSide(
                    color: Colors.grey.shade200,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _buildWideHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        24,
                      ),
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          _buildStationSelectionCard(
                            showShadow: false,
                          ),
                          const SizedBox(height: 18),
                          _buildTimePeriodCard(
                            duration,
                            showShadow: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool useSideSummary =
                        constraints.maxWidth >= 760;

                    if (useSideSummary) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildBookingOverviewCard(
                              duration: duration,
                              hourlyRate: hourlyRate,
                              totalCost: totalCost,
                              deposit: deposit,
                            ),
                          ),
                          const SizedBox(width: 22),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                _buildPricingCard(
                                  duration: duration,
                                  hourlyRate: hourlyRate,
                                  totalCost: totalCost,
                                  deposit: deposit,
                                ),
                                const SizedBox(height: 22),
                                _buildConfirmButton(deposit),
                                const SizedBox(height: 14),
                                _buildBalanceNotice(),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          _buildBookingOverviewCard(
                            duration: duration,
                            hourlyRate: hourlyRate,
                            totalCost: totalCost,
                            deposit: deposit,
                          ),
                          const SizedBox(height: 20),
                          _buildPricingCard(
                            duration: duration,
                            hourlyRate: hourlyRate,
                            totalCost: totalCost,
                            deposit: deposit,
                          ),
                          const SizedBox(height: 24),
                          _buildConfirmButton(deposit),
                          const SizedBox(height: 14),
                          _buildBalanceNotice(),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        22,
        24,
        22,
        20,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Material(
                color: Colors.white.withOpacity(0.15),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Book Station',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Choose a charging station and reserve a time slot.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.80),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationSelectionCard({
    bool showShadow = true,
  }) {
    return _buildSectionCard(
      title: 'Select Charging Station',
      showShadow: showShadow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoadingStations)
            Container(
              height: 54,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedStationId,
                  hint: Text(
                    'Choose a station...',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  isExpanded: true,
                  icon: const Icon(
                    Icons.expand_more,
                  ),
                  items: _allStations.map((station) {
                    return DropdownMenuItem<String>(
                      value: station['id'] as String,
                      child: Text(
                        station['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    final Map<String, dynamic> match =
                    _allStations.firstWhere(
                          (station) => station['id'] == value,
                      orElse: () => <String, dynamic>{},
                    );

                    setState(() {
                      _selectedStationId = value;
                      _selectedStationName =
                      match['name'] as String?;
                      _selectedStationData =
                      match['data'] as Map<String, dynamic>?;
                    });
                  },
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_selectedStationData != null) ...[
            Row(
              children: [
                Icon(
                  Icons.flash_on,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_selectedStationData!['charging_power']?.toString() ?? 'N/A'} kW  •  '
                        '${_selectedStationData!['available_plugs']?.toString() ?? '?'}/'
                        '${_selectedStationData!['connector_slots']?.toString() ?? '?'} plugs available',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedStationData!['address']?.toString() ??
                        'Address not available',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ] else
            Row(
              children: [
                Icon(
                  Icons.flash_on,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Fast charging available',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTimePeriodCard(
      Duration? duration, {
        bool showShadow = true,
      }) {
    return _buildSectionCard(
      title: 'Select Time Period',
      showShadow: showShadow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('Start Date & Time'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTappableField(
                  hint: 'dd/mm/yyyy',
                  value: _startDate != null
                      ? _formatDate(_startDate!)
                      : null,
                  icon: Icons.calendar_today_outlined,
                  onTap: _pickStartDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTappableField(
                  hint: '--:-- --',
                  value: _startTime?.format(context),
                  icon: Icons.access_time_outlined,
                  onTap: _pickStartTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildLabel('End Date & Time'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTappableField(
                  hint: 'dd/mm/yyyy',
                  value: _endDate != null
                      ? _formatDate(_endDate!)
                      : null,
                  icon: Icons.calendar_today_outlined,
                  onTap: _pickEndDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTappableField(
                  hint: '--:-- --',
                  value: _endTime?.format(context),
                  icon: Icons.access_time_outlined,
                  onTap: _pickEndTime,
                ),
              ),
            ],
          ),
          if (duration != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Duration',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_startDate != null &&
              _startTime != null &&
              _endDate != null &&
              _endTime != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 16,
              ),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.red.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade400,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'End time must be after start time',
                      style: TextStyle(
                        color: Colors.red.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPricingCard({
    required Duration? duration,
    required double hourlyRate,
    required double totalCost,
    required double deposit,
  }) {
    return _buildSectionCard(
      title: 'Pricing Details',
      child: Column(
        children: [
          _buildPriceRow(
            'Hourly Rate',
            'Rs.${hourlyRate.toStringAsFixed(2)}/hr',
          ),
          const SizedBox(height: 12),
          _buildPriceRow(
            'Duration',
            duration != null
                ? _formatDuration(duration)
                : '—',
          ),
          const SizedBox(height: 16),
          Divider(
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Cost',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                ),
              ),
              Text(
                duration != null
                    ? 'Rs.${totalCost.toStringAsFixed(2)}'
                    : '—',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.lightFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Deposit Required',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(
                        text: '10% of total cost — ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: duration != null
                            ? "You'll pay Rs.${deposit.toStringAsFixed(2)} now to secure your booking"
                            : 'Select dates and times to calculate the deposit',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingOverviewCard({
    required Duration? duration,
    required double hourlyRate,
    required double totalCost,
    required double deposit,
  }) {
    return _buildSectionCard(
      title: 'Booking Overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewRow(
            icon: Icons.ev_station_rounded,
            label: 'Station',
            value: _selectedStationName ?? 'Not selected',
          ),
          const SizedBox(height: 14),
          _buildOverviewRow(
            icon: Icons.calendar_today_rounded,
            label: 'Start',
            value: _startDate != null && _startTime != null
                ? '${_formatDate(_startDate!)} at ${_startTime!.format(context)}'
                : 'Not selected',
          ),
          const SizedBox(height: 14),
          _buildOverviewRow(
            icon: Icons.event_available_rounded,
            label: 'End',
            value: _endDate != null && _endTime != null
                ? '${_formatDate(_endDate!)} at ${_endTime!.format(context)}'
                : 'Not selected',
          ),
          const SizedBox(height: 14),
          _buildOverviewRow(
            icon: Icons.timer_rounded,
            label: 'Duration',
            value: duration != null
                ? _formatDuration(duration)
                : 'Not calculated',
          ),
          const SizedBox(height: 14),
          _buildOverviewRow(
            icon: Icons.payments_rounded,
            label: 'Estimated total',
            value: duration != null
                ? 'Rs.${totalCost.toStringAsFixed(2)}'
                : 'Not calculated',
          ),
          const SizedBox(height: 14),
          _buildOverviewRow(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Deposit',
            value: duration != null
                ? 'Rs.${deposit.toStringAsFixed(2)}'
                : 'Not calculated',
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.12),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Complete the station and time selections before confirming the booking.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.lightFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: AppColors.primary,
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmButton(double deposit) {
    final bool isValid = _isFormValid();

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isValid
            ? _showConfirmationPopup
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: Colors.grey.shade300,
          elevation: isValid ? 4 : 0,
          shadowColor: AppColors.primary.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          isValid
              ? 'Confirm Booking — Pay Rs.${deposit.toStringAsFixed(2)}'
              : 'Fill in all details to confirm',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isValid
                ? Colors.white
                : AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildBalanceNotice() {
    return Center(
      child: Text(
        'Remaining balance due upon arrival',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  // ── HELPER WIDGETS ─────────────────────────────────────────────────────────

  Widget _buildSectionCard({
    required String title,
    required Widget child,
    bool showShadow = true,
  }) {
    if (showShadow) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(
              icon: _sectionIconForTitle(title),
              title: title,
            ),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: _sectionIconForTitle(title),
            title: title,
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }

  IconData _sectionIconForTitle(String title) {
    switch (title) {
      case 'Select Charging Station':
        return Icons.ev_station_rounded;
      case 'Select Time Period':
        return Icons.schedule_rounded;
      case 'Pricing Details':
        return Icons.payments_rounded;
      case 'Booking Overview':
        return Icons.receipt_long_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTappableField({
    required String hint,
    required String? value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final bool hasValue = value != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: hasValue ? AppColors.lightFill : Colors.white,
          border: Border.all(
            color: hasValue
                ? AppColors.primary.withOpacity(0.4)
                : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                  color: hasValue ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight:
                  hasValue ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              icon,
              color: hasValue ? AppColors.primary : AppColors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}