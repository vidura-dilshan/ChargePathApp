import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // ADD THIS

class ChargingRoute extends StatefulWidget {
  final LatLng destination;
  final String destinationName;

  const ChargingRoute({
    super.key,
    required this.destination,
    required this.destinationName,
  });

  @override
  State<ChargingRoute> createState() => _ChargingRouteState();
}

class _ChargingRouteState extends State<ChargingRoute> {
  // ── THEME ─────────────────────────────────────────────────────────────────
  final Color _primaryColor = const Color(0xFF0253A4);
  final Color _backgroundColor = const Color(0xFFF5F7FA);

  // ── GOOGLE MAPS ───────────────────────────────────────────────────────────
  static const String _kGoogleApiKey =
      "AIzaSyALER_NJqGFdwseum4UGUk_wTTYZbGK-es";

  // ── MAP CONTROLLER ────────────────────────────────────────────────────────
  GoogleMapController? _mapController;

  // ── LOCATION STATE ────────────────────────────────────────────────────────
  LatLng? _currentPosition;
  String _startAddress = "Locating...";

  // ── DESTINATION FROM WIDGET ───────────────────────────────────────────────
  LatLng get _destination => widget.destination;
  String get _destinationName => widget.destinationName;

  // ── CUSTOM MARKER ICONS ───────────────────────────────────────────────────
  BitmapDescriptor? _locationDotIcon;
  BitmapDescriptor? _destinationIcon;

  // ── ROUTE DATA ────────────────────────────────────────────────────────────
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  List<LatLng> _routeCoords = [];
  bool _isLoading = true;
  String _totalDistance = "--";
  String _totalDuration = "--";

  @override
  void initState() {
    super.initState();
    _initCustomIcons();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // ── CUSTOM ICON GENERATION ────────────────────────────────────────────────

  Future<void> _initCustomIcons() async {
    _locationDotIcon = await _createLocationDotIcon();
    _destinationIcon = await _createDestinationIcon();
    _getUserLocationAndRoute();
  }

  Future<BitmapDescriptor> _createLocationDotIcon() async {
    const int size = 80;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final double cx = size / 2;
    final double cy = size / 2;

    // Pulse rings
    canvas.drawCircle(
      Offset(cx, cy),
      30,
      Paint()
        ..color = const Color(0xFF0253A4).withOpacity(0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      20,
      Paint()
        ..color = const Color(0xFF0253A4).withOpacity(0.22)
        ..style = PaintingStyle.fill,
    );
    // White ring
    canvas.drawCircle(
      Offset(cx, cy),
      13,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    // Core dot
    canvas.drawCircle(
      Offset(cx, cy),
      9,
      Paint()
        ..color = const Color(0xFF0253A4)
        ..style = PaintingStyle.fill,
    );

    final ui.Image img =
    await recorder.endRecording().toImage(size, size);
    final ByteData? byteData =
    await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  /// Professional teardrop pin with a charging-bolt glyph for the destination.
  Future<BitmapDescriptor> _createDestinationIcon() async {
    const int size = 130;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final double cx = size / 2;
    const double cyTop = 50;
    const double r = 40;

    // ── drop shadow ───────────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cyTop + 5),
      r,
      Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final Paint pinPaint = Paint()
      ..color = _primaryColor
      ..style = PaintingStyle.fill;

    // ── pointed tail ──────────────────────────────────────────────────────
    final Path tail = Path()
      ..moveTo(cx - 17, cyTop + 20)
      ..lineTo(cx + 17, cyTop + 20)
      ..lineTo(cx, size - 6.0)
      ..close();
    canvas.drawPath(tail, pinPaint);

    // ── pin head ──────────────────────────────────────────────────────────
    canvas.drawCircle(Offset(cx, cyTop), r, pinPaint);

    // ── white inner disc ──────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cyTop),
      25,
      Paint()..color = Colors.white,
    );

    // ── bolt glyph (rendered from the Material icon font) ─────────────────
    final TextPainter tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: String.fromCharCode(Icons.bolt_rounded.codePoint),
      style: TextStyle(
        fontSize: 36,
        fontFamily: Icons.bolt_rounded.fontFamily,
        package: Icons.bolt_rounded.fontPackage,
        color: _primaryColor,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cyTop - tp.height / 2));

    final ui.Image img =
    await recorder.endRecording().toImage(size, size);
    final ByteData? byteData =
    await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  // ── 1. INITIAL LOCATION + PERMISSIONS ────────────────────────────────────
  Future<void> _getUserLocationAndRoute() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    String fetchedName = "My Location";
    try {
      final List<Placemark> placemarks =
      await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        fetchedName = placemarks.first.locality ??
            placemarks.first.subAdministrativeArea ??
            "Current Location";
      }
    } catch (e) {
      debugPrint("Geocoding error: $e");
    }

    if (!mounted) return;

    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _startAddress = fetchedName;
      _updateMarkers();
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _currentPosition!, zoom: 14),
      ),
    );

    await _fetchRoute();
  }

  // ── 2. FETCH ROUTE (for preview line + distance/duration) ───────────────
  Future<void> _fetchRoute() async {
    if (_currentPosition == null) return;

    try {
      final Uri url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
            '?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
            '&destination=${_destination.latitude},${_destination.longitude}'
            '&mode=driving'
            '&key=$_kGoogleApiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK') {
          final route = data['routes'][0];
          final leg = route['legs'][0];

          final String dist = leg['distance']['text'];
          final String dur = leg['duration']['text'];

          final String encodedPolyline =
          route['overview_polyline']['points'];
          final PolylinePoints polylinePoints = PolylinePoints();
          final List<PointLatLng> decoded =
          polylinePoints.decodePolyline(encodedPolyline);
          final List<LatLng> polylineCoords =
          decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();

          if (!mounted) return;
          setState(() {
            _totalDistance = dist;
            _totalDuration = dur;
            _routeCoords = polylineCoords;
            _polylines = _buildPolylines();
            _isLoading = false;
          });

          _fitMapToRoute(polylineCoords);
        } else {
          debugPrint("Directions API status: ${data['status']}");
          await _fallbackPolyline();
        }
      } else {
        await _fallbackPolyline();
      }
    } catch (e) {
      debugPrint("Directions API error: $e");
      await _fallbackPolyline();
    }
  }

  // ── FIT MAP TO SHOW ENTIRE ROUTE ──────────────────────────────────────────
  void _fitMapToRoute(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80.0,
      ),
    );
  }

  Future<void> _fallbackPolyline() async {
    if (_currentPosition == null) return;
    try {
      final PolylinePoints polylinePoints = PolylinePoints();
      final PolylineResult result =
      await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: _kGoogleApiKey,
        request: PolylineRequest(
          origin: PointLatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          destination: PointLatLng(
            _destination.latitude,
            _destination.longitude,
          ),
          mode: TravelMode.driving,
        ),
      );

      if (!mounted) return;
      setState(() {
        if (result.points.isNotEmpty) {
          final coords = result.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();
          _routeCoords = coords;
          _polylines = _buildPolylines();
          _fitMapToRoute(coords);
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Fallback polyline error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── POLYLINE BUILDER ──────────────────────────────────────────────────────

  /// Full route drawn with a soft casing for a clean, layered look.
  Set<Polyline> _buildPolylines() {
    if (_routeCoords.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId("route_casing"),
        color: _primaryColor.withOpacity(0.22),
        points: _routeCoords,
        width: 12,
        zIndex: 0,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
      Polyline(
        polylineId: const PolylineId("route"),
        color: _primaryColor,
        points: _routeCoords,
        width: 6,
        zIndex: 1,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  // ── MARKER HELPER ─────────────────────────────────────────────────────────

  void _updateMarkers() {
    if (_currentPosition == null) return;
    _markers = {
      Marker(
        markerId: const MarkerId("user"),
        position: _currentPosition!,
        icon: _locationDotIcon ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(title: _startAddress),
        zIndex: 2,
      ),
      Marker(
        markerId: const MarkerId("destination"),
        position: _destination,
        icon: _destinationIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(title: _destinationName),
        zIndex: 1,
      ),
    };
  }

  // ── 3. LAUNCH GOOGLE MAPS FOR NAVIGATION ─────────────────────────────────
  // ADD THIS — replaces all custom in-app navigation logic.
  Future<void> _launchGoogleMapsNavigation() async {
    if (_currentPosition == null) return;

    final Uri googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
          '&origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
          '&destination=${_destination.latitude},${_destination.longitude}'
          '&travelmode=driving',
    );

    try {
      final bool launched = await launchUrl(
        googleMapsUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    } catch (e) {
      debugPrint("Could not launch Google Maps: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    }
  }

  // ── 4. COST POPUP ─────────────────────────────────────────────────────────
  void _showCostPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.flash_on,
                              color: _primaryColor, size: 18),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Estimated Cost',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 18, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Rs. 24.50',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.electric_bolt,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${_totalDistance != "--" ? _totalDistance : "?"} to $_destinationName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  // ── 5. BUILD ──────────────────────────────────────────────────────────────
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
    final double screenHeight = MediaQuery.of(context).size.height;
    final double mapHeight = screenHeight * 0.45;

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: mapHeight,
            child: _buildMap(),
          ),
          Positioned(
            top: 48,
            left: 16,
            child: SafeArea(
              child: _buildBackButton(),
            ),
          ),
          Positioned(
            top: 60,
            right: 16,
            child: SafeArea(
              child: _buildViewCostButton(),
            ),
          ),
          Positioned(
            top: mapHeight - 140,
            right: 16,
            child: _buildMapControls(),
          ),
          Positioned(
            top: mapHeight - 30,
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildMobileRouteSheet(),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 7,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildMap(),
                  ),
                  Positioned(
                    top: 18,
                    left: 18,
                    child: _buildBackButton(),
                  ),
                  Positioned(
                    top: 18,
                    right: 18,
                    child: _buildViewCostButton(),
                  ),
                  Positioned(
                    right: 18,
                    bottom: 18,
                    child: _buildMapControls(),
                  ),
                ],
              ),
            ),
            Container(
              width: 390,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(
                    color: Colors.grey.shade200,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 18,
                    offset: const Offset(-4, 0),
                  ),
                ],
              ),
              child: _buildWideRoutePanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_currentPosition == null) {
      return Container(
        color: _backgroundColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: _primaryColor,
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              Text(
                'Getting your location...',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GoogleMap(
      mapType: MapType.normal,
      initialCameraPosition: CameraPosition(
        target: _currentPosition!,
        zoom: 14,
      ),
      zoomControlsEnabled: false,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      polylines: _polylines,
      markers: _markers,
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
      },
    );
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildViewCostButton() {
    return GestureDetector(
      onTap: _showCostPopup,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.monetization_on_rounded,
                color: _primaryColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'View Cost',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Column(
      children: [
        _buildMapButton(
          Icons.my_location_rounded,
          onTap: () {
            if (_currentPosition != null) {
              _mapController?.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: _currentPosition!,
                    zoom: 16,
                  ),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 10),
        _buildMapButton(
          Icons.add_rounded,
          onTap: () {
            _mapController?.animateCamera(
              CameraUpdate.zoomIn(),
            );
          },
        ),
        const SizedBox(height: 10),
        _buildMapButton(
          Icons.remove_rounded,
          onTap: () {
            _mapController?.animateCamera(
              CameraUpdate.zoomOut(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMobileRouteSheet() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(
                top: 12,
                bottom: 8,
              ),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                24,
                10,
                24,
                24,
              ),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildRouteHeader(),
                const SizedBox(height: 24),
                _buildStatsPanel(),
                const SizedBox(height: 24),
                _buildTimeline(),
                const SizedBox(height: 20),
                _buildRouteActions(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideRoutePanel() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            24,
            26,
            24,
            22,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0253A4),
                Color(0xFF034485),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.navigation_rounded,
                color: Colors.white,
                size: 28,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Charging Route',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              _buildRouteHeader(),
              const SizedBox(height: 22),
              _buildStatsPanel(),
              const SizedBox(height: 24),
              _buildTimeline(),
              const SizedBox(height: 22),
              _buildRouteStatusCard(),
              const SizedBox(height: 24),
              _buildRouteActions(
                useCompactIcons: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _primaryColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.alt_route_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_startAddress → $_destinationName',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                'Optimal charging route',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            _totalDistance,
            'Distance',
            Icons.straighten_rounded,
            Colors.black87,
          ),
          _buildDivider(),
          _buildStatItem(
            _totalDuration,
            'Duration',
            Icons.access_time_rounded,
            Colors.black87,
          ),
          _buildDivider(),
          _buildStatItem(
            'Rs.24.50',
            'Cost',
            Icons.electric_bolt_rounded,
            _primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return Column(
      children: [
        _buildTimelineItem(
          index: 1,
          name: _startAddress,
          details: 'Start Point • Current Location',
          tag: 'Start',
          isLast: false,
        ),
        _buildTimelineItem(
          index: 2,
          name: _destinationName,
          details: 'Charging Station • $_totalDistance total',
          tag: 'End',
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildRouteStatusCard() {
    final bool routeReady =
        !_isLoading && _routeCoords.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: routeReady
            ? const Color(0xFFEAF8EF)
            : const Color(0xFFFFF5E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: routeReady
              ? const Color(0xFF00A843).withOpacity(0.20)
              : Colors.orange.withOpacity(0.20),
        ),
      ),
      child: Row(
        children: [
          Icon(
            routeReady
                ? Icons.check_circle_rounded
                : Icons.hourglass_top_rounded,
            color: routeReady
                ? const Color(0xFF00A843)
                : Colors.orange.shade700,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              routeReady
                  ? 'Route is ready. Open Google Maps to begin navigation.'
                  : 'Preparing your route and location details.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteActions({
    bool useCompactIcons = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : _launchGoogleMapsNavigation,
              icon: const Icon(
                Icons.navigation_rounded,
                color: Colors.white,
                size: 20,
              ),
              label: Text(
                _isLoading
                    ? 'Loading...'
                    : 'Start Navigation',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLoading
                    ? Colors.grey.shade400
                    : _primaryColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _buildIconButton(
          Icons.bookmark_border_rounded,
          size: useCompactIcons ? 52 : 56,
        ),
        const SizedBox(width: 10),
        _buildIconButton(
          Icons.share_outlined,
          size: useCompactIcons ? 52 : 56,
        ),
      ],
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Widget _buildMapButton(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.black87, size: 22),
      ),
    );
  }

  Widget _buildStatItem(
      String value,
      String label,
      IconData icon,
      Color valueColor,
      ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: valueColor.withOpacity(0.7)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 32,
      width: 1,
      color: Colors.grey.shade200,
    );
  }

  Widget _buildTimelineItem({
    required int index,
    required String name,
    required String details,
    required String tag,
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: _primaryColor.withOpacity(0.15),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            details,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: _primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(
      IconData icon, {
        double size = 56,
      }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Icon(icon, color: Colors.grey.shade600, size: 22),
    );
  }
}