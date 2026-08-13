import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:chargepath/Theme/app_colors.dart';
import 'package:chargepath/Theme/app_spacing.dart';
import 'package:chargepath/Widgets/app_card.dart';
import 'package:chargepath/Widgets/app_primary_button.dart';
import 'package:chargepath/Widgets/app_section_header.dart';
import 'chargingroute.dart';

class RoutePlanningPage extends StatefulWidget {
  const RoutePlanningPage({super.key});

  @override
  State<RoutePlanningPage> createState() => _RoutePlanningPageState();
}

class _RoutePlanningPageState extends State<RoutePlanningPage> {
  // --- CONFIGURATION ---
  final String _googleApiKey = "AIzaSyALER_NJqGFdwseum4UGUk_wTTYZbGK-es";


  double _currentBattery = 60.0;

  String _selectedConnector = "Type 1";
  static const List<String> _connectorOptions = [
    "Type 1",
    "Type 2",
    "Type 3",
    "CCS2",
    "CHAdeMO",
    "GBT",
  ];

  final Completer<GoogleMapController> _controller = Completer();
  bool _isLoading = false;

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  final TextEditingController _rangeController =
  TextEditingController(text: "100");

  List<dynamic> _routeStops = [];
  Set<Marker> _markers = {};
  double _totalDistance = 0.0;

  static const CameraPosition _kInitialLocation = CameraPosition(
    target: LatLng(6.9271, 79.8612),
    zoom: 10,
  );

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _rangeController.dispose();
    super.dispose();
  }

  Future<void> _fetchRoute() async {
    setState(() {
      _isLoading = true;
      _markers.clear();
      _routeStops.clear();
      _totalDistance = 0.0;
    });

    const String apiUrl = "https://chargepathmodel.onrender.com/plan_route";

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "start_point": _startController.text,
          "end_point": _endController.text,
          "max_range_km": int.tryParse(_rangeController.text) ?? 100,
          "current_battery_pct": _currentBattery.toInt(),
          "required_connector": _selectedConnector,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> results = data['Result'] ?? [];

        double dist = 0;
        for (var r in results) {
          dist += (r['DistancetoFind'] as num).toDouble();
        }

        setState(() {
          _routeStops = results;
          _totalDistance = dist;
          _generateMarkers(results);
        });

        if (results.isNotEmpty) {
          _fitMapBounds(results);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text("No charging stops needed or found.")),
            );
          }
        }
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _generateMarkers(List<dynamic> stops) {
    Set<Marker> newMarkers = {};
    for (var stop in stops) {
      final double lat = stop['Latitude'];
      final double lng = stop['Longitude'];
      final String name = stop['StationName'];

      newMarkers.add(Marker(
        markerId: MarkerId(name),
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(
          title: name,
          snippet:
          "Charge needed: ${stop['NeedChargePercentage']} — Tap to navigate",
        ),
        icon:
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChargingRoute(
                destination: LatLng(lat, lng),
                destinationName: name,
              ),
            ),
          );
        },
      ));
    }
    setState(() => _markers = newMarkers);
  }

  Future<void> _fitMapBounds(List<dynamic> stops) async {
    if (stops.isEmpty) return;
    double minLat = stops[0]['Latitude'], maxLat = stops[0]['Latitude'];
    double minLng = stops[0]['Longitude'], maxLng = stops[0]['Longitude'];

    for (var stop in stops) {
      double lat = stop['Latitude'];
      double lng = stop['Longitude'];
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.1, minLng - 0.1),
        northeast: LatLng(maxLat + 0.1, maxLng + 0.1),
      ),
      60,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useWideLayout = constraints.maxWidth >= 950;
        return useWideLayout ? _buildWideLayout() : _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildMobileHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  110,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRouteLocationsCard(),
                    const SizedBox(height: AppSpacing.lg),
                    _buildVehicleSettingsCard(),
                    const SizedBox(height: AppSpacing.xl),
                    _buildPlanRouteButton(),
                    const SizedBox(height: AppSpacing.xxl),
                    _buildMapCard(mapHeight: 220),
                    const SizedBox(height: AppSpacing.lg),
                    _buildChargingStopsCard(),
                    const SizedBox(height: AppSpacing.lg),
                    _buildTripSummaryCard(),
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
          const Row(
            children: [
              Icon(
                Icons.alt_route_rounded,
                color: Colors.white,
                size: 28,
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Route Planning',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Plan an EV-friendly journey using your battery, range, and connector requirements.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 370,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                children: [
                  _buildWideHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRouteLocationsCard(showShadow: false),
                          const SizedBox(height: 16),
                          _buildVehicleSettingsCard(showShadow: false),
                          const SizedBox(height: 20),
                          _buildPlanRouteButton(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool useSideDetails = constraints.maxWidth >= 760;
                    if (useSideDetails) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: _buildWideMapPanel()),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 2,
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                children: [
                                  _buildChargingStopsCard(),
                                  const SizedBox(height: 16),
                                  _buildTripSummaryCard(summaryColumns: 1),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(flex: 3, child: _buildWideMapPanel()),
                        const SizedBox(height: 16),
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              children: [
                                _buildChargingStopsCard(),
                                const SizedBox(height: 16),
                                _buildTripSummaryCard(),
                              ],
                            ),
                          ),
                        ),
                      ],
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
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.alt_route_rounded, color: Colors.white, size: 30), SizedBox(width: 12), Expanded(child: Text('Route Planning', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 8),
          Text('Plan an EV-friendly journey using your battery, range, and connector requirements.', style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 13, height: 1.45)),
        ],
      ),
    );
  }

  Widget _buildRouteLocationsCard({bool showShadow = true}) {
    return _buildCard(
      showShadow: showShadow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildSectionTitle('Plan Your Route', Icons.alt_route_rounded), const SizedBox(height: 20), _buildLocationHeader()]),
    );
  }

  Widget _buildVehicleSettingsCard({bool showShadow = true}) {
    return _buildCard(
      showShadow: showShadow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Vehicle Settings', Icons.electric_car_rounded),
          const SizedBox(height: 20),
          _buildBatterySlider(),
          const SizedBox(height: 20),
          _buildLabeledField(label: 'Max Range', sublabel: 'km', child: _buildBlueTextBox('e.g. 100', _rangeController, isNumber: true)),
          const SizedBox(height: 16),
          _buildConnectorSelector(),
        ],
      ),
    );
  }

  Widget _buildPlanRouteButton() {
    return AppPrimaryButton(
      text: _isLoading ? 'Planning...' : 'Plan Route',
      icon: Icons.navigation_rounded,
      isLoading: _isLoading,
      onPressed: _isLoading ? null : _fetchRoute,
    );
  }

  Widget _buildMapCard({required double mapHeight}) {
    return _buildCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildSectionTitle('Route Preview', Icons.map_rounded), const SizedBox(height: 16), _buildMapPreview(height: mapHeight)]));
  }

  Widget _buildWideMapPanel() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Expanded(child: _buildSectionTitle('Route Preview', Icons.map_rounded)), if (_routeStops.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.09), borderRadius: BorderRadius.circular(20)), child: Text('${_totalDistance.toStringAsFixed(1)} km', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 16),
          Expanded(child: _buildMapPreview(expand: true)),
        ],
      ),
    );
  }

  Widget _buildChargingStopsCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Expanded(child: _buildSectionTitle('Charging Stops', Icons.ev_station_rounded)), if (_routeStops.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.success.withOpacity(0.12), borderRadius: BorderRadius.circular(20)), child: Text('${_routeStops.length} stops', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 16),
          if (_routeStops.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Column(children: [Icon(Icons.ev_station_outlined, size: 48, color: Colors.grey.shade300), const SizedBox(height: 12), Text('Route not calculated yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 14))])))
          else
            ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _routeStops.length, itemBuilder: (context, index) => _buildStopItem(index + 1, _routeStops[index])),
        ],
      ),
    );
  }

  Widget _buildTripSummaryCard({int summaryColumns = 2}) {
    return _buildCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildSectionTitle('Trip Summary', Icons.summarize_rounded), const SizedBox(height: 16), _buildTripSummaryGrid(crossAxisCount: summaryColumns)]));
  }

  // ── WIDGET BUILDERS ───────────────────────────────────────────────────────

  /// Generic white card container
  Widget _buildCard({
    required Widget child,
    bool showShadow = true,
  }) {
    if (showShadow) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: child,
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
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return AppSectionHeader(
      icon: icon,
      title: title,
    );
  }

  /// Location header with Origin / Destination labels above each field
  Widget _buildLocationHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Vertical route line ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 34),
          child: Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              ...List.generate(
                6,
                    (_) => Container(
                  width: 2,
                  height: 8,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.red.shade500,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // ── Labeled input fields ────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Origin label + field
              _buildFieldLabel("Origin", Icons.my_location_rounded,
                  Colors.green.shade600),
              const SizedBox(height: 6),
              _buildBlueTextBox("Enter starting point", _startController),

              const SizedBox(height: 16),

              // Destination label + field
              _buildFieldLabel("Destination", Icons.location_on_rounded,
                  Colors.red.shade500),
              const SizedBox(height: 6),
              _buildBlueTextBox("Enter destination", _endController),
            ],
          ),
        ),
      ],
    );
  }

  /// Label row shown above each input field
  Widget _buildFieldLabel(String text, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  /// Helper to wrap a field with a label + optional sub-label
  Widget _buildLabeledField({
    required String label,
    String? sublabel,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            if (sublabel != null) ...[
              const SizedBox(width: 4),
              Text(
                "($sublabel)",
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildBlueTextBox(String hint, TextEditingController controller,
      {bool isNumber = false}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType:
        isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          suffixIcon: isNumber
              ? Icon(Icons.speed_rounded,
              size: 18, color: AppColors.primary.withOpacity(0.5))
              : Icon(Icons.search_rounded,
              size: 18, color: AppColors.primary.withOpacity(0.5)),
        ),
        style: const TextStyle(
            fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildConnectorSelector() {
    return _buildLabeledField(
      label: "Connector Type",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.lightFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedConnector,
            isExpanded: true,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.primary),
            items: _connectorOptions.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Row(
                  children: [
                    Icon(Icons.electrical_services_rounded,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      value,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (newValue) =>
                setState(() => _selectedConnector = newValue!),
          ),
        ),
      ),
    );
  }

  Widget _buildBatterySlider() {
    // Determine colour based on level
    final Color batteryColor = _currentBattery < 20
        ? Colors.red.shade500
        : _currentBattery < 50
        ? Colors.orange.shade600
        : AppColors.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Current Battery Level",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: batteryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentBattery > 70
                        ? Icons.battery_full_rounded
                        : _currentBattery > 30
                        ? Icons.battery_4_bar_rounded
                        : Icons.battery_1_bar_rounded,
                    color: batteryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "${_currentBattery.toInt()}%",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: batteryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: batteryColor,
            inactiveTrackColor: AppColors.lightFill,
            thumbColor: batteryColor,
            overlayColor: batteryColor.withOpacity(0.15),
            thumbShape:
            const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: _currentBattery,
            min: 0,
            max: 100,
            onChanged: (value) =>
                setState(() => _currentBattery = value),
          ),
        ),
      ],
    );
  }

  Widget _buildMapPreview({double? height, bool expand = false}) {
    final Widget map = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GoogleMap(
        mapType: MapType.normal,
        initialCameraPosition: _kInitialLocation,
        zoomControlsEnabled: false,
        markers: _markers,
        onMapCreated: (GoogleMapController controller) {
          if (!_controller.isCompleted) {
            _controller.complete(controller);
          }
        },
      ),
    );
    if (expand) {
      return SizedBox.expand(child: map);
    }
    return SizedBox(height: height ?? 200, width: double.infinity, child: map);
  }

  Widget _buildStopItem(int index, dynamic stop) {
    final double lat = stop['Latitude'];
    final double lng = stop['Longitude'];
    final String name = stop['StationName'];

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChargingRoute(
              destination: LatLng(lat, lng),
              destinationName: name,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            // Index badge
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.success.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  "$index",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Station info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.straighten_rounded,
                          size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        "${stop['DistancetoFind']} km",
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.navigation_rounded,
                          size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        "Tap to Navigate",
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 11, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ),
            // Charge needed badge
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(Icons.bolt_rounded,
                      size: 14, color: AppColors.success),
                  Text(
                    "${stop['NeedChargePercentage']}",
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripSummaryGrid({int crossAxisCount = 2}) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: crossAxisCount == 1 ? 3.6 : 2.4,
      children: [
        _summaryCard(Icons.straighten_rounded,
            "${_totalDistance.toStringAsFixed(1)} km", "Total Distance",
            Colors.blue.shade600),
        _summaryCard(Icons.access_time_rounded, "--", "Est. Time",
            Colors.purple.shade400),
        _summaryCard(Icons.electric_bolt_rounded, "--", "Est. Cost",
            Colors.orange.shade600),
        _summaryCard(Icons.eco_rounded, "0 lbs", "CO₂ Saved",
            Colors.green.shade600),
      ],
    );
  }

  Widget _summaryCard(
      IconData icon, String value, String label, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: iconColor.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}