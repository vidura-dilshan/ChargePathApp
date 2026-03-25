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
  final Completer<GoogleMapController> _controller = Completer();

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

  Future<BitmapDescriptor> _createNavigationArrowIcon() async {
    const int size = 120;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final Paint shadowPaint = Paint()
      ..color = const Color(0xFF0253A4).withOpacity(0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Paint bodyPaint = Paint()
      ..color = const Color(0xFF0253A4)
      ..style = PaintingStyle.fill;

    final Paint edgePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeJoin = StrokeJoin.round;

    final double cx = size / 2;
    final double cy = size / 2;

    final Path arrow = Path();
    arrow.moveTo(cx, cy - 42);
    arrow.lineTo(cx + 30, cy + 30);
    arrow.lineTo(cx, cy + 12);
    arrow.lineTo(cx - 30, cy + 30);
    arrow.close();

    canvas.save();
    canvas.translate(0, 4);
    canvas.drawPath(arrow, shadowPaint);
    canvas.restore();

    canvas.drawPath(arrow, bodyPaint);
    canvas.drawPath(arrow, edgePaint);
    canvas.drawCircle(
      Offset(cx, cy - 42),
      4,
      Paint()..color = Colors.white,
    );

    final ui.Image img =
        await recorder.endRecording().toImage(size, size);
    final ByteData? byteData =
        await img.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _createLocationDotIcon() async {
    const int size = 80;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final double cx = size / 2;
    final double cy = size / 2;

    canvas.drawCircle(
      Offset(cx, cy),
      28,
      Paint()
        ..color = const Color(0xFF0253A4).withOpacity(0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      18,
      Paint()
        ..color = const Color(0xFF0253A4).withOpacity(0.30)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      12,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
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

    final GoogleMapController ctrl = await _controller.future;
    ctrl.animateCamera(
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

          // Fit camera to show entire route
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
  Future<void> _fitMapToRoute(List<LatLng> points) async {
    if (points.isEmpty) return;
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

    final GoogleMapController ctrl = await _controller.future;
    ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80.0, // padding
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
      ),
      Marker(
        markerId: const MarkerId("destination"),
        position: _destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
        infoWindow: InfoWindow(title: _destinationName),
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
        consumeTapEvents: false,
      ),
      Marker(
        markerId: const MarkerId("destination"),
        position: _destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
        infoWindow: InfoWindow(title: _destinationName),
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

    final GoogleMapController ctrl = await _controller.future;
    ctrl.animateCamera(
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
        distanceFilter: 5,
      ),
    ).listen(_onLocationUpdate);
  }

  // ── 4. REAL-TIME LOCATION UPDATE ──────────────────────────────────────────
  Future<void> _onLocationUpdate(Position position) async {
    if (!mounted) return;

    final LatLng newPos = LatLng(position.latitude, position.longitude);
    final double bearing = position.heading;

    setState(() {
      _currentPosition = newPos;
      _currentBearing = bearing;
      _updateMarkersNavigation(newPos, bearing);
    });

    // Step advancement logic
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

    // Arrival detection
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

    if (!mounted) return;
    final GoogleMapController ctrl = await _controller.future;
    ctrl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: newPos,
          zoom: 18,
          tilt: 60,
          bearing: bearing,
        ),
      ),
    );
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
      final GoogleMapController ctrl = await _controller.future;
      ctrl.animateCamera(
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
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green.shade600,
                  size: 48,
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
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
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
                        Icon(Icons.flash_on, color: _primaryColor, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          'Estimated Total Cost',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Rs.24.50',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_totalDistance.isNotEmpty && _totalDistance != "--" ? _totalDistance : "?"} to $_destinationName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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
                          CircularProgressIndicator(color: _primaryColor),
                          const SizedBox(height: 16),
                          Text(
                            "Getting your location...",
                            style:
                                TextStyle(color: Colors.grey.shade600),
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
                      if (!_controller.isCompleted) {
                        _controller.complete(controller);
                      }
                    },
                  ),
          ),

          // ── BACK BUTTON (always visible, preview mode) ─────────────────────
          if (!_isNavigating)
            Positioned(
              top: 48,
              left: 16,
              child: SafeArea(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
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

          // ── PREVIEW: VIEW COST ─────────────────────────────────────────────
          if (!_isNavigating)
            Positioned(
              top: 60,
              right: 20,
              child: SafeArea(
                child: GestureDetector(
                  onTap: _showCostPopup,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.attach_money,
                            color: _primaryColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "View Cost",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
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
              top: screenHeight * 0.45 - 130,
              right: 16,
              child: Column(
                children: [
                  _buildMapButton(
                    Icons.my_location,
                    onTap: () async {
                      if (_currentPosition != null) {
                        final ctrl = await _controller.future;
                        ctrl.animateCamera(
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
                  const SizedBox(height: 12),
                  _buildMapButton(
                    Icons.add,
                    onTap: () async {
                      final ctrl = await _controller.future;
                      ctrl.animateCamera(CameraUpdate.zoomIn());
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildMapButton(
                    Icons.remove,
                    onTap: () async {
                      final ctrl = await _controller.future;
                      ctrl.animateCamera(CameraUpdate.zoomOut());
                    },
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
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
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
                        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          // Route label
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _primaryColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.alt_route,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$_startAddress → $_destinationName',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Optimal charging route',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Stats row
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatItem(
                                _totalDistance,
                                'Distance',
                                Colors.black87,
                              ),
                              _buildStatItem(
                                _totalDuration,
                                'Duration',
                                Colors.black87,
                              ),
                              _buildStatItem(
                                'Rs.24.50',
                                'Cost',
                                _primaryColor,
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),

                          // Timeline
                          _buildTimelineItem(
                            index: 1,
                            name: _startAddress,
                            details: 'Start Point • Current Location',
                            percentage: 'Start',
                            isLast: false,
                          ),
                          _buildTimelineItem(
                            index: 2,
                            name: _destinationName,
                            details:
                                'Charging Station • $_totalDistance total',
                            percentage: 'End',
                            isLast: true,
                          ),

                          const SizedBox(height: 20),

                          // Action buttons
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
                                    ),
                                    label: Text(
                                      _isLoading
                                          ? 'Loading route...'
                                          : 'Start Navigation',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isLoading
                                          ? Colors.grey
                                          : _primaryColor,
                                      elevation: 4,
                                      shadowColor:
                                          _primaryColor.withOpacity(0.4),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _buildIconButton(Icons.bookmark_border),
                              const SizedBox(width: 12),
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
              color: _primaryColor.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _maneuverIcon(step?.maneuver ?? 'straight'),
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step?.instruction ?? 'Follow the route',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (step != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'In ${step.distance}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: _endNavigation,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.close,
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
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _remainingDistance,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              Text(
                'remaining',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _steps.isNotEmpty
                    ? 'Step ${_currentStepIndex + 1}/${_steps.length}'
                    : '-- / --',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Text(
                'of route',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.ev_station, color: Colors.blue, size: 20),
              Text(
                _destinationName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.black87, size: 24),
      ),
    );
  }

  Widget _buildStatItem(String value, String label, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem({
    required int index,
    required String name,
    required String details,
    required String percentage,
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
                      index.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey.shade200,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
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
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            details,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      percentage,
                      style: TextStyle(
                        color: _primaryColor.withOpacity(0.6),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Icon(icon, color: Colors.grey.shade700),
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