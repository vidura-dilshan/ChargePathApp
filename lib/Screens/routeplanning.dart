import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'chargingroute.dart';

class RoutePlanningPage extends StatefulWidget {
  const RoutePlanningPage({super.key});

  @override
  State<RoutePlanningPage> createState() => _RoutePlanningPageState();
}

class _RoutePlanningPageState extends State<RoutePlanningPage> {
  // --- CONFIGURATION ---
  final String _googleApiKey = "AIzaSyALER_NJqGFdwseum4UGUk_wTTYZbGK-es";

  final Color _primaryColor = const Color(0xFF0253A4);
  final Color _lightFillColor = const Color(0xFFE6EFF8);
  final Color _accentGreen = const Color(0xFF00C853);

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

  // ── CHANGE 1: Removed default text — fields show only the hint ────────────
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  // ─────────────────────────────────────────────────────────────────────────

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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          "Route Planning",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLocationHeader(),
              const SizedBox(height: 24),
              _buildSectionTitle("Vehicle Settings", Icons.electric_car),
              const SizedBox(height: 16),
              _buildBatterySlider(),
              const SizedBox(height: 16),
              const Text("Max Range (km)",
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              _buildBlueTextBox("e.g. 100", _rangeController,
                  isNumber: true),
              const SizedBox(height: 16),
              _buildConnectorSelector(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _fetchRoute,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white))
                      : const Text("Plan Route",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle("Route Preview", Icons.map),
              const SizedBox(height: 16),
              _buildMapPreview(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle("Charging Stops", Icons.ev_station),
                  Text("${_routeStops.length} stops",
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 16),
              _routeStops.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text("Route not calculated yet",
                            style: TextStyle(color: Colors.grey[400])),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _routeStops.length,
                      itemBuilder: (ctx, index) =>
                          _buildStopItem(index + 1, _routeStops[index]),
                    ),
              const SizedBox(height: 24),
              _buildSectionTitle("Trip Summary", Icons.summarize),
              const SizedBox(height: 16),
              _buildTripSummaryGrid(),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS (unchanged) ---

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: _primaryColor, size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildLocationHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 15),
          child: Column(
            children: [
              const Icon(Icons.circle, color: Colors.green, size: 12),
              Container(width: 2, height: 45, color: Colors.grey[300]),
              const Icon(Icons.circle, color: Colors.red, size: 12),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              _buildBlueTextBox("Origin", _startController),
              const SizedBox(height: 12),
              _buildBlueTextBox("Destination", _endController),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBlueTextBox(String hint, TextEditingController controller,
      {bool isNumber = false}) {
    return Container(
      decoration: BoxDecoration(
          color: _lightFillColor,
          borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: controller,
        keyboardType:
            isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  Widget _buildConnectorSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Connector Type",
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
              color: _lightFillColor,
              borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedConnector,
              isExpanded: true,
              icon:
                  Icon(Icons.keyboard_arrow_down, color: _primaryColor),
              items: _connectorOptions.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Row(
                    children: [
                      Icon(Icons.electrical_services,
                          color: _primaryColor, size: 20),
                      const SizedBox(width: 10),
                      Text(value,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (newValue) =>
                  setState(() => _selectedConnector = newValue!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBatterySlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Current Battery Level"),
            Text("${_currentBattery.toInt()}%",
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: _primaryColor,
            inactiveTrackColor: _lightFillColor,
            thumbColor: _primaryColor,
            overlayColor: _primaryColor.withOpacity(0.2),
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

  Widget _buildMapPreview() {
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GoogleMap(
          mapType: MapType.normal,
          initialCameraPosition: _kInitialLocation,
          zoomControlsEnabled: false,
          markers: _markers,
          onMapCreated: (GoogleMapController controller) {
            if (!_controller.isCompleted)
              _controller.complete(controller);
          },
        ),
      ),
    );
  }

  // ── CHANGE 2: onTap navigates to ChargingRoute instead of Google Maps ─────
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
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: _accentGreen, shape: BoxShape.circle),
              child: Center(
                  child: Text("$index",
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  Text(
                      "Distance: ${stop['DistancetoFind']} km",
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 12)),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Text("Tap to Navigate",
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward,
                          size: 10, color: Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              "Need: ${stop['NeedChargePercentage']}",
              style: TextStyle(
                  color: _accentGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTripSummaryGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: [
        _summaryCard(Icons.directions,
            "${_totalDistance.toStringAsFixed(1)} km", "Total Distance"),
        _summaryCard(Icons.access_time, "--", "Est. Time"),
        _summaryCard(Icons.attach_money, "--", "Est. Cost"),
        _summaryCard(Icons.eco, "0 lbs", "CO2 Saved"),
      ],
    );
  }

  Widget _summaryCard(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFFF5F9FD),
          borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: _primaryColor, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              Text(label,
                  style: TextStyle(
                      color: Colors.grey[600], fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}