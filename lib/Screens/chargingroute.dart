import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:chargepath/Theme/app_colors.dart';
import 'package:chargepath/Theme/app_spacing.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChargingRoute extends StatefulWidget {
  final String? stationId;
  final LatLng destination;
  final String destinationName;

  const ChargingRoute({
    super.key,
    this.stationId,
    required this.destination,
    required this.destinationName,
  });

  @override
  State<ChargingRoute> createState() => _ChargingRouteState();
}

class _ChargingRouteState extends State<ChargingRoute>
    with WidgetsBindingObserver {
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

  // ── ARRIVAL DETECTION ──────────────────────────────────────────────────────

  static const double _arrivalRadiusMeters = 100.0;

// True after Google Maps has been opened.
  bool _navigationOpened = false;

// Stops multiple location checks from running at the same time.
  bool _isCheckingArrival = false;

// Prevents the arrival flow from running repeatedly
// after arrival has already been verified.
  bool _arrivalVerified = false;

  @override
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _initCustomIcons();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _mapController?.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state,
      ) {
    super.didChangeAppLifecycleState(state);

    // We only care when:
    //
    // 1. Google Maps was opened
    // 2. ChargePath becomes active again
    // 3. Arrival has not already been verified
    if (state == AppLifecycleState.resumed &&
        _navigationOpened &&
        !_arrivalVerified) {
      Future.microtask(
        _checkArrivalAfterReturning,
      );
    }
  }

  Future<void> _checkArrivalAfterReturning() async {
    if (_isCheckingArrival ||
        _arrivalVerified) {
      return;
    }

    final String? stationId =
        widget.stationId;

    // Route Planner stops may not currently have
    // a Firestore station document ID.
    if (stationId == null ||
        stationId.trim().isEmpty) {
      debugPrint(
        'ARRIVAL_DEBUG: No stationId was supplied. '
            'Arrival check skipped.',
      );

      return;
    }

    final User? currentUser =
        FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      debugPrint(
        'ARRIVAL_DEBUG: No logged-in user.',
      );

      return;
    }

    _isCheckingArrival = true;

    try {
      // -----------------------------------------------------------------------
      // 1. GET THE STATION
      // -----------------------------------------------------------------------

      final DocumentSnapshot<
          Map<String, dynamic>>
      stationSnapshot =
      await FirebaseFirestore.instance
          .collection('stations')
          .doc(stationId)
          .get();

      if (!stationSnapshot.exists) {
        debugPrint(
          'ARRIVAL_DEBUG: Station does not exist.',
        );

        return;
      }

      final Map<String, dynamic>
      stationData =
      stationSnapshot.data()!;

      // -----------------------------------------------------------------------
      // 2. MAKE SURE THIS DRIVER BOOKED THIS STATION
      // -----------------------------------------------------------------------

      final String bookingUserId =
          stationData['booking_user_id']
              ?.toString()
              .trim() ??
              '';

      if (bookingUserId !=
          currentUser.uid) {
        debugPrint(
          'ARRIVAL_DEBUG: Current user does not '
              'have the booking for this station.',
        );

        return;
      }

      // -----------------------------------------------------------------------
      // 3. READ STATION LOCATION
      // -----------------------------------------------------------------------

      final double? stationLatitude =
      double.tryParse(
        stationData['latitude']
            ?.toString()
            .trim() ??
            '',
      );

      final double? stationLongitude =
      double.tryParse(
        stationData['longitude']
            ?.toString()
            .trim() ??
            '',
      );

      if (stationLatitude == null ||
          stationLongitude == null) {
        debugPrint(
          'ARRIVAL_DEBUG: Station coordinates are invalid.',
        );

        return;
      }

      // -----------------------------------------------------------------------
      // 4. CHECK LOCATION SERVICE
      // -----------------------------------------------------------------------

      final bool serviceEnabled =
      await Geolocator
          .isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint(
          'ARRIVAL_DEBUG: Location service is disabled.',
        );

        return;
      }

      // -----------------------------------------------------------------------
      // 5. CHECK LOCATION PERMISSION
      // -----------------------------------------------------------------------

      LocationPermission permission =
      await Geolocator
          .checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
        await Geolocator
            .requestPermission();
      }

      if (permission ==
          LocationPermission.denied ||
          permission ==
              LocationPermission
                  .deniedForever) {
        debugPrint(
          'ARRIVAL_DEBUG: Location permission denied.',
        );

        return;
      }

      // -----------------------------------------------------------------------
      // 6. GET DRIVER LOCATION
      // -----------------------------------------------------------------------

      final Position driverPosition =
      await Geolocator
          .getCurrentPosition(
        desiredAccuracy:
        LocationAccuracy.high,
      );

      // -----------------------------------------------------------------------
      // 7. CALCULATE DISTANCE
      // -----------------------------------------------------------------------

      final double distanceInMeters =
      Geolocator.distanceBetween(
        driverPosition.latitude,
        driverPosition.longitude,
        stationLatitude,
        stationLongitude,
      );

      debugPrint(
        'ARRIVAL_DEBUG: Distance to station = '
            '${distanceInMeters.toStringAsFixed(2)} metres',
      );

      // -----------------------------------------------------------------------
      // 8. WITHIN 100 METRES?
      // -----------------------------------------------------------------------

      if (distanceInMeters <=
          _arrivalRadiusMeters) {
        _arrivalVerified = true;

        // We no longer need to keep checking after
        // the arrival has been verified.
        _navigationOpened = false;

        debugPrint(
          'ARRIVAL_DEBUG: Arrival verified.',
        );

        if (!mounted) {
          return;
        }

        await _showFinishChargingPopup();
      } else {
        debugPrint(
          'ARRIVAL_DEBUG: Driver is outside '
              'the 100 m arrival radius.',
        );

        // IMPORTANT:
        // Do not set _navigationOpened = false here.
        //
        // This means if the user later returns to
        // ChargePath again while at the station,
        // we can check their location again.
      }
    } on FirebaseException catch (e) {
      debugPrint(
        'ARRIVAL_DEBUG: Firestore error: '
            '${e.code} - ${e.message}',
      );
    } catch (e) {
      debugPrint(
        'ARRIVAL_DEBUG: Arrival check failed: $e',
      );
    } finally {
      _isCheckingArrival = false;
    }
  }

  Future<void> _showAmountPaidPopup() async {
    if (!mounted) {
      return;
    }

    final TextEditingController amountController =
    TextEditingController();

    String? errorMessage;
    bool isSaving = false;

    final double? confirmedAmount =
    await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (
              BuildContext context,
              void Function(void Function())
              setDialogState,
              ) {
            return PopScope(
              // Driver cannot escape the payment
              // popup using Android back.
              canPop: false,

              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(20),
                ),

                title: const Row(
                  children: [
                    Icon(
                      Icons.payments_rounded,
                      color: AppColors.primary,
                    ),

                    SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'Amount Paid',
                      ),
                    ),
                  ],
                ),

                content: Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter the amount you paid at '
                          '${widget.destinationName}.',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(
                      height: 18,
                    ),

                    TextField(
                      controller:
                      amountController,

                      autofocus: true,

                      enabled:
                      !isSaving,

                      keyboardType:
                      const TextInputType
                          .numberWithOptions(
                        decimal: true,
                      ),

                      decoration:
                      InputDecoration(
                        labelText:
                        'Amount Paid',

                        prefixText:
                        'Rs. ',

                        hintText:
                        '0.00',

                        errorText:
                        errorMessage,

                        border:
                        OutlineInputBorder(
                          borderRadius:
                          BorderRadius
                              .circular(
                            12,
                          ),
                        ),

                        focusedBorder:
                        OutlineInputBorder(
                          borderRadius:
                          BorderRadius
                              .circular(
                            12,
                          ),
                          borderSide:
                          const BorderSide(
                            color:
                            AppColors
                                .primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Text(
                      'You must enter the amount paid '
                          'before continuing.',
                      style: TextStyle(
                        color:
                        AppColors
                            .textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                actions: [
                  SizedBox(
                    width:
                    double.infinity,
                    child:
                    ElevatedButton(
                      onPressed:
                      isSaving
                          ? null
                          : () async {
                        final String
                        enteredText =
                        amountController
                            .text
                            .trim();

                        final double?
                        amount =
                        double.tryParse(
                          enteredText,
                        );

                        // -----------------------------------------
                        // VALIDATION
                        // -----------------------------------------

                        if (enteredText
                            .isEmpty) {
                          setDialogState(
                                () {
                              errorMessage =
                              'Please enter the amount paid.';
                            },
                          );

                          return;
                        }

                        if (amount ==
                            null) {
                          setDialogState(
                                () {
                              errorMessage =
                              'Please enter a valid amount.';
                            },
                          );

                          return;
                        }

                        if (amount <=
                            0) {
                          setDialogState(
                                () {
                              errorMessage =
                              'Amount must be greater than Rs. 0.';
                            },
                          );

                          return;
                        }

                        // -----------------------------------------
                        // START SAVING
                        // -----------------------------------------

                        setDialogState(
                              () {
                            isSaving =
                            true;

                            errorMessage =
                            null;
                          },
                        );

                        try {
                          await _savePaymentToFirestore(
                            amount,
                          );

                          if (!dialogContext
                              .mounted) {
                            return;
                          }

                          // Firestore succeeded.
                          //
                          // Only NOW can the payment popup close.
                          Navigator.of(
                            dialogContext,
                          ).pop(
                            amount,
                          );
                        } catch (e) {
                          debugPrint(
                            'PAYMENT_DEBUG: '
                                'Payment save failed: $e',
                          );

                          if (!dialogContext
                              .mounted) {
                            return;
                          }

                          setDialogState(
                                () {
                              isSaving =
                              false;

                              String
                              message =
                              e.toString();

                              message =
                                  message
                                      .replaceFirst(
                                    'Exception: ',
                                    '',
                                  );

                              errorMessage =
                                  message;
                            },
                          );
                        }
                      },

                      style:
                      ElevatedButton
                          .styleFrom(
                        backgroundColor:
                        AppColors.primary,

                        foregroundColor:
                        Colors.white,

                        padding:
                        const EdgeInsets
                            .symmetric(
                          vertical: 14,
                        ),

                        shape:
                        RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius
                              .circular(
                            12,
                          ),
                        ),
                      ),

                      child:
                      isSaving
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                        CircularProgressIndicator(
                          strokeWidth:
                          2,
                          color:
                          Colors.white,
                        ),
                      )
                          : const Text(
                        'Confirm Amount',
                        style:
                        TextStyle(
                          fontWeight:
                          FontWeight
                              .bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Dispose after Flutter has removed the dialog.
    WidgetsBinding.instance
        .addPostFrameCallback(
          (_) {
        amountController.dispose();
      },
    );

    if (!mounted ||
        confirmedAmount == null) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          'Payment recorded successfully. '
              'Rs.${confirmedAmount.toStringAsFixed(2)}',
        ),
        backgroundColor:
        Colors.green.shade700,
      ),
    );
  }

  Future<void> _savePaymentToFirestore(
      double amount,
      ) async {
    final User? currentUser =
        FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      throw Exception(
        'You must be signed in to complete the payment.',
      );
    }

    final String? stationId =
        widget.stationId;

    if (stationId == null ||
        stationId.trim().isEmpty) {
      throw Exception(
        'Station information is missing.',
      );
    }

    final DocumentReference<Map<String, dynamic>>
    stationReference =
    FirebaseFirestore.instance
        .collection('stations')
        .doc(stationId);

    await FirebaseFirestore.instance.runTransaction(
          (Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>>
        stationSnapshot =
        await transaction.get(
          stationReference,
        );

        if (!stationSnapshot.exists) {
          throw Exception(
            'The charging station no longer exists.',
          );
        }

        final Map<String, dynamic> data =
        stationSnapshot.data()!;

        // ---------------------------------------------------------------------
        // VERIFY THIS DRIVER OWNS THE CURRENT BOOKING
        // ---------------------------------------------------------------------

        final String bookingUserId =
            data['booking_user_id']
                ?.toString()
                .trim() ??
                '';

        if (bookingUserId !=
            currentUser.uid) {
          throw Exception(
            'This booking does not belong to the current user.',
          );
        }

        // ---------------------------------------------------------------------
        // READ CURRENT TOTAL INCOME
        // ---------------------------------------------------------------------

        final double currentTotalIncome =
            double.tryParse(
              data['total_income']
                  ?.toString()
                  .trim() ??
                  '0',
            ) ??
                0.0;

        // ---------------------------------------------------------------------
        // ADD THIS PAYMENT
        // ---------------------------------------------------------------------

        final double newTotalIncome =
            currentTotalIncome + amount;

        debugPrint(
          'PAYMENT_DEBUG: Current total income = '
              '$currentTotalIncome',
        );

        debugPrint(
          'PAYMENT_DEBUG: Payment amount = $amount',
        );

        debugPrint(
          'PAYMENT_DEBUG: New total income = '
              '$newTotalIncome',
        );

        // ---------------------------------------------------------------------
        // UPDATE STATION
        // ---------------------------------------------------------------------

        transaction.update(
          stationReference,
          {
            // Most recent completed charging payment.
            'actual_income':
            amount.toStringAsFixed(2),

            // Lifetime accumulated income.
            'total_income':
            newTotalIncome.toStringAsFixed(2),

            // Booking is now completed.
            'booking_date': '',
            'booking_time': '',
            'booking_user_id': '',
          },
        );
      },
    );
  }

  Future<void> _showFinishChargingPopup() async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,

      // User must choose Yes or No.
      barrierDismissible: false,

      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),

            title: const Row(
              children: [
                Icon(
                  Icons.ev_station_rounded,
                  color: AppColors.primary,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Charging Session',
                  ),
                ),
              ],
            ),

            content: Text(
              'Did you finish charging at '
                  '${widget.destinationName}?',
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
              ),
            ),

            actions: [
              // ---------------------------------------------------------------
              // NO
              // ---------------------------------------------------------------

              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();

                  debugPrint(
                    'ARRIVAL_DEBUG: Driver selected NO - '
                        'charging was not completed.',
                  );
                },
                child: const Text(
                  'No',
                ),
              ),

              // ---------------------------------------------------------------
              // YES
              // ---------------------------------------------------------------

              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();

                  debugPrint(
                    'ARRIVAL_DEBUG: Driver selected YES - '
                        'charging completed.',
                  );

                  // Give the first dialog a moment to close.
                  await Future.delayed(
                    const Duration(milliseconds: 150),
                  );

                  if (!mounted) {
                    return;
                  }

                  // Open the mandatory amount-paid popup.
                  await _showAmountPaidPopup();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'Yes, Finished',
                ),
              ),
            ],
          ),
        );
      },
    );
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
        ..color = AppColors.primary.withOpacity(0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      20,
      Paint()
        ..color = AppColors.primary.withOpacity(0.22)
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
        ..color = AppColors.primary
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
      ..color = AppColors.primary
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
        color: AppColors.primary,
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
        color: AppColors.primary.withOpacity(0.22),
        points: _routeCoords,
        width: 12,
        zIndex: 0,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
      Polyline(
        polylineId: const PolylineId("route"),
        color: AppColors.primary,
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
  Future<void> _launchGoogleMapsNavigation() async {
    if (_currentPosition == null) return;

    final Uri googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
          '&origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
          '&destination=${_destination.latitude},${_destination.longitude}'
          '&travelmode=driving',
    );

    try {
      // Mark that external navigation is about to start.
      //
      // When ChargePath becomes active again,
      // didChangeAppLifecycleState() will perform
      // the 100 m check.
      _navigationOpened = true;

      final bool launched = await launchUrl(
        googleMapsUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _navigationOpened = false;
      }
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    } catch (e) {
      _navigationOpened = false;
      debugPrint("Could not launch Google Maps: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    }
  }

  // ── 4. BUILD ──────────────────────────────────────────────────────────────
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
      backgroundColor: AppColors.background,
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
      backgroundColor: AppColors.background,
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
                color: AppColors.white,
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
        color: AppColors.background,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              Text(
                'Getting your location...',
                style: TextStyle(
                  color: AppColors.textSecondary,
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
          color: AppColors.white,
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
          color: AppColors.textPrimary,
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
        color: AppColors.white,
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
                AppSpacing.xxl,
                AppSpacing.sm,
                AppSpacing.xxl,
                AppSpacing.xxl,
              ),
              physics: const BouncingScrollPhysics(),
              children: [
                _buildRouteHeader(),
                const SizedBox(height: 24),
                _buildStatsPanel(),
                const SizedBox(height: 24),
                _buildTimeline(),
                const SizedBox(height: AppSpacing.lg),
                _buildRouteStatusCard(),
                const SizedBox(height: AppSpacing.xl),
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
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xl,
          ),
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
          ),
          child: const Row(
            children: [
              Icon(
                Icons.navigation_rounded,
                color: AppColors.white,
                size: 28,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Charging Route',
                  style: TextStyle(
                    color: AppColors.white,
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
            padding: const EdgeInsets.all(AppSpacing.xxl),
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
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.alt_route_rounded,
            color: AppColors.white,
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
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                'Optimal charging route',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
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
            AppColors.textPrimary,
          ),
          _buildDivider(),
          _buildStatItem(
            _totalDuration,
            'Duration',
            Icons.access_time_rounded,
            AppColors.textPrimary,
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
                color: AppColors.textSecondary,
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
                color: AppColors.white,
                size: 20,
              ),
              label: Text(
                _isLoading
                    ? 'Loading...'
                    : 'Start Navigation',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLoading
                    ? Colors.grey.shade400
                    : AppColors.primary,
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
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 22),
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
            color: AppColors.textSecondary,
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
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        color: AppColors.white,
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
                      color: AppColors.primary.withOpacity(0.15),
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
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            details,
                            style: TextStyle(
                              color: AppColors.textSecondary,
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
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: AppColors.primary,
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
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Icon(icon, color: AppColors.textSecondary, size: 22),
    );
  }
}