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
  State<RoutePlanningPage> createState() =>
      _RoutePlanningPageState();
}

class _RoutePlanningPageState
    extends State<RoutePlanningPage> {
  // ---------------------------------------------------------------------------
  // CONFIGURATION
  // ---------------------------------------------------------------------------

  final String _googleApiKey =
      "AIzaSyALER_NJqGFdwseum4UGUk_wTTYZbGK-es";

  double _currentBattery = 60.0;

  bool _isReturnTrip = false;

  final Set<String> _selectedActivityPreferences =
  <String>{};

  static const List<String> _activityOptions = [
    'Dine & Charge',
    'Shop & Charge',
    'Grocery & Charge',
    'Stay & Charge',
  ];

  String _selectedConnector = "Type 1";

  static const List<String> _connectorOptions = [
    "Type 1",
    "Type 2",
    "Type 3",
    "CCS2",
    "CHAdeMO",
    "GBT",
  ];

  final Completer<GoogleMapController> _controller =
  Completer<GoogleMapController>();

  bool _isLoading = false;

  // ---------------------------------------------------------------------------
  // TEXT CONTROLLERS
  // ---------------------------------------------------------------------------

  final TextEditingController _startController =
  TextEditingController();

  final TextEditingController _endController =
  TextEditingController();

  final TextEditingController _rangeController =
  TextEditingController(
    text: "100",
  );

  // ---------------------------------------------------------------------------
  // API RESULT
  // ---------------------------------------------------------------------------

  List<dynamic> _outboundStops = [];
  List<dynamic> _returnStops = [];

  // API messages returned when stops cannot be produced.
  String? _outboundMessage;
  String? _returnMessage;

  // Tells the UI that a route request has actually completed.
  bool _hasRouteResult = false;

  Set<Marker> _markers = {};

  double _totalDistance = 0.0;

  // ---------------------------------------------------------------------------
  // MAP HELPERS
  // ---------------------------------------------------------------------------

  List<dynamic> get _allRouteStops {
    return [
      ..._outboundStops,
      ..._returnStops,
    ];
  }

  int get _totalStopCount {
    return _outboundStops.length +
        _returnStops.length;
  }

  static const CameraPosition _kInitialLocation =
  CameraPosition(
    target: LatLng(
      6.9271,
      79.8612,
    ),
    zoom: 10,
  );

  // ---------------------------------------------------------------------------
  // ACTIVITY PREFERENCE IDS
  // ---------------------------------------------------------------------------

  List<int> _getSelectedCategoryIds() {
    final List<int> categoryIds = [];

    for (final String preference
    in _selectedActivityPreferences) {
      switch (preference) {
        case 'Grocery & Charge':
          categoryIds.add(1);
          break;

        case 'Dine & Charge':
          categoryIds.add(2);
          break;

        case 'Shop & Charge':
          categoryIds.add(3);
          break;

        case 'Stay & Charge':
          categoryIds.add(4);
          break;
      }
    }

    categoryIds.sort();

    return categoryIds;
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _rangeController.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // API MESSAGE HELPERS
  // ---------------------------------------------------------------------------

  // This is the serious case:
  //
  // "No stations found for the current range and can't reach the destination"
  //
  // This means the driver's battery/range cannot complete that part of
  // the journey.
  //
  // We show this as a RED timed notification.
  bool _isRangeFailureMessage(
      String? message,
      ) {
    if (message == null) {
      return false;
    }

    final String lower =
    message.toLowerCase();

    return lower.contains(
      'no stations found for the current range',
    ) &&
        lower.contains(
          'reach the destination',
        );
  }

  // This is NOT treated as an error notification.
  //
  // Example:
  // "There are no charging stations available for your preference"
  //
  // This is displayed inside the Charging Stops card.
  bool _isPreferenceNoStationMessage(
      String? message,
      ) {
    if (message == null) {
      return false;
    }

    final String lower =
    message.toLowerCase();

    return lower.contains(
      'no charging stations available for your preference',
    );
  }

  // Get the preference-related message from either journey direction.
  String? _getPreferenceNoStationMessage() {
    if (_isPreferenceNoStationMessage(
      _outboundMessage,
    )) {
      return _outboundMessage;
    }

    if (_isPreferenceNoStationMessage(
      _returnMessage,
    )) {
      return _returnMessage;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // RED RANGE FAILURE NOTIFICATION
  // ---------------------------------------------------------------------------

  void _showRangeFailureNotification(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    final ScaffoldMessengerState messenger =
    ScaffoldMessenger.of(context);

    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white,
              size: 22,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        backgroundColor:
        Colors.red.shade700,
        behavior:
        SnackBarBehavior.floating,
        duration:
        const Duration(seconds: 5),
        margin:
        const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius:
          BorderRadius.circular(14),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FETCH ROUTE
  // ---------------------------------------------------------------------------

  Future<void> _fetchRoute() async {
    // -------------------------------------------------------------------------
    // BASIC VALIDATION
    // -------------------------------------------------------------------------

    if (_startController.text.trim().isEmpty ||
        _endController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter both an origin and a destination.',
          ),
        ),
      );

      return;
    }

    // -------------------------------------------------------------------------
    // RESET PREVIOUS RESULT
    // -------------------------------------------------------------------------

    setState(() {
      _isLoading = true;

      _markers.clear();

      _outboundStops.clear();
      _returnStops.clear();

      _outboundMessage = null;
      _returnMessage = null;

      _hasRouteResult = false;

      _totalDistance = 0.0;
    });

    const String apiUrl =
        'https://chargepathmodel.onrender.com/plan_route';

    try {
      // -----------------------------------------------------------------------
      // BUILD REQUEST
      // -----------------------------------------------------------------------

      final List<int> categoryIds =
      _getSelectedCategoryIds();

      final Map<String, dynamic> requestBody = {
        'start_point':
        _startController.text.trim(),

        'end_point':
        _endController.text.trim(),

        'max_range_km':
        int.tryParse(
          _rangeController.text.trim(),
        ) ??
            100,

        'current_battery_pct':
        _currentBattery.toInt(),

        'required_connector':
        _selectedConnector,

        'return_trip':
        _isReturnTrip ? 1 : 0,

        'nearby_category_ids':
        categoryIds,
      };

      debugPrint(
        'PLAN ROUTE REQUEST:',
      );

      debugPrint(
        jsonEncode(
          requestBody,
        ),
      );

      // -----------------------------------------------------------------------
      // CALL API
      // -----------------------------------------------------------------------

      final http.Response response =
      await http.post(
        Uri.parse(
          apiUrl,
        ),
        headers: {
          'Content-Type':
          'application/json',
        },
        body: jsonEncode(
          requestBody,
        ),
      );

      debugPrint(
        'PLAN ROUTE STATUS CODE: '
            '${response.statusCode}',
      );

      debugPrint(
        'PLAN ROUTE RESPONSE:',
      );

      debugPrint(
        response.body,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Server returned status code '
              '${response.statusCode}',
        );
      }

      // -----------------------------------------------------------------------
      // DECODE RESPONSE
      // -----------------------------------------------------------------------

      final dynamic decodedResponse =
      jsonDecode(
        response.body,
      );

      if (decodedResponse
      is! Map<String, dynamic>) {
        throw Exception(
          'Unexpected response format from the server.',
        );
      }

      final dynamic resultData =
      decodedResponse['Result'];

      if (resultData
      is! Map<String, dynamic>) {
        throw Exception(
          'The API response does not contain a valid Result object.',
        );
      }

      // =======================================================================
      // OUTBOUND
      // =======================================================================

      List<dynamic> outboundStops = [];

      String? outboundMessage;

      final dynamic outboundData =
      resultData['outbound'];

      if (outboundData
      is Map<String, dynamic>) {
        final dynamic stops =
        outboundData['stops'];

        if (stops is List) {
          outboundStops =
          List<dynamic>.from(
            stops,
          );
        }

        final dynamic message =
        outboundData['message'];

        if (message != null &&
            message
                .toString()
                .trim()
                .isNotEmpty) {
          outboundMessage =
              message
                  .toString()
                  .trim();
        }
      }

      // =======================================================================
      // RETURN
      // =======================================================================

      List<dynamic> returnStops = [];

      String? returnMessage;

      final dynamic returnData =
      resultData['return'];

      if (returnData
      is Map<String, dynamic>) {
        final dynamic stops =
        returnData['stops'];

        if (stops is List) {
          returnStops =
          List<dynamic>.from(
            stops,
          );
        }

        final dynamic message =
        returnData['message'];

        if (message != null &&
            message
                .toString()
                .trim()
                .isNotEmpty) {
          returnMessage =
              message
                  .toString()
                  .trim();
        }
      }

      // -----------------------------------------------------------------------
      // ONE WAY TRIP
      // -----------------------------------------------------------------------
      //
      // Ignore anything returned inside "return" when the driver selected
      // One Way.
      // -----------------------------------------------------------------------

      if (!_isReturnTrip) {
        returnStops = [];
        returnMessage = null;
      }

      // -----------------------------------------------------------------------
      // CALCULATE DISTANCE
      // -----------------------------------------------------------------------

      double calculatedDistance = 0.0;

      for (final dynamic stop
      in outboundStops) {
        if (stop
        is Map<String, dynamic>) {
          calculatedDistance +=
              (stop['DistancetoFind']
              as num?)
                  ?.toDouble() ??
                  0.0;
        }
      }

      for (final dynamic stop
      in returnStops) {
        if (stop
        is Map<String, dynamic>) {
          calculatedDistance +=
              (stop['DistancetoFind']
              as num?)
                  ?.toDouble() ??
                  0.0;
        }
      }

      if (!mounted) {
        return;
      }

      // -----------------------------------------------------------------------
      // SAVE RESPONSE
      // -----------------------------------------------------------------------

      setState(() {
        _outboundStops =
            outboundStops;

        _returnStops =
            returnStops;

        _outboundMessage =
            outboundMessage;

        _returnMessage =
            returnMessage;

        _totalDistance =
            calculatedDistance;

        _hasRouteResult = true;
      });

      // =======================================================================
      // RANGE FAILURE
      // =======================================================================
      //
      // Example:
      //
      // outbound:
      //   station available
      //
      // return:
      //   no reachable station because battery/range is insufficient
      //
      // This gets a RED TIMED NOTIFICATION.
      // =======================================================================

      if (_isRangeFailureMessage(
        outboundMessage,
      )) {
        _showRangeFailureNotification(
          outboundMessage!,
        );
      } else if (_isRangeFailureMessage(
        returnMessage,
      )) {
        _showRangeFailureNotification(
          returnMessage!,
        );
      }

      // -----------------------------------------------------------------------
      // MAP STOPS
      // -----------------------------------------------------------------------

      final List<dynamic> mapStops = [
        ...outboundStops,
        ...returnStops,
      ];

      _generateMarkers(
        outboundStops:
        outboundStops,
        returnStops:
        returnStops,
      );

      // Only adjust map bounds when we actually have stops.
      //
      // IMPORTANT:
      // We intentionally DO NOT show a generic SnackBar when no stations
      // exist. Preference-related "no station" messages are displayed inside
      // the Charging Stops card instead.
      if (mapStops.isNotEmpty) {
        await _fitMapBounds(
          mapStops,
        );
      }
    } catch (error) {
      debugPrint(
        'PLAN ROUTE ERROR: $error',
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              'Unable to plan route: $error',
            ),
            backgroundColor:
            Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // GENERATE MAP MARKERS
  // ---------------------------------------------------------------------------

  void _generateMarkers({
    required List<dynamic> outboundStops,
    required List<dynamic> returnStops,
  }) {
    final Set<Marker> newMarkers = {};

    // -------------------------------------------------------------------------
    // OUTBOUND MARKERS
    // -------------------------------------------------------------------------

    for (int index = 0;
    index < outboundStops.length;
    index++) {
      final dynamic rawStop =
      outboundStops[index];

      if (rawStop
      is! Map<String, dynamic>) {
        continue;
      }

      final double lat =
          (rawStop['Latitude'] as num?)
              ?.toDouble() ??
              0.0;

      final double lng =
          (rawStop['Longitude'] as num?)
              ?.toDouble() ??
              0.0;

      final String name =
          rawStop['StationName']
              ?.toString() ??
              'Charging Station';

      final String chargeNeeded =
          rawStop['NeedChargePercentage']
              ?.toString() ??
              '--';

      newMarkers.add(
        Marker(
          markerId: MarkerId(
            'outbound_${index}_$name',
          ),
          position: LatLng(
            lat,
            lng,
          ),
          infoWindow: InfoWindow(
            title: name,
            snippet:
            'Outbound • Charge needed: '
                '$chargeNeeded',
          ),
          icon:
          BitmapDescriptor
              .defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ChargingRoute(
                      destination:
                      LatLng(
                        lat,
                        lng,
                      ),
                      destinationName:
                      name,
                    ),
              ),
            );
          },
        ),
      );
    }

    // -------------------------------------------------------------------------
    // RETURN MARKERS
    // -------------------------------------------------------------------------

    for (int index = 0;
    index < returnStops.length;
    index++) {
      final dynamic rawStop =
      returnStops[index];

      if (rawStop
      is! Map<String, dynamic>) {
        continue;
      }

      final double lat =
          (rawStop['Latitude'] as num?)
              ?.toDouble() ??
              0.0;

      final double lng =
          (rawStop['Longitude'] as num?)
              ?.toDouble() ??
              0.0;

      final String name =
          rawStop['StationName']
              ?.toString() ??
              'Charging Station';

      final String chargeNeeded =
          rawStop['NeedChargePercentage']
              ?.toString() ??
              '--';

      newMarkers.add(
        Marker(
          markerId: MarkerId(
            'return_${index}_$name',
          ),
          position: LatLng(
            lat,
            lng,
          ),
          infoWindow: InfoWindow(
            title: name,
            snippet:
            'Return • Charge needed: '
                '$chargeNeeded',
          ),
          icon:
          BitmapDescriptor
              .defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ChargingRoute(
                      destination:
                      LatLng(
                        lat,
                        lng,
                      ),
                      destinationName:
                      name,
                    ),
              ),
            );
          },
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // FIT MAP BOUNDS
  // ---------------------------------------------------------------------------

  Future<void> _fitMapBounds(
      List<dynamic> stops,
      ) async {
    if (stops.isEmpty) {
      return;
    }

    final dynamic firstStop =
        stops.first;

    if (firstStop
    is! Map<String, dynamic>) {
      return;
    }

    double minLat =
        (firstStop['Latitude'] as num?)
            ?.toDouble() ??
            0.0;

    double maxLat = minLat;

    double minLng =
        (firstStop['Longitude'] as num?)
            ?.toDouble() ??
            0.0;

    double maxLng = minLng;

    for (final dynamic rawStop
    in stops) {
      if (rawStop
      is! Map<String, dynamic>) {
        continue;
      }

      final double lat =
          (rawStop['Latitude'] as num?)
              ?.toDouble() ??
              0.0;

      final double lng =
          (rawStop['Longitude'] as num?)
              ?.toDouble() ??
              0.0;

      if (lat < minLat) {
        minLat = lat;
      }

      if (lat > maxLat) {
        maxLat = lat;
      }

      if (lng < minLng) {
        minLng = lng;
      }

      if (lng > maxLng) {
        maxLng = lng;
      }
    }

    final GoogleMapController controller =
    await _controller.future;

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            minLat - 0.1,
            minLng - 0.1,
          ),
          northeast: LatLng(
            maxLat + 0.1,
            maxLng + 0.1,
          ),
        ),
        60,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(
      BuildContext context,
      ) {
    return _buildMobileLayout();
  }

  // ---------------------------------------------------------------------------
  // MOBILE LAYOUT
  // ---------------------------------------------------------------------------

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor:
      AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildMobileHeader(),

            Expanded(
              child:
              SingleChildScrollView(
                physics:
                const ClampingScrollPhysics(),
                padding:
                const EdgeInsets
                    .fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  110,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    _buildRouteLocationsCard(),

                    const SizedBox(
                      height:
                      AppSpacing.lg,
                    ),

                    _buildVehicleSettingsCard(),

                    const SizedBox(
                      height:
                      AppSpacing.xl,
                    ),

                    _buildPlanRouteButton(),

                    const SizedBox(
                      height:
                      AppSpacing.xxl,
                    ),

                    _buildMapCard(
                      mapHeight: 220,
                    ),

                    const SizedBox(
                      height:
                      AppSpacing.lg,
                    ),

                    _buildChargingStopsCard(),

                    const SizedBox(
                      height:
                      AppSpacing.lg,
                    ),

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

  // ---------------------------------------------------------------------------
  // MOBILE HEADER
  // ---------------------------------------------------------------------------

  Widget _buildMobileHeader() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      decoration:
      const BoxDecoration(
        gradient:
        AppColors.primaryGradient,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.alt_route_rounded,
                color: Colors.white,
                size: 28,
              ),
              SizedBox(
                width: AppSpacing.sm,
              ),
              Expanded(
                child: Text(
                  'Route Planning',
                  style: TextStyle(
                    color:
                    Colors.white,
                    fontSize: 22,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: AppSpacing.sm,
          ),

          Text(
            'Plan an EV-friendly journey using your battery, '
                'range, and connector requirements.',
            style: TextStyle(
              color:
              Colors.white.withOpacity(
                0.78,
              ),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WIDE LAYOUT
  // ---------------------------------------------------------------------------

  Widget _buildWideLayout() {
    return Scaffold(
      backgroundColor:
      AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 370,
              decoration:
              BoxDecoration(
                color: Colors.white,
                border: Border(
                  right: BorderSide(
                    color:
                    Colors.grey.shade200,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _buildWideHeader(),

                  Expanded(
                    child:
                    SingleChildScrollView(
                      physics:
                      const ClampingScrollPhysics(),
                      padding:
                      const EdgeInsets
                          .fromLTRB(
                        20,
                        20,
                        20,
                        24,
                      ),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                        children: [
                          _buildRouteLocationsCard(
                            showShadow:
                            false,
                          ),

                          const SizedBox(
                            height: 16,
                          ),

                          _buildVehicleSettingsCard(
                            showShadow:
                            false,
                          ),

                          const SizedBox(
                            height: 20,
                          ),

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
                padding:
                const EdgeInsets
                    .all(
                  22,
                ),
                child:
                LayoutBuilder(
                  builder: (
                      context,
                      constraints,
                      ) {
                    final bool
                    useSideDetails =
                        constraints
                            .maxWidth >=
                            760;

                    if (useSideDetails) {
                      return Row(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child:
                            _buildWideMapPanel(),
                          ),

                          const SizedBox(
                            width: 18,
                          ),

                          Expanded(
                            flex: 2,
                            child:
                            SingleChildScrollView(
                              physics:
                              const ClampingScrollPhysics(),
                              child:
                              Column(
                                children: [
                                  _buildChargingStopsCard(),

                                  const SizedBox(
                                    height:
                                    16,
                                  ),

                                  _buildTripSummaryCard(
                                    summaryColumns:
                                    1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child:
                          _buildWideMapPanel(),
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        Expanded(
                          flex: 2,
                          child:
                          SingleChildScrollView(
                            physics:
                            const ClampingScrollPhysics(),
                            child:
                            Column(
                              children: [
                                _buildChargingStopsCard(),

                                const SizedBox(
                                  height:
                                  16,
                                ),

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

  // ---------------------------------------------------------------------------
  // WIDE HEADER
  // ---------------------------------------------------------------------------

  Widget _buildWideHeader() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.fromLTRB(
        22,
        24,
        22,
        20,
      ),
      decoration:
      const BoxDecoration(
        gradient:
        AppColors.primaryGradient,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.alt_route_rounded,
                color: Colors.white,
                size: 30,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Route Planning',
                  style: TextStyle(
                    color:
                    Colors.white,
                    fontSize: 24,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            'Plan an EV-friendly journey using your battery, '
                'range, and connector requirements.',
            style: TextStyle(
              color:
              Colors.white.withOpacity(
                0.82,
              ),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ROUTE LOCATIONS CARD
  // ---------------------------------------------------------------------------

  Widget _buildRouteLocationsCard({
    bool showShadow = true,
  }) {
    return _buildCard(
      showShadow:
      showShadow,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Plan Your Route',
            Icons.alt_route_rounded,
          ),

          const SizedBox(
            height: 20,
          ),

          _buildLocationHeader(),

          const SizedBox(
            height: 20,
          ),

          _buildTripTypeSelector(),

          const SizedBox(
            height: 14,
          ),

          _buildChargingPreferencesMenuRow(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VEHICLE SETTINGS
  // ---------------------------------------------------------------------------

  Widget _buildVehicleSettingsCard({
    bool showShadow = true,
  }) {
    return _buildCard(
      showShadow:
      showShadow,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Vehicle Settings',
            Icons.electric_car_rounded,
          ),

          const SizedBox(
            height: 20,
          ),

          _buildBatterySlider(),

          const SizedBox(
            height: 20,
          ),

          _buildLabeledField(
            label:
            'Max Range',
            sublabel: 'km',
            child:
            _buildBlueTextBox(
              'e.g. 100',
              _rangeController,
              isNumber: true,
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          _buildConnectorSelector(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PLAN ROUTE BUTTON
  // ---------------------------------------------------------------------------

  Widget _buildPlanRouteButton() {
    return AppPrimaryButton(
      text: _isLoading
          ? 'Planning...'
          : 'Plan Route',
      icon:
      Icons.navigation_rounded,
      isLoading:
      _isLoading,
      onPressed:
      _isLoading
          ? null
          : _fetchRoute,
    );
  }

  // ---------------------------------------------------------------------------
  // MAP CARD
  // ---------------------------------------------------------------------------

  Widget _buildMapCard({
    required double mapHeight,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Route Preview',
            Icons.map_rounded,
          ),

          const SizedBox(
            height: 16,
          ),

          _buildMapPreview(
            height: mapHeight,
          ),
        ],
      ),
    );
  }

  Widget _buildWideMapPanel() {
    return _buildCard(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child:
                _buildSectionTitle(
                  'Route Preview',
                  Icons.map_rounded,
                ),
              ),

              if (_allRouteStops
                  .isNotEmpty)
                Container(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    AppColors.primary
                        .withOpacity(
                      0.09,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      20,
                    ),
                  ),
                  child: Text(
                    '${_totalDistance.toStringAsFixed(1)} km',
                    style:
                    const TextStyle(
                      color:
                      AppColors.primary,
                      fontSize: 12,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          Expanded(
            child:
            _buildMapPreview(
              expand: true,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CHARGING STOPS
  // ---------------------------------------------------------------------------

  Widget _buildChargingStopsCard() {
    final bool hasAnyStops =
        _totalStopCount > 0;

    final String? preferenceMessage =
    _getPreferenceNoStationMessage();

    return _buildCard(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child:
                _buildSectionTitle(
                  'Charging Stops',
                  Icons.ev_station_rounded,
                ),
              ),

              if (hasAnyStops)
                Container(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    AppColors.success
                        .withValues(
                      alpha: 0.12,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      20,
                    ),
                  ),
                  child: Text(
                    '$_totalStopCount '
                        '${_totalStopCount == 1 ? 'stop' : 'stops'}',
                    style:
                    const TextStyle(
                      color:
                      AppColors.success,
                      fontSize: 12,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          // ===================================================================
          // ZERO STOPS
          // ===================================================================

          if (!hasAnyStops)
            _buildNoStopsResult(
              preferenceMessage,
            )

          // ===================================================================
          // HAS AT LEAST ONE STOP
          // ===================================================================

          else ...[
            // -----------------------------------------------------------------
            // OUTBOUND
            // -----------------------------------------------------------------

            _buildStopSectionHeader(
              title:
              'Outbound',
              icon:
              Icons.arrow_forward_rounded,
              stopCount:
              _outboundStops.length,
            ),

            const SizedBox(
              height: 10,
            ),

            if (_outboundStops.isEmpty)
              _buildNoStopsMessage(
                _isRangeFailureMessage(
                  _outboundMessage,
                )
                    ? 'No reachable charging station was found for the outbound journey.'
                    : _outboundMessage ??
                    'No charging stop required on the outbound journey.',
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics:
                const NeverScrollableScrollPhysics(),
                itemCount:
                _outboundStops.length,
                itemBuilder: (
                    context,
                    index,
                    ) {
                  return _buildStopItem(
                    index + 1,
                    _outboundStops[index],
                  );
                },
              ),

            // -----------------------------------------------------------------
            // RETURN
            // -----------------------------------------------------------------

            if (_isReturnTrip) ...[
              const SizedBox(
                height: 18,
              ),

              Divider(
                color:
                Colors.grey.shade200,
                height: 1,
              ),

              const SizedBox(
                height: 18,
              ),

              _buildStopSectionHeader(
                title:
                'Return',
                icon:
                Icons.keyboard_return_rounded,
                stopCount:
                _returnStops.length,
              ),

              const SizedBox(
                height: 10,
              ),

              if (_returnStops.isEmpty)
                _buildNoStopsMessage(
                  _isRangeFailureMessage(
                    _returnMessage,
                  )
                      ? 'No reachable charging station was found for the return journey.'
                      : _returnMessage ??
                      'No charging stop required on the return journey.',
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics:
                  const NeverScrollableScrollPhysics(),
                  itemCount:
                  _returnStops.length,
                  itemBuilder: (
                      context,
                      index,
                      ) {
                    return _buildStopItem(
                      index + 1,
                      _returnStops[index],
                    );
                  },
                ),
            ],
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ZERO-STOPS RESULT
  // ---------------------------------------------------------------------------

  Widget _buildNoStopsResult(
      String? preferenceMessage,
      ) {
    // Before the user has planned anything.
    if (!_hasRouteResult) {
      return Center(
        child: Padding(
          padding:
          const EdgeInsets
              .symmetric(
            vertical: 24,
          ),
          child: Column(
            children: [
              Icon(
                Icons
                    .ev_station_outlined,
                size: 48,
                color:
                Colors.grey.shade300,
              ),

              const SizedBox(
                height: 12,
              ),

              Text(
                'Route not calculated yet',
                style: TextStyle(
                  color: AppColors
                      .textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // -------------------------------------------------------------------------
    // NO STATIONS FOR DRIVER PREFERENCES
    // -------------------------------------------------------------------------
    //
    // NO SnackBar is shown.
    //
    // We only display the API message inside this card.
    // -------------------------------------------------------------------------

    if (preferenceMessage != null) {
      return Container(
        width: double.infinity,
        padding:
        const EdgeInsets.all(
          16,
        ),
        decoration: BoxDecoration(
          color:
          AppColors.lightFill,
          borderRadius:
          BorderRadius.circular(
            14,
          ),
        ),
        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons
                  .ev_station_outlined,
              color:
              AppColors.primary,
              size: 22,
            ),

            const SizedBox(
              width: 10,
            ),

            Expanded(
              child: Text(
                preferenceMessage,
                style:
                const TextStyle(
                  color:
                  AppColors
                      .textSecondary,
                  fontSize: 13,
                  height: 1.45,
                  fontWeight:
                  FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // -------------------------------------------------------------------------
    // OTHER ZERO-STATION RESULT
    // -------------------------------------------------------------------------

    return Center(
      child: Padding(
        padding:
        const EdgeInsets
            .symmetric(
          vertical: 24,
          horizontal: 12,
        ),
        child: Column(
          children: [
            Icon(
              Icons
                  .ev_station_outlined,
              size: 48,
              color:
              Colors.grey.shade300,
            ),

            const SizedBox(
              height: 12,
            ),

            Text(
              'No suitable charging stations were found for this route.',
              textAlign:
              TextAlign.center,
              style: TextStyle(
                color:
                AppColors
                    .textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STOP SECTION HEADER
  // ---------------------------------------------------------------------------

  Widget _buildStopSectionHeader({
    required String title,
    required IconData icon,
    required int stopCount,
  }) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration:
          BoxDecoration(
            color: AppColors.primary
                .withValues(
              alpha: 0.10,
            ),
            borderRadius:
            BorderRadius.circular(
              9,
            ),
          ),
          child: Icon(
            icon,
            size: 17,
            color:
            AppColors.primary,
          ),
        ),

        const SizedBox(
          width: 9,
        ),

        Expanded(
          child: Text(
            title,
            style:
            const TextStyle(
              fontSize: 13,
              fontWeight:
              FontWeight.bold,
              color:
              AppColors
                  .textPrimary,
            ),
          ),
        ),

        Text(
          '$stopCount '
              '${stopCount == 1 ? 'stop' : 'stops'}',
          style: TextStyle(
            fontSize: 11,
            fontWeight:
            FontWeight.w600,
            color:
            AppColors
                .textSecondary,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // NO STOP MESSAGE
  // ---------------------------------------------------------------------------

  Widget _buildNoStopsMessage(
      String message,
      ) {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets
          .symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color:
        AppColors.background,
        borderRadius:
        BorderRadius.circular(
          12,
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color:
            AppColors.primary,
            size: 18,
          ),

          const SizedBox(
            width: 8,
          ),

          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color:
                AppColors
                    .textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TRIP SUMMARY
  // ---------------------------------------------------------------------------

  Widget _buildTripSummaryCard({
    int summaryColumns = 2,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            'Trip Summary',
            Icons.summarize_rounded,
          ),

          const SizedBox(
            height: 16,
          ),

          _buildTripSummaryGrid(
            crossAxisCount:
            summaryColumns,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GENERIC CARD
  // ---------------------------------------------------------------------------

  Widget _buildCard({
    required Widget child,
    bool showShadow = true,
  }) {
    if (showShadow) {
      return AppCard(
        padding:
        const EdgeInsets.all(
          AppSpacing.xl,
        ),
        child: child,
      );
    }

    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.all(
        AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color:
        AppColors.white,
        borderRadius:
        BorderRadius.circular(
          20,
        ),
        border: Border.all(
          color:
          const Color(
            0xFFE5E7EB,
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(
      String title,
      IconData icon,
      ) {
    return AppSectionHeader(
      icon: icon,
      title: title,
    );
  }

  // ---------------------------------------------------------------------------
  // ROUTE LOCATION INPUTS
  // ---------------------------------------------------------------------------

  Widget _buildLocationHeader() {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
          const EdgeInsets.only(
            top: 34,
          ),
          child: Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration:
                BoxDecoration(
                  color:
                  AppColors.success,
                  shape:
                  BoxShape.circle,
                  border: Border.all(
                    color:
                    Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                      AppColors
                          .success
                          .withOpacity(
                        0.4,
                      ),
                      blurRadius:
                      6,
                      offset:
                      const Offset(
                        0,
                        2,
                      ),
                    ),
                  ],
                ),
              ),

              ...List.generate(
                6,
                    (_) => Container(
                  width: 2,
                  height: 8,
                  margin:
                  const EdgeInsets
                      .symmetric(
                    vertical: 2,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    Colors.grey
                        .shade300,
                    borderRadius:
                    BorderRadius
                        .circular(
                      1,
                    ),
                  ),
                ),
              ),

              Container(
                width: 14,
                height: 14,
                decoration:
                BoxDecoration(
                  color:
                  Colors.red
                      .shade500,
                  shape:
                  BoxShape.circle,
                  border: Border.all(
                    color:
                    Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                      Colors.red
                          .withOpacity(
                        0.35,
                      ),
                      blurRadius:
                      6,
                      offset:
                      const Offset(
                        0,
                        2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(
          width: 16,
        ),

        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              _buildFieldLabel(
                "Origin",
                Icons.my_location_rounded,
                Colors.green.shade600,
              ),

              const SizedBox(
                height: 6,
              ),

              _buildBlueTextBox(
                "Enter starting point",
                _startController,
              ),

              const SizedBox(
                height: 16,
              ),

              _buildFieldLabel(
                "Destination",
                Icons.location_on_rounded,
                Colors.red.shade500,
              ),

              const SizedBox(
                height: 6,
              ),

              _buildBlueTextBox(
                "Enter destination",
                _endController,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(
      String text,
      IconData icon,
      Color color,
      ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: color,
        ),

        const SizedBox(
          width: 5,
        ),

        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight:
            FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildLabeledField({
    required String label,
    String? sublabel,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                FontWeight.w600,
                color:
                AppColors
                    .textSecondary,
              ),
            ),

            if (sublabel != null) ...[
              const SizedBox(
                width: 4,
              ),

              Text(
                "($sublabel)",
                style: TextStyle(
                  fontSize: 12,
                  color:
                  AppColors
                      .textSecondary,
                ),
              ),
            ],
          ],
        ),

        const SizedBox(
          height: 8,
        ),

        child,
      ],
    );
  }

  Widget _buildBlueTextBox(
      String hint,
      TextEditingController controller, {
        bool isNumber = false,
      }) {
    return Container(
      decoration:
      BoxDecoration(
        color:
        AppColors.lightFill,
        borderRadius:
        BorderRadius.circular(
          12,
        ),
      ),
      child: TextField(
        controller:
        controller,
        keyboardType:
        isNumber
            ? TextInputType.number
            : TextInputType.text,
        decoration:
        InputDecoration(
          hintText: hint,
          hintStyle:
          TextStyle(
            color:
            AppColors
                .textSecondary,
            fontSize: 14,
            fontWeight:
            FontWeight.w400,
          ),
          border:
          InputBorder.none,
          contentPadding:
          const EdgeInsets
              .symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          suffixIcon:
          isNumber
              ? Icon(
            Icons
                .speed_rounded,
            size: 18,
            color: AppColors
                .primary
                .withOpacity(
              0.5,
            ),
          )
              : Icon(
            Icons
                .search_rounded,
            size: 18,
            color: AppColors
                .primary
                .withOpacity(
              0.5,
            ),
          ),
        ),
        style:
        const TextStyle(
          fontWeight:
          FontWeight.bold,
          fontSize: 14,
          color:
          AppColors
              .textPrimary,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONNECTOR SELECTOR
  // ---------------------------------------------------------------------------

  Widget _buildConnectorSelector() {
    return _buildLabeledField(
      label:
      "Connector Type",
      child: Container(
        padding:
        const EdgeInsets
            .symmetric(
          horizontal: 14,
          vertical: 4,
        ),
        decoration:
        BoxDecoration(
          color:
          AppColors.lightFill,
          borderRadius:
          BorderRadius.circular(
            12,
          ),
        ),
        child:
        DropdownButtonHideUnderline(
          child:
          DropdownButton<String>(
            value:
            _selectedConnector,
            isExpanded: true,
            icon: const Icon(
              Icons
                  .keyboard_arrow_down_rounded,
              color:
              AppColors.primary,
            ),
            items:
            _connectorOptions
                .map(
                  (String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Row(
                    children: [
                      const Icon(
                        Icons
                            .electrical_services_rounded,
                        color:
                        AppColors
                            .primary,
                        size: 18,
                      ),

                      const SizedBox(
                        width: 10,
                      ),

                      Text(
                        value,
                        style:
                        const TextStyle(
                          fontWeight:
                          FontWeight
                              .bold,
                          fontSize:
                          14,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ).toList(),
            onChanged:
                (newValue) {
              if (newValue ==
                  null) {
                return;
              }

              setState(() {
                _selectedConnector =
                    newValue;
              });
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TRIP TYPE
  // ---------------------------------------------------------------------------

  Widget _buildTripTypeSelector() {
    return _buildLabeledField(
      label:
      'Trip Type',
      child: Container(
        padding:
        const EdgeInsets.all(
          4,
        ),
        decoration:
        BoxDecoration(
          color:
          AppColors.lightFill,
          borderRadius:
          BorderRadius.circular(
            12,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child:
              _buildTripTypeOption(
                label:
                'One Way',
                icon:
                Icons
                    .arrow_forward_rounded,
                selected:
                !_isReturnTrip,
                onTap: () {
                  setState(() {
                    _isReturnTrip =
                    false;
                  });
                },
              ),
            ),

            const SizedBox(
              width: 6,
            ),

            Expanded(
              child:
              _buildTripTypeOption(
                label:
                'Return Trip',
                icon:
                Icons
                    .sync_alt_rounded,
                selected:
                _isReturnTrip,
                onTap: () {
                  setState(() {
                    _isReturnTrip =
                    true;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripTypeOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color:
      Colors.transparent,
      child: InkWell(
        onTap:
        onTap,
        borderRadius:
        BorderRadius.circular(
          10,
        ),
        child:
        AnimatedContainer(
          duration:
          const Duration(
            milliseconds: 180,
          ),
          padding:
          const EdgeInsets
              .symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          decoration:
          BoxDecoration(
            color: selected
                ? AppColors.primary
                : Colors.transparent,
            borderRadius:
            BorderRadius.circular(
              10,
            ),
          ),
          child: Row(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? Colors.white
                    : AppColors
                    .textSecondary,
              ),

              const SizedBox(
                width: 6,
              ),

              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  TextStyle(
                    color: selected
                        ? Colors.white
                        : AppColors
                        .textSecondary,
                    fontSize: 12,
                    fontWeight: selected
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CHARGING PREFERENCES
  // ---------------------------------------------------------------------------

  Widget _buildChargingPreferencesMenuRow() {
    final int selectedCount =
        _selectedActivityPreferences.length;

    final bool hasSelection =
        selectedCount > 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text(
                    'Charging Preferences',
                    style:
                    TextStyle(
                      fontSize: 13,
                      fontWeight:
                      FontWeight
                          .w600,
                      color:
                      AppColors
                          .textSecondary,
                    ),
                  ),

                  SizedBox(
                    width: 6,
                  ),

                  Text(
                    '(Optional)',
                    style:
                    TextStyle(
                      fontSize: 11,
                      color:
                      AppColors
                          .textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 3,
              ),

              Text(
                hasSelection
                    ? '$selectedCount preference'
                    '${selectedCount == 1 ? '' : 's'} selected'
                    : 'No preference selected',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                  hasSelection
                      ? FontWeight
                      .w700
                      : FontWeight
                      .w500,
                  color:
                  hasSelection
                      ? AppColors
                      .primary
                      : AppColors
                      .textSecondary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(
          width: 10,
        ),

        Material(
          color:
          Colors.transparent,
          child: InkWell(
            onTap:
            _showChargingPreferencesSheet,
            borderRadius:
            BorderRadius.circular(
              12,
            ),
            child: Container(
              width: 44,
              height: 44,
              decoration:
              BoxDecoration(
                color: hasSelection
                    ? AppColors.lightFill
                    : AppColors.background,
                borderRadius:
                BorderRadius.circular(
                  12,
                ),
                border: Border.all(
                  color: hasSelection
                      ? AppColors.primary
                      .withValues(
                    alpha: 0.35,
                  )
                      : const Color(
                    0xFFE5E7EB,
                  ),
                ),
              ),
              child: Stack(
                alignment:
                Alignment.center,
                children: [
                  Icon(
                    Icons
                        .tune_rounded,
                    color: hasSelection
                        ? AppColors
                        .primary
                        : AppColors
                        .textSecondary,
                    size: 21,
                  ),

                  if (hasSelection)
                    Positioned(
                      top: 7,
                      right: 7,
                      child:
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                        const BoxDecoration(
                          color:
                          AppColors
                              .primary,
                          shape:
                          BoxShape
                              .circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showChargingPreferencesSheet() {
    showModalBottomSheet(
      context:
      context,
      isScrollControlled:
      true,
      backgroundColor:
      AppColors.white,
      shape:
      const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(
          top:
          Radius.circular(
            24,
          ),
        ),
      ),
      builder:
          (sheetContext) {
        return StatefulBuilder(
          builder: (
              context,
              setSheetState,
              ) {
            void togglePreference(
                String option,
                ) {
              setState(() {
                if (_selectedActivityPreferences
                    .contains(
                  option,
                )) {
                  _selectedActivityPreferences
                      .remove(
                    option,
                  );
                } else {
                  _selectedActivityPreferences
                      .add(
                    option,
                  );
                }
              });

              setSheetState(
                    () {},
              );
            }

            final bool hasSelection =
                _selectedActivityPreferences
                    .isNotEmpty;

            final Size screenSize =
            MediaQuery.sizeOf(
              context,
            );

            final bool isShortHeight =
                screenSize.height <
                    500;

            final double sheetHeight =
            isShortHeight
                ? screenSize
                .height *
                0.78
                : screenSize
                .height *
                0.58;

            return SafeArea(
              top: false,
              child: SizedBox(
                height:
                sheetHeight,
                child: Column(
                  children: [
                    Padding(
                      padding:
                      EdgeInsets
                          .fromLTRB(
                        AppSpacing.xl,
                        isShortHeight
                            ? 8
                            : AppSpacing
                            .md,
                        AppSpacing.xl,
                        0,
                      ),
                      child: Column(
                        children: [
                          Center(
                            child:
                            Container(
                              width: 40,
                              height: 4,
                              decoration:
                              BoxDecoration(
                                color:
                                const Color(
                                  0xFFD1D5DB,
                                ),
                                borderRadius:
                                BorderRadius
                                    .circular(
                                  2,
                                ),
                              ),
                            ),
                          ),

                          SizedBox(
                            height: isShortHeight
                                ? 8
                                : AppSpacing
                                .lg,
                          ),

                          Row(
                            children: [
                              Expanded(
                                child:
                                Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                                  children: [
                                    Text(
                                      'Charging Preferences',
                                      style:
                                      TextStyle(
                                        fontSize: isShortHeight
                                            ? 17
                                            : 20,
                                        fontWeight:
                                        FontWeight
                                            .bold,
                                        color:
                                        AppColors
                                            .textPrimary,
                                      ),
                                    ),

                                    SizedBox(
                                      height: isShortHeight
                                          ? 2
                                          : 4,
                                    ),

                                    Text(
                                      'Select any activities you prefer while charging.',
                                      style:
                                      TextStyle(
                                        fontSize: isShortHeight
                                            ? 10
                                            : 12,
                                        color:
                                        AppColors
                                            .textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (hasSelection)
                                TextButton(
                                  onPressed:
                                      () {
                                    setState(
                                          () {
                                        _selectedActivityPreferences
                                            .clear();
                                      },
                                    );

                                    setSheetState(
                                          () {},
                                    );
                                  },
                                  child:
                                  Text(
                                    'Clear all',
                                    style:
                                    TextStyle(
                                      color:
                                      AppColors
                                          .primary,
                                      fontWeight:
                                      FontWeight
                                          .w700,
                                      fontSize: isShortHeight
                                          ? 11
                                          : 13,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(
                      height: 6,
                    ),

                    Expanded(
                      child:
                      ListView
                          .separated(
                        physics:
                        const ClampingScrollPhysics(),
                        padding:
                        EdgeInsets
                            .symmetric(
                          horizontal:
                          AppSpacing
                              .xl,
                          vertical:
                          isShortHeight
                              ? 4
                              : AppSpacing
                              .sm,
                        ),
                        itemCount:
                        _activityOptions
                            .length,
                        separatorBuilder:
                            (_, __) =>
                            SizedBox(
                              height:
                              isShortHeight
                                  ? 6
                                  : AppSpacing
                                  .sm,
                            ),
                        itemBuilder:
                            (
                            context,
                            index,
                            ) {
                          final String
                          option =
                          _activityOptions[
                          index];

                          final bool
                          selected =
                          _selectedActivityPreferences
                              .contains(
                            option,
                          );

                          return Material(
                            color: Colors
                                .transparent,
                            child:
                            InkWell(
                              onTap: () =>
                                  togglePreference(
                                    option,
                                  ),
                              borderRadius:
                              BorderRadius
                                  .circular(
                                14,
                              ),
                              child:
                              AnimatedContainer(
                                duration:
                                const Duration(
                                  milliseconds:
                                  180,
                                ),
                                width:
                                double
                                    .infinity,
                                padding:
                                EdgeInsets
                                    .symmetric(
                                  horizontal:
                                  isShortHeight
                                      ? 12
                                      : 14,
                                  vertical:
                                  isShortHeight
                                      ? 9
                                      : 13,
                                ),
                                decoration:
                                BoxDecoration(
                                  color: selected
                                      ? AppColors
                                      .lightFill
                                      : AppColors
                                      .background,
                                  borderRadius:
                                  BorderRadius
                                      .circular(
                                    14,
                                  ),
                                  border:
                                  Border.all(
                                    color: selected
                                        ? AppColors
                                        .primary
                                        .withValues(
                                      alpha:
                                      0.45,
                                    )
                                        : const Color(
                                      0xFFE5E7EB,
                                    ),
                                  ),
                                ),
                                child:
                                Row(
                                  children: [
                                    Container(
                                      width: isShortHeight
                                          ? 30
                                          : 36,
                                      height: isShortHeight
                                          ? 30
                                          : 36,
                                      decoration:
                                      BoxDecoration(
                                        color: selected
                                            ? AppColors
                                            .primary
                                            : AppColors
                                            .white,
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                          10,
                                        ),
                                      ),
                                      child:
                                      Icon(
                                        _activityIcon(
                                          option,
                                        ),
                                        color: selected
                                            ? Colors
                                            .white
                                            : AppColors
                                            .primary,
                                        size: isShortHeight
                                            ? 17
                                            : 19,
                                      ),
                                    ),

                                    const SizedBox(
                                      width: 10,
                                    ),

                                    Expanded(
                                      child:
                                      Text(
                                        option,
                                        style:
                                        TextStyle(
                                          fontSize: isShortHeight
                                              ? 12
                                              : 14,
                                          fontWeight: selected
                                              ? FontWeight
                                              .w700
                                              : FontWeight
                                              .w600,
                                          color: selected
                                              ? AppColors
                                              .primary
                                              : AppColors
                                              .textPrimary,
                                        ),
                                      ),
                                    ),

                                    Icon(
                                      selected
                                          ? Icons
                                          .check_circle_rounded
                                          : Icons
                                          .radio_button_unchecked_rounded,
                                      color: selected
                                          ? AppColors
                                          .primary
                                          : AppColors
                                          .textSecondary,
                                      size: isShortHeight
                                          ? 18
                                          : 21,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    Padding(
                      padding:
                      EdgeInsets
                          .fromLTRB(
                        AppSpacing.xl,
                        isShortHeight
                            ? 4
                            : AppSpacing
                            .sm,
                        AppSpacing.xl,
                        isShortHeight
                            ? 8
                            : AppSpacing
                            .lg,
                      ),
                      child: SizedBox(
                        width:
                        double
                            .infinity,
                        height:
                        isShortHeight
                            ? 42
                            : 48,
                        child:
                        ElevatedButton(
                          onPressed:
                              () {
                            Navigator.pop(
                              sheetContext,
                            );
                          },
                          style:
                          ElevatedButton
                              .styleFrom(
                            backgroundColor:
                            AppColors
                                .primary,
                            foregroundColor:
                            Colors.white,
                            elevation: 0,
                            shape:
                            RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius
                                  .circular(
                                14,
                              ),
                            ),
                          ),
                          child:
                          Text(
                            'Apply Preferences',
                            style:
                            TextStyle(
                              fontWeight:
                              FontWeight
                                  .bold,
                              fontSize:
                              isShortHeight
                                  ? 12
                                  : 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _activityIcon(
      String option,
      ) {
    switch (option) {
      case 'Dine & Charge':
        return Icons
            .restaurant_rounded;

      case 'Shop & Charge':
        return Icons
            .shopping_bag_rounded;

      case 'Grocery & Charge':
        return Icons
            .local_grocery_store_rounded;

      case 'Stay & Charge':
        return Icons
            .hotel_rounded;

      default:
        return Icons
            .bolt_rounded;
    }
  }

  // ---------------------------------------------------------------------------
  // BATTERY SLIDER
  // ---------------------------------------------------------------------------

  Widget _buildBatterySlider() {
    final Color batteryColor =
    _currentBattery < 20
        ? Colors.red.shade500
        : _currentBattery < 50
        ? Colors.orange.shade600
        : AppColors.success;

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
          MainAxisAlignment
              .spaceBetween,
          children: [
            Text(
              "Current Battery Level",
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                FontWeight.w600,
                color:
                AppColors
                    .textSecondary,
              ),
            ),

            Container(
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 12,
                vertical: 5,
              ),
              decoration:
              BoxDecoration(
                color:
                batteryColor
                    .withOpacity(
                  0.12,
                ),
                borderRadius:
                BorderRadius
                    .circular(
                  20,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentBattery >
                        70
                        ? Icons
                        .battery_full_rounded
                        : _currentBattery >
                        30
                        ? Icons
                        .battery_4_bar_rounded
                        : Icons
                        .battery_1_bar_rounded,
                    color:
                    batteryColor,
                    size: 16,
                  ),

                  const SizedBox(
                    width: 4,
                  ),

                  Text(
                    "${_currentBattery.toInt()}%",
                    style:
                    TextStyle(
                      fontWeight:
                      FontWeight
                          .bold,
                      fontSize: 13,
                      color:
                      batteryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 8,
        ),

        SliderTheme(
          data:
          SliderTheme.of(context)
              .copyWith(
            trackHeight: 6,
            activeTrackColor:
            batteryColor,
            inactiveTrackColor:
            AppColors.lightFill,
            thumbColor:
            batteryColor,
            overlayColor:
            batteryColor
                .withOpacity(
              0.15,
            ),
            thumbShape:
            const RoundSliderThumbShape(
              enabledThumbRadius:
              10,
            ),
          ),
          child: Slider(
            value:
            _currentBattery,
            min: 0,
            max: 100,
            onChanged: (value) {
              setState(() {
                _currentBattery =
                    value;
              });
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MAP PREVIEW
  // ---------------------------------------------------------------------------

  Widget _buildMapPreview({
    double? height,
    bool expand = false,
  }) {
    final Widget map =
    ClipRRect(
      borderRadius:
      BorderRadius.circular(
        14,
      ),
      child: GoogleMap(
        mapType:
        MapType.normal,
        initialCameraPosition:
        _kInitialLocation,
        zoomControlsEnabled:
        false,
        markers:
        _markers,
        onMapCreated:
            (
            GoogleMapController controller,
            ) {
          if (!_controller
              .isCompleted) {
            _controller.complete(
              controller,
            );
          }
        },
      ),
    );

    if (expand) {
      return SizedBox.expand(
        child: map,
      );
    }

    return SizedBox(
      height:
      height ?? 200,
      width:
      double.infinity,
      child: map,
    );
  }

  // ---------------------------------------------------------------------------
  // STOP ITEM
  // ---------------------------------------------------------------------------

  Widget _buildStopItem(
      int index,
      dynamic stop,
      ) {
    final double lat =
    (stop['Latitude'] as num)
        .toDouble();

    final double lng =
    (stop['Longitude'] as num)
        .toDouble();

    final String name =
    stop['StationName']
        .toString();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChargingRoute(
                  destination:
                  LatLng(
                    lat,
                    lng,
                  ),
                  destinationName:
                  name,
                ),
          ),
        );
      },
      child: Container(
        margin:
        const EdgeInsets.only(
          bottom: 12,
        ),
        padding:
        const EdgeInsets.all(
          14,
        ),
        decoration:
        BoxDecoration(
          color:
          const Color(
            0xFFF8FAFC,
          ),
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          border: Border.all(
            color:
            Colors.grey
                .shade100,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration:
              BoxDecoration(
                color:
                AppColors.success,
                shape:
                BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                    AppColors
                        .success
                        .withOpacity(
                      0.3,
                    ),
                    blurRadius:
                    8,
                    offset:
                    const Offset(
                      0,
                      3,
                    ),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  "$index",
                  style:
                  const TextStyle(
                    color:
                    Colors.white,
                    fontWeight:
                    FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

            const SizedBox(
              width: 14,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                children: [
                  Text(
                    name,
                    style:
                    const TextStyle(
                      fontWeight:
                      FontWeight.bold,
                      fontSize: 14,
                      color:
                      AppColors
                          .textPrimary,
                    ),
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Row(
                    children: [
                      const Icon(
                        Icons
                            .straighten_rounded,
                        size: 12,
                        color:
                        AppColors
                            .textSecondary,
                      ),

                      const SizedBox(
                        width: 4,
                      ),

                      Text(
                        "${stop['DistancetoFind']} km",
                        style:
                        const TextStyle(
                          color:
                          AppColors
                              .textSecondary,
                          fontSize:
                          12,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  const Row(
                    children: [
                      Icon(
                        Icons
                            .navigation_rounded,
                        size: 12,
                        color:
                        AppColors
                            .primary,
                      ),

                      SizedBox(
                        width: 4,
                      ),

                      Text(
                        "Tap to Navigate",
                        style:
                        TextStyle(
                          fontSize: 11,
                          color:
                          AppColors
                              .primary,
                          fontWeight:
                          FontWeight
                              .bold,
                        ),
                      ),

                      SizedBox(
                        width: 4,
                      ),

                      Icon(
                        Icons
                            .arrow_forward_rounded,
                        size: 11,
                        color:
                        AppColors
                            .primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Container(
              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration:
              BoxDecoration(
                color:
                AppColors.success
                    .withOpacity(
                  0.12,
                ),
                borderRadius:
                BorderRadius
                    .circular(
                  10,
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    size: 14,
                    color:
                    AppColors.success,
                  ),

                  Text(
                    "${stop['NeedChargePercentage']}",
                    style:
                    const TextStyle(
                      color:
                      AppColors.success,
                      fontWeight:
                      FontWeight.bold,
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

  // ---------------------------------------------------------------------------
  // TRIP SUMMARY GRID
  // ---------------------------------------------------------------------------

  Widget _buildTripSummaryGrid({
    int crossAxisCount = 2,
  }) {
    return GridView.count(
      shrinkWrap: true,
      physics:
      const NeverScrollableScrollPhysics(),
      crossAxisCount:
      crossAxisCount,
      crossAxisSpacing:
      12,
      mainAxisSpacing:
      12,
      childAspectRatio:
      crossAxisCount == 1
          ? 3.6
          : 2.4,
      children: [
        _summaryCard(
          Icons
              .straighten_rounded,
          "${_totalDistance.toStringAsFixed(1)} km",
          "Total Distance",
          Colors.blue.shade600,
        ),

        _summaryCard(
          Icons
              .access_time_rounded,
          "--",
          "Est. Time",
          Colors.purple.shade400,
        ),
      ],
    );
  }

  Widget _summaryCard(
      IconData icon,
      String value,
      String label,
      Color iconColor,
      ) {
    return Container(
      padding:
      const EdgeInsets
          .symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration:
      BoxDecoration(
        color:
        iconColor.withOpacity(
          0.06,
        ),
        borderRadius:
        BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color:
          iconColor.withOpacity(
            0.12,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding:
            const EdgeInsets
                .all(
              7,
            ),
            decoration:
            BoxDecoration(
              color:
              iconColor
                  .withOpacity(
                0.12,
              ),
              borderRadius:
              BorderRadius
                  .circular(
                10,
              ),
            ),
            child: Icon(
              icon,
              color:
              iconColor,
              size: 18,
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              mainAxisAlignment:
              MainAxisAlignment
                  .center,
              children: [
                Text(
                  value,
                  style:
                  const TextStyle(
                    fontWeight:
                    FontWeight.bold,
                    fontSize: 15,
                    color:
                    AppColors
                        .textPrimary,
                  ),
                ),

                Text(
                  label,
                  style:
                  const TextStyle(
                    color:
                    AppColors
                        .textSecondary,
                    fontSize: 10,
                    fontWeight:
                    FontWeight.w500,
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