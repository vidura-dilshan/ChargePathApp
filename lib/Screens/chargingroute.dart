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

class _ChargingRouteState extends State<ChargingRoute>
    with TickerProviderStateMixin {
  // ── THEME ─────────────────────────────────────────────────────────────────
  final Color _primaryColor = const Color(0xFF0253A4);
  final Color _backgroundColor = const Color(0xFFF5F7FA);

  // ── GOOGLE MAPS ───────────────────────────────────────────────────────────
  static const String _kGoogleApiKey =
      "AIzaSyALER_NJqGFdwseum4UGUk_wTTYZbGK-es";

  // ── CACHED CONTROLLER (key fix for smooth navigation) ─────────────────────
  GoogleMapController? _mapController;

  // ── LOCATION STATE ────────────────────────────────────────────────────────
  LatLng? _currentPosition;
  double _currentBearing = 0;
  String _startAddress = "Locating...";

  // ── DESTINATION FROM WIDGET ───────────────────────────────────────────────
  LatLng get _destination => widget.destination;
  String get _destinationName => widget.destinationName;

  // ── CUSTOM MARKER ICONS ───────────────────────────────────────────────────
  BitmapDescriptor? _navigationArrowIcon;
  BitmapDescriptor? _locationDotIcon;

  // ── ROUTE DATA ────────────────────────────────────────────────────────────
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  bool _isLoading = true;

  // ── NAVIGATION STATE ──────────────────────────────────────────────────────
  bool _isNavigating = false;
  StreamSubscription<Position>? _positionStream;
  List<_NavStep> _steps = [];
  int _currentStepIndex = 0;
  String _totalDistance = "--";
  String _totalDuration = "--";
  String _remainingDistance = "--";
  bool _isArrived = false;

  // ── ANIMATION ─────────────────────────────────────────────────────────────
  late AnimationController _hudAnimCtrl;
  late Animation<Offset> _hudSlide;
  late AnimationController _instrAnimCtrl;
  late Animation<double> _instrFade;

  @override
  void initState() {
    super.initState();

    _hudAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _hudSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _hudAnimCtrl, curve: Curves.easeOut),
    );

    _instrAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..value = 1.0;
    _instrFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _instrAnimCtrl, curve: Curves.easeIn),
    );

    _initCustomIcons();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController?.dispose();
    _hudAnimCtrl.dispose();
    _instrAnimCtrl.dispose();
    super.dispose();
  }

  // ── CUSTOM ICON GENERATION ────────────────────────────────────────────────

  Future<void> _initCustomIcons() async {
    _navigationArrowIcon = await _createNavigationArrowIcon();
    _locationDotIcon = await _createLocationDotIcon();
    _getUserLocationAndRoute();
  }

  /// Google Maps–style navigation chevron — sharp, blue with white border
  Future<BitmapDescriptor> _createNavigationArrowIcon() async {
    const int size = 160;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final double cx = size / 2;
    final double cy = size / 2;

    // ── outer glow / shadow ───────────────────────────────────────────────
    final Paint glowPaint = Paint()
      ..color = const Color(0xFF0253A4).withOpacity(0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final Path arrowShape = _buildArrowPath(cx, cy, 54, 22);

    canvas.save();
    canvas.translate(0, 6);
    canvas.drawPath(arrowShape, glowPaint);
    canvas.restore();

    // ── white border stroke ───────────────────────────────────────────────
    canvas.drawPath(
      arrowShape,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round,
    );

    // ── solid fill ────────────────────────────────────────────────────────
    canvas.drawPath(
      arrowShape,
      Paint()
        ..color = const Color(0xFF0253A4)
        ..style = PaintingStyle.fill,
    );

    // ── inner highlight line ──────────────────────────────────────────────
    canvas.drawPath(
      arrowShape,
      Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    final ui.Image img =
        await recorder.endRecording().toImage(size, size);
    final ByteData? byteData =
        await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  /// Builds a clean navigation-chevron path centred on (cx, cy).
  /// [tip] = half-height from centre to tip; [tail] = half-height to tail
  Path _buildArrowPath(
      double cx, double cy, double tip, double tail) {
    final Path p = Path();
    // Tip of arrow (pointing up — bearing rotation handled by Marker.rotation)
    p.moveTo(cx, cy - tip);
    // Right wing
    p.lineTo(cx + 32, cy + tail);
    // Notch
    p.lineTo(cx, cy + tail - 14);
    // Left wing
    p.lineTo(cx - 32, cy + tail);
    p.close();
    return p;
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
      _updateMarkersPreview();
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _currentPosition!, zoom: 14),
      ),
    );

    await _fetchRouteAndSteps();
  }

  // ── 2. FETCH ROUTE + STEPS ────────────────────────────────────────────────
  Future<void> _fetchRouteAndSteps() async {
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

          final List<_NavStep> steps = [];
          for (final step in leg['steps']) {
            steps.add(
              _NavStep(
                instruction: _stripHtml(step['html_instructions']),
                distance: step['distance']['text'],
                distanceMeters:
                    (step['distance']['value'] as num).toDouble(),
                maneuver: step['maneuver'] ?? 'straight',
                endLocation: LatLng(
                  step['end_location']['lat'],
                  step['end_location']['lng'],
                ),
              ),
            );
          }

          final String encodedPolyline =
              route['overview_polyline']['points'];
          final PolylinePoints polylinePoints = PolylinePoints();
          final List<PointLatLng> decoded =
              polylinePoints.decodePolyline(encodedPolyline);
          final List<LatLng> polylineCoords =
              decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();

          if (!mounted) return;
          setState(() {
            _steps = steps;
            _totalDistance = dist;
            _totalDuration = dur;
            _remainingDistance = dist;
            _polylines = {
              Polyline(
                polylineId: const PolylineId("route"),
                color: _primaryColor,
                points: polylineCoords,
                width: 6,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            };
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
          _polylines = {
            Polyline(
              polylineId: const PolylineId("route"),
              color: _primaryColor,
              points: coords,
              width: 6,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          };
          _fitMapToRoute(coords);
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Fallback polyline error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── MARKER HELPERS ────────────────────────────────────────────────────────

  void _updateMarkersPreview() {
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
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ),
        infoWindow: InfoWindow(title: _destinationName),
        zIndex: 1,
      ),
    };
  }

  void _updateMarkersNavigation(LatLng pos, double bearing) {
    _markers = {
      Marker(
        markerId: const MarkerId("user"),
        position: pos,
        icon: _navigationArrowIcon ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
        rotation: bearing,
        flat: true,
        zIndex: 3,
        consumeTapEvents: false,
      ),
      Marker(
        markerId: const MarkerId("destination"),
        position: _destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ),
        infoWindow: InfoWindow(title: _destinationName),
        zIndex: 1,
      ),
    };
  }

  // ── 3. START NAVIGATION ───────────────────────────────────────────────────
  Future<void> _startNavigation() async {
    if (_currentPosition == null) return;

    setState(() {
      _isNavigating = true;
      _currentStepIndex = 0;
      _isArrived = false;
      _updateMarkersNavigation(_currentPosition!, _currentBearing);
    });

    _hudAnimCtrl.forward();

    // Move instantly to navigation view — no animation delay
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition!,
          zoom: 18,
          tilt: 60,
          bearing: _currentBearing,
        ),
      ),
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2, // update every 2 m for smoother tracking
      ),
    ).listen(_onLocationUpdate);
  }

  // ── 4. REAL-TIME LOCATION UPDATE ──────────────────────────────────────────
  /// KEY FIX: use moveCamera (instant, no easing) so the marker and camera
  /// move together without any async gap or animation conflict.
  void _onLocationUpdate(Position position) async {
    if (!mounted) return;

    final LatLng newPos = LatLng(position.latitude, position.longitude);
    final double bearing = position.heading;

    // Update marker + state synchronously so the icon moves immediately
    setState(() {
      _currentPosition = newPos;
      _currentBearing = bearing;
      _updateMarkersNavigation(newPos, bearing);
    });

    // Move camera without animation so it tracks the marker in real time
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: newPos,
          zoom: 18,
          tilt: 60,
          bearing: bearing,
        ),
      ),
    );

    // ── Step advancement ──────────────────────────────────────────────────
    if (_steps.isNotEmpty && _currentStepIndex < _steps.length) {
      final _NavStep currentStep = _steps[_currentStepIndex];
      final double distToStepEnd = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        currentStep.endLocation.latitude,
        currentStep.endLocation.longitude,
      );

      if (distToStepEnd < 30 && _currentStepIndex < _steps.length - 1) {
        await _instrAnimCtrl.reverse();
        if (!mounted) return;
        setState(() {
          _currentStepIndex++;
          double rem = 0;
          for (int i = _currentStepIndex; i < _steps.length; i++) {
            rem += _steps[i].distanceMeters;
          }
          _remainingDistance = rem >= 1000
              ? '${(rem / 1000).toStringAsFixed(1)} km'
              : '${rem.toInt()} m';
        });
        await _instrAnimCtrl.forward();
      }
    }

    // ── Arrival detection ─────────────────────────────────────────────────
    final double distToDestination = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _destination.latitude,
      _destination.longitude,
    );

    if (distToDestination < 50 && !_isArrived) {
      if (!mounted) return;
      setState(() => _isArrived = true);
      _positionStream?.cancel();
      _showArrivalDialog();
    }
  }

  // ── 5. END NAVIGATION ─────────────────────────────────────────────────────
  Future<void> _endNavigation() async {
    _positionStream?.cancel();
    await _hudAnimCtrl.reverse();

    if (!mounted) return;
    setState(() {
      _isNavigating = false;
      _currentStepIndex = 0;
      _updateMarkersPreview();
    });

    if (_currentPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _currentPosition!,
            zoom: 14,
            tilt: 0,
          ),
        ),
      );
    }
  }

  // ── 6. ARRIVAL DIALOG ─────────────────────────────────────────────────────
  void _showArrivalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.green.shade100,
                      Colors.green.shade50,
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green.shade600,
                  size: 52,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "You've Arrived!",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "You have reached $_destinationName",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _endNavigation();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Done",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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

  // ── 7. COST POPUP ─────────────────────────────────────────────────────────
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

  // ── 8. BUILD ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double mapHeight =
        _isNavigating ? screenHeight : screenHeight * 0.45;

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          // ── MAP ────────────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: mapHeight,
            child: _currentPosition == null
                ? Container(
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
                            "Getting your location...",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : GoogleMap(
                    mapType: MapType.normal,
                    initialCameraPosition: CameraPosition(
                      target: _currentPosition!,
                      zoom: 14,
                    ),
                    zoomControlsEnabled: false,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    polylines: _polylines,
                    markers: _markers,
                    onMapCreated: (GoogleMapController controller) {
                      // Cache controller immediately — no Completer needed
                      _mapController = controller;
                    },
                  ),
          ),

          // ── BACK BUTTON (preview mode only) ────────────────────────────────
          if (!_isNavigating)
            Positioned(
              top: 48,
              left: 16,
              child: SafeArea(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
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
                ),
              ),
            ),

          // ── NAV HUD: TOP INSTRUCTION CARD ────────────────────────────────
          if (_isNavigating)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _hudSlide,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _buildInstructionCard(),
                  ),
                ),
              ),
            ),

          // ── NAV HUD: BOTTOM BAR ───────────────────────────────────────────
          if (_isNavigating)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildNavigationBottomBar(),
            ),

          // ── PREVIEW: VIEW COST BUTTON ──────────────────────────────────────
          if (!_isNavigating)
            Positioned(
              top: 60,
              right: 16,
              child: SafeArea(
                child: GestureDetector(
                  onTap: _showCostPopup,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
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
                          "View Cost",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── PREVIEW: MAP CONTROLS ──────────────────────────────────────────
          if (!_isNavigating)
            Positioned(
              top: screenHeight * 0.45 - 140,
              right: 16,
              child: Column(
                children: [
                  _buildMapButton(
                    Icons.my_location_rounded,
                    onTap: () {
                      if (_currentPosition != null) {
                        _mapController?.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(
                                target: _currentPosition!, zoom: 16),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildMapButton(
                    Icons.add_rounded,
                    onTap: () =>
                        _mapController?.animateCamera(CameraUpdate.zoomIn()),
                  ),
                  const SizedBox(height: 10),
                  _buildMapButton(
                    Icons.remove_rounded,
                    onTap: () =>
                        _mapController?.animateCamera(CameraUpdate.zoomOut()),
                  ),
                ],
              ),
            ),

          // ── PREVIEW: BOTTOM ROUTE SHEET ────────────────────────────────────
          if (!_isNavigating)
            Positioned(
              top: screenHeight * 0.45 - 30,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
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
                        margin:
                            const EdgeInsets.only(top: 12, bottom: 8),
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
                        padding:
                            const EdgeInsets.fromLTRB(24, 10, 24, 24),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          // ── Route header ─────────────────────────────────
                          Row(
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$_startAddress → $_destinationName',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
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
                          ),

                          const SizedBox(height: 24),

                          // ── Stats row ─────────────────────────────────────
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceAround,
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
                          ),

                          const SizedBox(height: 24),

                          // ── Timeline ──────────────────────────────────────
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
                            details:
                                'Charging Station • $_totalDistance total',
                            tag: 'End',
                            isLast: true,
                          ),

                          const SizedBox(height: 20),

                          // ── Action buttons ────────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 56,
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoading
                                        ? null
                                        : _startNavigation,
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
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _buildIconButton(Icons.bookmark_border_rounded),
                              const SizedBox(width: 10),
                              _buildIconButton(Icons.share_outlined),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── NAVIGATION WIDGETS ────────────────────────────────────────────────────

  Widget _buildInstructionCard() {
    final _NavStep? step =
        _steps.isNotEmpty && _currentStepIndex < _steps.length
            ? _steps[_currentStepIndex]
            : null;

    return FadeTransition(
      opacity: _instrFade,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _primaryColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _primaryColor.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            // Maneuver icon box
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _maneuverIcon(step?.maneuver ?? 'straight'),
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step?.instruction ?? 'Follow the route',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (step != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.straighten_rounded,
                            color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'In ${step.distance}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // End navigation button
            GestureDetector(
              onTap: _endNavigation,
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Remaining distance
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _remainingDistance,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'remaining',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Step counter badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _steps.isNotEmpty
                      ? '${_currentStepIndex + 1} / ${_steps.length}'
                      : '-- / --',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  'steps',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Destination
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.ev_station_rounded,
                        color: _primaryColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Destination',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _destinationName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  IconData _maneuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn-left':
        return Icons.turn_left_rounded;
      case 'turn-right':
        return Icons.turn_right_rounded;
      case 'turn-slight-left':
      case 'fork-left':
        return Icons.turn_slight_left_rounded;
      case 'turn-slight-right':
      case 'fork-right':
        return Icons.turn_slight_right_rounded;
      case 'turn-sharp-left':
        return Icons.turn_sharp_left_rounded;
      case 'turn-sharp-right':
        return Icons.turn_sharp_right_rounded;
      case 'uturn-left':
      case 'uturn-right':
        return Icons.u_turn_left_rounded;
      case 'roundabout-left':
      case 'roundabout-right':
        return Icons.roundabout_left_rounded;
      case 'merge':
        return Icons.merge_rounded;
      case 'ramp-left':
        return Icons.turn_left_rounded;
      case 'ramp-right':
        return Icons.turn_right_rounded;
      case 'ferry':
        return Icons.directions_ferry_rounded;
      case 'straight':
      default:
        return Icons.straight_rounded;
    }
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

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

  Widget _buildIconButton(IconData icon) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Icon(icon, color: Colors.grey.shade600, size: 22),
    );
  }
}

// ── DATA MODEL ────────────────────────────────────────────────────────────────
class _NavStep {
  final String instruction;
  final String distance;
  final double distanceMeters;
  final String maneuver;
  final LatLng endLocation;

  const _NavStep({
    required this.instruction,
    required this.distance,
    required this.distanceMeters,
    required this.maneuver,
    required this.endLocation,
  });
}