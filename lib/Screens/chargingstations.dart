import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'chargingroute.dart';
import 'bookstation.dart';
import 'favorites_db.dart';

class FindStations extends StatefulWidget {
  const FindStations({super.key});

  @override
  State<FindStations> createState() => _FindStationsState();
}

class _FindStationsState extends State<FindStations> {
  // --- THEME COLORS ---
  final Color _primaryColor = const Color(0xFF0253A4);
  final Color _lightFillColor = const Color(0xFFE6EFF8);
  final Color _backgroundColor = const Color(0xFFF5F7FA);
  final Color _greyText = Colors.grey.shade600;

  // --- STATE ---
  bool _isNearbySelected = true;
  double _distanceValue = 5.0;
  String _selectedConnectorType = 'All';
  String _selectedAvailability = 'All';
  LatLng? _currentUserPosition;
  bool _isLoadingLocation = false;

  /// Favourite station IDs persisted in SQLite
  final Set<String> _favoriteIds = {};

  // --- FILTER OPTIONS ---
  static const List<String> _connectorTypes = [
    'All',
    'Type 1',
    'Type 2',
    'Type 3',
    'CCS2',
    'CHAdeMO',
    'GBT',
  ];
  static const List<String> _availabilityOptions = [
    'All',
    'Available',
    'Unavailable',
  ];

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _loadFavorites();
  }

  // ── LOAD FAVOURITES FROM SQLITE ───────────────────────────────────────────
  Future<void> _loadFavorites() async {
    final rows = await FavoritesDb.instance.getAllFavorites();
    if (mounted) {
      setState(() {
        _favoriteIds
          ..clear()
          ..addAll(rows.map((r) => r['station_id'] as String));
      });
    }
  }

  // ── TOGGLE FAVOURITE ──────────────────────────────────────────────────────
  Future<void> _toggleFavorite(
    String stationId,
    Map<String, dynamic> data,
  ) async {
    final isFav = _favoriteIds.contains(stationId);
    if (isFav) {
      await FavoritesDb.instance.removeFavorite(stationId);
      if (mounted) setState(() => _favoriteIds.remove(stationId));
      _showTopSnack('Removed from favourites');
    } else {
      await FavoritesDb.instance.addFavorite(stationId, data);
      if (mounted) setState(() => _favoriteIds.add(stationId));
      _showTopSnack('Added to favourites ⭐');
    }
  }

  // ── SNACK AT THE TOP OF THE SCREEN ───────────────────────────────────────
  void _showTopSnack(String msg) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              msg.contains('Added')
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 130,
          left: 16,
          right: 16,
        ),
      ),
    );
  }

  // ── GET USER LOCATION ─────────────────────────────────────────────────────
  Future<void> _getUserLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isLoadingLocation = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentUserPosition = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // ── DISTANCE CALCULATION ──────────────────────────────────────────────────
  double _calculateDistanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000.0;
  }

  // ── FILTER STATIONS ───────────────────────────────────────────────────────
  List<QueryDocumentSnapshot> _filterStations(
    List<QueryDocumentSnapshot> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      if (_selectedAvailability != 'All') {
        int availablePlugs =
            int.tryParse(data['available_plugs']?.toString() ?? '0') ?? 0;
        bool isAvailable = availablePlugs > 0;
        if (_selectedAvailability == 'Available' && !isAvailable) return false;
        if (_selectedAvailability == 'Unavailable' && isAvailable) return false;
      }

      if (_selectedConnectorType != 'All') {
        String rawConnectors =
            data['supported_connector_types']?.toString() ?? '';
        List<String> parts = rawConnectors
            .split(',')
            .map((e) => e.trim())
            .toList();
        bool hasConnector = parts.any(
          (part) => part.toLowerCase() == _selectedConnectorType.toLowerCase(),
        );
        if (!hasConnector) return false;
      }

      if (_isNearbySelected && _currentUserPosition != null) {
        double? lat = double.tryParse(data['latitude']?.toString() ?? '');
        double? lng = double.tryParse(data['longitude']?.toString() ?? '');
        if (lat == null || lng == null) return false;
        double distKm = _calculateDistanceKm(
          _currentUserPosition!.latitude,
          _currentUserPosition!.longitude,
          lat,
          lng,
        );
        if (distKm > _distanceValue) return false;
      }
      return true;
    }).toList();
  }

  // ── FILTER BOTTOM SHEET ───────────────────────────────────────────────────
  void _showFilterSheet(
    String title,
    List<String> options,
    String selected,
    ValueChanged<String> onSelected,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        if (selected != 'All')
                          TextButton(
                            onPressed: () {
                              onSelected('All');
                              Navigator.pop(ctx);
                            },
                            child: Text(
                              'Clear',
                              style: TextStyle(color: _primaryColor),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      // ← FIXED: subtract nav bar height so list never overflows
                      maxHeight:
                          MediaQuery.of(context).size.height * 0.45 -
                          MediaQuery.of(context).viewPadding.bottom -
                          21,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: options.length,
                      itemBuilder: (_, i) {
                        final opt = options[i];
                        final bool isSelected = selected == opt;
                        return ListTile(
                          title: Text(
                            opt,
                            style: TextStyle(
                              color: isSelected
                                  ? _primaryColor
                                  : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle, color: _primaryColor)
                              : const Icon(
                                  Icons.radio_button_unchecked,
                                  color: Colors.grey,
                                ),
                          onTap: () {
                            onSelected(opt);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── HEADER ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Find Charging Stations',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.black87),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // ── FIXED CONTROLS ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, thickness: 1, color: Colors.black12),
                  const SizedBox(height: 20),

                  // Toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildToggleButton(
                            'Nearby',
                            _isNearbySelected,
                          ),
                        ),
                        Expanded(
                          child: _buildToggleButton(
                            'All Stations',
                            !_isNearbySelected,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Location status
                  if (_isNearbySelected) ...[
                    const SizedBox(height: 10),
                    if (_isLoadingLocation)
                      Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _primaryColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Getting your location...',
                            style: TextStyle(color: _greyText, fontSize: 12),
                          ),
                        ],
                      )
                    else if (_currentUserPosition == null)
                      Row(
                        children: [
                          const Icon(
                            Icons.location_off,
                            color: Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Location unavailable — showing all stations.',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _getUserLocation,
                            child: Text(
                              'Retry',
                              style: TextStyle(
                                color: _primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: Colors.green.shade600,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Showing stations within ${_distanceValue.toInt()} km',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],

                  const SizedBox(height: 16),

                  // Filter dropdowns
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterDropdown(
                          label: _selectedConnectorType == 'All'
                              ? 'Connector Type'
                              : _selectedConnectorType,
                          isActive: _selectedConnectorType != 'All',
                          onTap: () => _showFilterSheet(
                            'Connector Type',
                            _connectorTypes,
                            _selectedConnectorType,
                            (val) =>
                                setState(() => _selectedConnectorType = val),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFilterDropdown(
                          label: _selectedAvailability == 'All'
                              ? 'Availability'
                              : _selectedAvailability,
                          isActive: _selectedAvailability != 'All',
                          onTap: () => _showFilterSheet(
                            'Availability',
                            _availabilityOptions,
                            _selectedAvailability,
                            (val) =>
                                setState(() => _selectedAvailability = val),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Active filter chips
                  if (_selectedConnectorType != 'All' ||
                      _selectedAvailability != 'All') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_selectedConnectorType != 'All')
                          _buildActiveFilterChip(
                            _selectedConnectorType,
                            () =>
                                setState(() => _selectedConnectorType = 'All'),
                          ),
                        if (_selectedAvailability != 'All')
                          _buildActiveFilterChip(
                            _selectedAvailability,
                            () => setState(() => _selectedAvailability = 'All'),
                          ),
                      ],
                    ),
                  ],

                  // Distance slider
                  if (_isNearbySelected) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Distance Radius',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _lightFillColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_distanceValue.toInt()} km',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: _primaryColor,
                        inactiveTrackColor: Colors.grey.shade300,
                        thumbColor: _primaryColor,
                        overlayColor: _primaryColor.withOpacity(0.1),
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10,
                        ),
                      ),
                      child: Slider(
                        value: _distanceValue,
                        min: 1,
                        max: 50,
                        divisions: 49,
                        onChanged: (val) =>
                            setState(() => _distanceValue = val),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── SCROLLABLE STATION LIST ──────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('No stations found.'));
                  }

                  final List<QueryDocumentSnapshot> filtered = _filterStations(
                    snapshot.data!.docs,
                  );

                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.ev_station_outlined,
                            size: 56,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isNearbySelected && _currentUserPosition != null
                                ? 'No stations within ${_distanceValue.toInt()} km\nof your location'
                                : 'No stations match the selected filters',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _greyText,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isNearbySelected && _currentUserPosition != null)
                            TextButton.icon(
                              onPressed: () => setState(
                                () => _distanceValue = (_distanceValue + 10)
                                    .clamp(1, 50),
                              ),
                              icon: Icon(Icons.add, color: _primaryColor),
                              label: Text(
                                'Increase radius',
                                style: TextStyle(color: _primaryColor),
                              ),
                            ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                    physics: const BouncingScrollPhysics(),
                    itemCount: filtered.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            '${filtered.length} station${filtered.length == 1 ? '' : 's'} found',
                            style: TextStyle(
                              color: _greyText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }

                      final doc = filtered[index - 1];
                      final data = doc.data() as Map<String, dynamic>;

                      int availablePlugs =
                          int.tryParse(
                            data['available_plugs']?.toString() ?? '0',
                          ) ??
                          0;
                      int totalSlots =
                          int.tryParse(
                            data['connector_slots']?.toString() ?? '0',
                          ) ??
                          0;
                      bool isAvailable = availablePlugs > 0;

                      String rawConnectors =
                          data['supported_connector_types']?.toString() ??
                          'Unknown';
                      List<String> connectorList = rawConnectors
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();

                      double? lat = double.tryParse(
                        data['latitude']?.toString() ?? '',
                      );
                      double? lng = double.tryParse(
                        data['longitude']?.toString() ?? '',
                      );
                      String stationName =
                          data['station_name']?.toString() ?? 'Unknown Station';

                      String distanceText = 'N/A';
                      if (_currentUserPosition != null &&
                          lat != null &&
                          lng != null) {
                        double distKm = _calculateDistanceKm(
                          _currentUserPosition!.latitude,
                          _currentUserPosition!.longitude,
                          lat,
                          lng,
                        );
                        distanceText = distKm < 1
                            ? '${(distKm * 1000).toInt()} m away'
                            : '${distKm.toStringAsFixed(1)} km away';
                      }

                      return _buildStationCard(
                        doc: doc,
                        name: stationName,
                        address:
                            data['address']?.toString() ??
                            ((lat != null && lng != null)
                                ? 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}'
                                : 'Location unavailable'),
                        distance: distanceText,
                        availabilityText:
                            '$availablePlugs/$totalSlots Available',
                        power:
                            '${data['charging_power']?.toString() ?? '0'} kW',
                        connectors: connectorList,
                        statusColor: isAvailable ? Colors.green : Colors.red,
                        isAvailable: isAvailable,
                        stationLatLng: (lat != null && lng != null)
                            ? LatLng(lat, lng)
                            : null,
                        stationName: stationName,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WIDGET HELPERS ─────────────────────────────────────────────────────────

  Widget _buildToggleButton(String text, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() => _isNearbySelected = (text == 'Nearby'));
        if (text == 'Nearby' && _currentUserPosition == null) {
          _getUserLocation();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : _greyText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isActive ? _lightFillColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? _primaryColor.withOpacity(0.5)
                : Colors.transparent,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? _primaryColor : Colors.black87,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              color: isActive ? _primaryColor : _greyText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: Colors.white, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStationCard({
    required QueryDocumentSnapshot doc,
    required String name,
    required String address,
    required String distance,
    required String availabilityText,
    required String power,
    required List<String> connectors,
    required Color statusColor,
    required bool isAvailable,
    required LatLng? stationLatLng,
    required String stationName,
  }) {
    final data = doc.data() as Map<String, dynamic>;
    final bool isFav = _favoriteIds.contains(doc.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0253A4).withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      address,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // ── ⭐ FAVOURITE STAR BUTTON ──────────────────────────────────
              GestureDetector(
                onTap: () => _toggleFavorite(doc.id, data),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isFav ? Colors.amber.shade50 : Colors.grey.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isFav
                          ? Colors.amber.shade300
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Icon(
                    isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isFav ? Colors.amber.shade600 : Colors.grey.shade400,
                    size: 22,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Availability badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      availabilityText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 16),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.near_me, size: 18, color: _primaryColor),
                  const SizedBox(width: 6),
                  Text(
                    distance,
                    style: TextStyle(
                      color: _greyText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.flash_on, size: 18, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    power,
                    style: TextStyle(
                      color: _greyText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Connector chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: connectors
                .map(
                  (c) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _lightFillColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        color: _primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isAvailable
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BookStation(
                                preSelectedStationId: doc.id,
                                preSelectedStationName: stationName,
                                stationData: data,
                              ),
                            ),
                          )
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAvailable
                          ? _primaryColor
                          : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      isAvailable ? 'Book' : 'Full',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: stationLatLng == null
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChargingRoute(
                                destination: stationLatLng,
                                destinationName: stationName,
                              ),
                            ),
                          ),
                    icon: Icon(
                      Icons.directions,
                      size: 20,
                      color: _primaryColor,
                    ),
                    label: Text(
                      'Route',
                      style: TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _primaryColor, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
