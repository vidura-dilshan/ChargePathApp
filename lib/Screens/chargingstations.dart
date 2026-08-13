import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:chargepath/Theme/app_colors.dart';
import 'package:chargepath/Theme/app_spacing.dart';
import 'package:chargepath/Widgets/app_card.dart';

import 'bookstation.dart';
import 'chargingroute.dart';
import 'favorites_db.dart';

class FindStations extends StatefulWidget {
  const FindStations({super.key});

  @override
  State<FindStations> createState() => _FindStationsState();
}

class _FindStationsState extends State<FindStations> {
  // Google Maps API key
  static const String _googleApiKey =
      'AIzaSyALER_NJqGFdwseum4UGUk_wTTYZbGK-es';

  // Stations with charging_power >= this are treated as Fast.
  static const double _fastChargingThreshold = 50.0;

  // ---------------------------------------------------------------------------
  // STATE
  // ---------------------------------------------------------------------------

  bool _isNearbySelected = true;

  double _distanceValue = 5.0;

  String _selectedConnectorType = 'All';
  String _selectedChargingType = 'All';

  LatLng? _currentUserPosition;

  bool _isLoadingLocation = false;

  // ---------------------------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------------------------

  final TextEditingController _searchController = TextEditingController();

  final FocusNode _searchFocusNode = FocusNode();

  LatLng? _searchedTownPosition;
  String? _searchedTownName;

  bool _isSearchActive = false;
  bool _isSearching = false;

  // ---------------------------------------------------------------------------
  // FAVOURITES
  // ---------------------------------------------------------------------------

  final Set<String> _favoriteIds = {};

  late final Stream<QuerySnapshot> _stationsStream;

  // ---------------------------------------------------------------------------
  // FILTER OPTIONS
  // ---------------------------------------------------------------------------

  static const List<String> _connectorTypes = [
    'All',
    'Type 1',
    'Type 2',
    'Type 3',
    'CCS2',
    'CHAdeMO',
    'GBT',
  ];

  static const List<String> _chargingTypes = [
    'All',
    'Fast',
    'Normal',
  ];

  bool get _showDistanceSlider =>
      _isNearbySelected ||
          _isSearchActive ||
          _searchedTownPosition != null;

  /// Number displayed on the mobile filter icon.
  int get _activeFilterCount {
    int count = 0;

    if (_selectedConnectorType != 'All') {
      count++;
    }

    if (_selectedChargingType != 'All') {
      count++;
    }

    // Distance is only counted as an active filter if it differs
    // from the default 5 km value.
    if (_showDistanceSlider && _distanceValue != 5.0) {
      count++;
    }

    return count;
  }

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _getUserLocation();
    _loadFavorites();

    FavoritesDb.favoritesChanged.addListener(
      _onFavoritesChanged,
    );

    _stationsStream =
        FirebaseFirestore.instance.collection('users').snapshots();

    _searchFocusNode.addListener(() {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSearchActive = _searchFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    FavoritesDb.favoritesChanged.removeListener(
      _onFavoritesChanged,
    );

    _searchController.dispose();
    _searchFocusNode.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // FAVOURITES
  // ---------------------------------------------------------------------------

  Future<void> _loadFavorites() async {
    try {
      // SQLite is not currently used on Flutter Web.
      if (kIsWeb) {
        if (!mounted) {
          return;
        }

        setState(() {
          _favoriteIds.clear();
        });

        return;
      }

      final List<Map<String, dynamic>> rows =
      await FavoritesDb.instance.getAllFavorites();

      if (!mounted) {
        return;
      }

      setState(() {
        _favoriteIds
          ..clear()
          ..addAll(
            rows.map(
                  (row) => row['station_id'].toString(),
            ),
          );
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to load favourites: $error',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _favoriteIds.clear();
      });
    }
  }

  void _onFavoritesChanged() {
    _loadFavorites();
  }

  Future<void> _toggleFavorite(
      String stationId,
      Map<String, dynamic> data,
      ) async {
    final bool isFavourite = _favoriteIds.contains(stationId);

    try {
      if (!kIsWeb) {
        if (isFavourite) {
          await FavoritesDb.instance.removeFavorite(
            stationId,
          );
        } else {
          await FavoritesDb.instance.addFavorite(
            stationId,
            data,
          );
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        if (isFavourite) {
          _favoriteIds.remove(stationId);
        } else {
          _favoriteIds.add(stationId);
        }
      });

      _showTopSnack(
        isFavourite
            ? 'Removed from favourites'
            : 'Added to favourites',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to update favourite: $error',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      _showInfoSnack(
        'Unable to update favourites.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SNACKBARS
  // ---------------------------------------------------------------------------

  void _showTopSnack(String message) {
    final ScaffoldMessengerState messenger =
    ScaffoldMessenger.of(context);

    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              message.contains('Added')
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
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
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 130,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
        ),
      ),
    );
  }

  void _showInfoSnack(String message) {
    final ScaffoldMessengerState messenger =
    ScaffoldMessenger.of(context);

    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 130,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOCATION
  // ---------------------------------------------------------------------------

  Future<void> _getUserLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      final bool serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
          });
        }

        return;
      }

      LocationPermission permission =
      await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _isLoadingLocation = false;
            });
          }

          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
          });
        }

        return;
      }

      final Position position =
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentUserPosition = LatLng(
          position.latitude,
          position.longitude,
        );

        _isLoadingLocation = false;
      });
    } catch (error) {
      debugPrint(
        'Location error: $error',
      );

      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    FocusManager.instance.primaryFocus?.unfocus();

    _searchController.clear();

    if (mounted) {
      setState(() {
        _searchedTownPosition = null;
        _searchedTownName = null;

        // Current location filtering requires Nearby mode.
        _isNearbySelected = true;
      });
    }

    await _getUserLocation();
  }

  // ---------------------------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------------------------

  Future<void> _searchTown(
      String query,
      ) async {
    final String cleanQuery = query.trim();

    if (cleanQuery.isEmpty) {
      _clearSearch();
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
    });

    try {
      final Uri url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
            '?address=${Uri.encodeComponent(cleanQuery)}'
            '&key=$_googleApiKey',
      );

      final http.Response response =
      await http.get(url);

      final Map<String, dynamic> body =
      json.decode(response.body) as Map<String, dynamic>;

      final List results =
          (body['results'] as List?) ?? [];

      if (body['status'] == 'OK' && results.isNotEmpty) {
        final dynamic location =
        results[0]['geometry']['location'];

        final double latitude =
        (location['lat'] as num).toDouble();

        final double longitude =
        (location['lng'] as num).toDouble();

        final String name =
            results[0]['formatted_address']?.toString() ??
                cleanQuery;

        if (!mounted) {
          return;
        }

        setState(() {
          _searchedTownPosition = LatLng(
            latitude,
            longitude,
          );

          _searchedTownName = name;
          _isSearching = false;
        });
      } else {
        if (!mounted) {
          return;
        }

        setState(() {
          _isSearching = false;
        });

        _showInfoSnack(
          'No location found for "$cleanQuery"',
        );
      }
    } catch (error) {
      debugPrint(
        'Geocoding error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSearching = false;
      });

      _showInfoSnack(
        'Search failed. Check your connection.',
      );
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();

    setState(() {
      _searchedTownPosition = null;
      _searchedTownName = null;
      _isSearching = false;
    });
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  double _parsePower(dynamic raw) {
    final RegExpMatch? match = RegExp(
      r'[\d.]+',
    ).firstMatch(
      raw?.toString() ?? '',
    );

    if (match == null) {
      return 0;
    }

    return double.tryParse(
      match.group(0)!,
    ) ??
        0;
  }

  double _calculateDistanceKm(
      double lat1,
      double lng1,
      double lat2,
      double lng2,
      ) {
    return Geolocator.distanceBetween(
      lat1,
      lng1,
      lat2,
      lng2,
    ) /
        1000;
  }

  List<QueryDocumentSnapshot> _filterStations(
      List<QueryDocumentSnapshot> docs,
      ) {
    final LatLng? filterCenter =
        _searchedTownPosition ??
            (_isNearbySelected
                ? _currentUserPosition
                : null);

    return docs.where((doc) {
      final Map<String, dynamic> data =
      doc.data() as Map<String, dynamic>;

      if (_selectedChargingType != 'All') {
        final double power =
        _parsePower(
          data['charging_power'],
        );

        final bool isFast =
            power >= _fastChargingThreshold;

        if (_selectedChargingType == 'Fast' &&
            !isFast) {
          return false;
        }

        if (_selectedChargingType == 'Normal' &&
            isFast) {
          return false;
        }
      }

      if (_selectedConnectorType != 'All') {
        final String rawConnectors =
            data['supported_connector_types']
                ?.toString() ??
                '';

        final List<String> parts =
        rawConnectors
            .split(',')
            .map(
              (connector) =>
              connector.trim(),
        )
            .toList();

        final bool hasConnector =
        parts.any(
              (part) =>
          part.toLowerCase() ==
              _selectedConnectorType.toLowerCase(),
        );

        if (!hasConnector) {
          return false;
        }
      }

      if (filterCenter != null) {
        final double? latitude =
        double.tryParse(
          data['latitude']?.toString() ?? '',
        );

        final double? longitude =
        double.tryParse(
          data['longitude']?.toString() ?? '',
        );

        if (latitude == null ||
            longitude == null) {
          return false;
        }

        final double distanceKm =
        _calculateDistanceKm(
          filterCenter.latitude,
          filterCenter.longitude,
          latitude,
          longitude,
        );

        if (distanceKm > _distanceValue) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // STANDARD FILTER SHEET
  // Used by tablet / wide layout
  // ---------------------------------------------------------------------------

  void _showFilterSheet(
      String title,
      List<String> options,
      String selected,
      ValueChanged<String> onSelected,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        final double screenHeight =
            MediaQuery.of(sheetContext).size.height;

        final double sheetHeight =
        screenHeight < 500
            ? screenHeight * 0.72
            : screenHeight * 0.55;

        return SizedBox(
          height: sheetHeight,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(
                    top: 10,
                    bottom: 4,
                  ),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius:
                    BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    10,
                    12,
                    10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight:
                            FontWeight.bold,
                            color:
                            AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (selected != 'All')
                        TextButton(
                          onPressed: () {
                            onSelected('All');

                            Navigator.pop(
                              sheetContext,
                            );
                          },
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color:
                              AppColors.primary,
                              fontWeight:
                              FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding:
                    const EdgeInsets.symmetric(
                      vertical: 4,
                    ),
                    physics:
                    const BouncingScrollPhysics(),
                    itemCount: options.length,
                    separatorBuilder: (_, __) {
                      return const Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                      );
                    },
                    itemBuilder: (
                        context,
                        index,
                        ) {
                      final String option =
                      options[index];

                      final bool isSelected =
                          selected == option;

                      return ListTile(
                        dense: screenHeight < 500,
                        contentPadding:
                        const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                        title: Text(
                          option,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors
                                .textPrimary,
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: Icon(
                          isSelected
                              ? Icons
                              .check_circle_rounded
                              : Icons
                              .radio_button_unchecked_rounded,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors
                              .textSecondary,
                          size: 21,
                        ),
                        onTap: () {
                          onSelected(option);

                          Navigator.pop(
                            sheetContext,
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE FILTER SHEET
  // ---------------------------------------------------------------------------

  void _showMobileFiltersSheet() {
    // Temporary values allow the user to change filters without
    // immediately changing the station list.
    double temporaryDistance =
        _distanceValue;

    String temporaryConnector =
        _selectedConnectorType;

    String temporaryCharging =
        _selectedChargingType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
              context,
              setSheetState,
              ) {
            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight:
                  MediaQuery.of(context).size.height *
                      0.82,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  borderRadius:
                  BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Container(
                      width: 42,
                      height: 4,
                      margin:
                      const EdgeInsets.only(
                        top: 10,
                        bottom: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                        Colors.grey.shade300,
                        borderRadius:
                        BorderRadius.circular(2),
                      ),
                    ),

                    // Header
                    Padding(
                      padding:
                      const EdgeInsets.fromLTRB(
                        20,
                        8,
                        12,
                        8,
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Filters',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight:
                                FontWeight.bold,
                                color: AppColors
                                    .textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Navigator.pop(
                                sheetContext,
                              );
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    Flexible(
                      child: SingleChildScrollView(
                        padding:
                        const EdgeInsets.fromLTRB(
                          20,
                          18,
                          20,
                          20,
                        ),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                          children: [
                            // -------------------------------------------------
                            // DISTANCE RADIUS
                            // -------------------------------------------------

                            if (_showDistanceSlider) ...[
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Distance Radius',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight:
                                        FontWeight
                                            .w700,
                                        color: AppColors
                                            .textPrimary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding:
                                    const EdgeInsets
                                        .symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration:
                                    BoxDecoration(
                                      color: AppColors
                                          .lightFill,
                                      borderRadius:
                                      BorderRadius
                                          .circular(
                                        8,
                                      ),
                                    ),
                                    child: Text(
                                      '${temporaryDistance.toInt()} km',
                                      style:
                                      const TextStyle(
                                        color: AppColors
                                            .primary,
                                        fontSize: 13,
                                        fontWeight:
                                        FontWeight
                                            .bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SliderTheme(
                                data:
                                SliderTheme.of(
                                  context,
                                ).copyWith(
                                  activeTrackColor:
                                  AppColors.primary,
                                  inactiveTrackColor:
                                  const Color(
                                    0xFFD1D5DB,
                                  ),
                                  thumbColor:
                                  AppColors.primary,
                                  overlayColor:
                                  AppColors.primary
                                      .withOpacity(
                                    0.10,
                                  ),
                                  trackHeight: 5,
                                  thumbShape:
                                  const RoundSliderThumbShape(
                                    enabledThumbRadius:
                                    9,
                                  ),
                                  overlayShape:
                                  const RoundSliderOverlayShape(
                                    overlayRadius: 16,
                                  ),
                                  trackShape:
                                  const RoundedRectSliderTrackShape(),
                                ),
                                child: Slider(
                                  value:
                                  temporaryDistance,
                                  min: 1,
                                  max: 50,
                                  divisions: 49,
                                  onChanged: (value) {
                                    setSheetState(() {
                                      temporaryDistance =
                                          value;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(
                                height: 20,
                              ),
                              const Divider(height: 1),
                              const SizedBox(
                                height: 20,
                              ),
                            ],

                            // -------------------------------------------------
                            // CONNECTOR TYPE
                            // -------------------------------------------------

                            const Text(
                              'Connector Type',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight:
                                FontWeight.w700,
                                color: AppColors
                                    .textPrimary,
                              ),
                            ),

                            const SizedBox(height: 12),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                              _connectorTypes.map(
                                    (connector) {
                                  final bool
                                  isSelected =
                                      temporaryConnector ==
                                          connector;

                                  return _buildFilterChoice(
                                    label: connector,
                                    isSelected:
                                    isSelected,
                                    onTap: () {
                                      setSheetState(() {
                                        temporaryConnector =
                                            connector;
                                      });
                                    },
                                  );
                                },
                              ).toList(),
                            ),

                            const SizedBox(
                              height: 20,
                            ),

                            const Divider(height: 1),

                            const SizedBox(
                              height: 20,
                            ),

                            // -------------------------------------------------
                            // CHARGING TYPE
                            // -------------------------------------------------

                            const Text(
                              'Charging Type',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight:
                                FontWeight.w700,
                                color: AppColors
                                    .textPrimary,
                              ),
                            ),

                            const SizedBox(height: 12),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                              _chargingTypes.map(
                                    (chargingType) {
                                  final bool
                                  isSelected =
                                      temporaryCharging ==
                                          chargingType;

                                  return _buildFilterChoice(
                                    label:
                                    chargingType ==
                                        'All'
                                        ? 'All'
                                        : '$chargingType Charging',
                                    isSelected:
                                    isSelected,
                                    onTap: () {
                                      setSheetState(() {
                                        temporaryCharging =
                                            chargingType;
                                      });
                                    },
                                  );
                                },
                              ).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ---------------------------------------------------------
                    // CLEAR / APPLY BUTTONS
                    // ---------------------------------------------------------

                    Container(
                      padding:
                      const EdgeInsets.fromLTRB(
                        20,
                        12,
                        20,
                        16,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        border: Border(
                          top: BorderSide(
                            color: Color(
                              0xFFE5E7EB,
                            ),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () {
                                  setSheetState(() {
                                    temporaryDistance =
                                    5.0;

                                    temporaryConnector =
                                    'All';

                                    temporaryCharging =
                                    'All';
                                  });
                                },
                                style:
                                OutlinedButton
                                    .styleFrom(
                                  foregroundColor:
                                  AppColors.primary,
                                  side:
                                  const BorderSide(
                                    color:
                                    AppColors.primary,
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
                                child: const Text(
                                  'Clear',
                                  style: TextStyle(
                                    fontWeight:
                                    FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _distanceValue =
                                        temporaryDistance;

                                    _selectedConnectorType =
                                        temporaryConnector;

                                    _selectedChargingType =
                                        temporaryCharging;
                                  });

                                  Navigator.pop(
                                    sheetContext,
                                  );
                                },
                                style:
                                ElevatedButton
                                    .styleFrom(
                                  elevation: 0,
                                  backgroundColor:
                                  AppColors.primary,
                                  foregroundColor:
                                  Colors.white,
                                  shape:
                                  RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius
                                        .circular(
                                      12,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'Apply',
                                  style: TextStyle(
                                    fontWeight:
                                    FontWeight.w700,
                                  ),
                                ),
                              ),
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
      },
    );
  }

  Widget _buildFilterChoice({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration:
        const Duration(milliseconds: 150),
        padding:
        const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : AppColors.background,
          borderRadius:
          BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : const Color(
              0xFFE5E7EB,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: isSelected
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RESPONSIVE BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final bool useWideLayout =
            constraints.maxWidth >= 700;

        if (useWideLayout) {
          return _buildWideLayout();
        }

        return _buildMobileLayout();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE
  // ---------------------------------------------------------------------------

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildMobileHeader(),

            Expanded(
              child: Column(
                children: [
                  // Compact mobile controls.
                  Padding(
                    padding:
                    const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      0,
                    ),
                    child:
                    _buildMobileControls(),
                  ),

                  const SizedBox(
                    height: AppSpacing.xs,
                  ),

                  Expanded(
                    child: _buildStationResults(
                      useGrid: false,
                      horizontalPadding:
                      AppSpacing.lg,
                      bottomPadding: 100,
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
  // MOBILE CONTROLS
  // ---------------------------------------------------------------------------

  Widget _buildMobileControls() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Nearby / All Stations stays visible on mobile.
            Expanded(
              child: Container(
                padding:
                const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius:
                  BorderRadius.circular(12),
                  border: Border.all(
                    color:
                    const Color(0xFFE5E7EB),
                  ),
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
            ),

            const SizedBox(width: 10),

            // Mobile filter button.
            _buildMobileFilterButton(),
          ],
        ),

        // Keep location information below the toggle,
        // but without the large filters that previously consumed space.
        _buildLocationStatus(),
      ],
    );
  }

  Widget _buildMobileFilterButton() {
    final bool hasActiveFilters =
        _activeFilterCount > 0;

    return Material(
      color: hasActiveFilters
          ? AppColors.primary
          : AppColors.white,
      borderRadius:
      BorderRadius.circular(12),
      child: InkWell(
        onTap: _showMobileFiltersSheet,
        borderRadius:
        BorderRadius.circular(12),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius:
            BorderRadius.circular(12),
            border: Border.all(
              color: hasActiveFilters
                  ? AppColors.primary
                  : const Color(
                0xFFE5E7EB,
              ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  Icons.tune_rounded,
                  color: hasActiveFilters
                      ? Colors.white
                      : AppColors.primary,
                  size: 22,
                ),
              ),

              if (hasActiveFilters)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                        AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                    alignment:
                    Alignment.center,
                    child: Text(
                      '$_activeFilterCount',
                      style:
                      const TextStyle(
                        color:
                        AppColors.primary,
                        fontSize: 10,
                        fontWeight:
                        FontWeight.bold,
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

  // ---------------------------------------------------------------------------
  // TABLET / CAR
  // ---------------------------------------------------------------------------

  Widget _buildWideLayout() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 340,
              decoration:
              const BoxDecoration(
                color: AppColors.white,
                border: Border(
                  right: BorderSide(
                    color: Color(
                      0xFFE5E7EB,
                    ),
                  ),
                ),
              ),
              child: Column(
                children: [
                  _buildWideHeader(),

                  Expanded(
                    child:
                    SingleChildScrollView(
                      padding:
                      const EdgeInsets.only(
                        bottom:
                        AppSpacing.xxl,
                      ),
                      child:
                      _buildControlsPanel(
                        horizontalPadding:
                        AppSpacing.xxl,
                        isWideLayout: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Column(
                children: [
                  _buildWideResultsHeader(),

                  Expanded(
                    child:
                    _buildStationResults(
                      useGrid: true,
                      horizontalPadding:
                      AppSpacing.xxl,
                      bottomPadding:
                      AppSpacing.xxl,
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
  // HEADERS
  // ---------------------------------------------------------------------------

  Widget _buildMobileHeader() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        gradient:
        AppColors.primaryGradient,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.ev_station_rounded,
                color: Colors.white,
                size: 28,
              ),

              const SizedBox(
                width: AppSpacing.sm,
              ),

              const Expanded(
                child: Text(
                  'Find Stations',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ),

              Material(
                color: Colors.white
                    .withOpacity(0.16),
                borderRadius:
                BorderRadius.circular(12),
                child: InkWell(
                  onTap: _isLoadingLocation
                      ? null
                      : _useCurrentLocation,
                  borderRadius:
                  BorderRadius.circular(12),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: _isLoadingLocation
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                        CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                          Colors.white,
                        ),
                      )
                          : const Icon(
                        Icons
                            .my_location_rounded,
                        color:
                        Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: AppSpacing.xs,
          ),

          Text(
            'Search and filter available charging stations.',
            style: TextStyle(
              color: Colors.white
                  .withOpacity(0.78),
              fontSize: 12,
              height: 1.3,
            ),
          ),

          const SizedBox(
            height: AppSpacing.md,
          ),

          // Compact search bar used only on mobile.
          _buildSearchBar(
            useDarkBackground: true,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildWideHeader() {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xl,
      ),
      decoration: const BoxDecoration(
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
                Icons.ev_station_rounded,
                color: Colors.white,
                size: 30,
              ),

              SizedBox(
                width: AppSpacing.sm,
              ),

              Expanded(
                child: Text(
                  'Find Stations',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
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
            'Search and filter available charging stations.',
            style: TextStyle(
              color: Colors.white
                  .withOpacity(0.78),
              fontSize: 13,
              height: 1.4,
            ),
          ),

          const SizedBox(
            height: AppSpacing.lg,
          ),

          _buildSearchBar(
            useDarkBackground: true,
          ),
        ],
      ),
    );
  }

  Widget _buildWideResultsHeader() {
    return Padding(
      padding:
      const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Available Stations',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight:
                    FontWeight.bold,
                    color:
                    AppColors.textPrimary,
                  ),
                ),

                SizedBox(height: 4),

                Text(
                  'Select a station to book or begin route navigation.',
                  style: TextStyle(
                    color: AppColors
                        .textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip:
            'Use current location',
            onPressed: _isLoadingLocation
                ? null
                : _useCurrentLocation,
            icon: const Icon(
              Icons.my_location_rounded,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH BAR
  // ---------------------------------------------------------------------------

  Widget _buildSearchBar({
    bool useDarkBackground = false,
    bool compact = false,
  }) {
    final double searchHeight =
    compact
        ? 40
        : useDarkBackground
        ? 48
        : 44;

    return Container(
      height: searchHeight,
      padding:
      EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius:
        BorderRadius.circular(
          compact ? 12 : 14,
        ),
        border: Border.all(
          color: _isSearchActive
              ? AppColors.primary
              .withOpacity(0.50)
              : const Color(
            0xFFE5E7EB,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(
              useDarkBackground
                  ? 0.12
                  : 0.04,
            ),
            blurRadius:
            compact ? 6 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: _isSearchActive
                ? AppColors.primary
                : AppColors
                .textSecondary,
            size: compact ? 18 : 20,
          ),

          const SizedBox(
            width: AppSpacing.sm,
          ),

          Expanded(
            child: TextField(
              controller:
              _searchController,
              focusNode:
              _searchFocusNode,
              textInputAction:
              TextInputAction.search,
              onSubmitted: _searchTown,
              onChanged: (_) {
                setState(() {});
              },
              style: TextStyle(
                fontSize:
                compact ? 13 : 14,
                color:
                AppColors.textPrimary,
              ),
              decoration:
              const InputDecoration(
                hintText:
                'Search a town or city...',
                border:
                InputBorder.none,
                isCollapsed: true,
                filled: false,
                contentPadding:
                EdgeInsets.zero,
              ),
            ),
          ),

          if (_isSearching)
            SizedBox(
              width: compact ? 16 : 18,
              height: compact ? 16 : 18,
              child:
              const CircularProgressIndicator(
                strokeWidth: 2,
                color:
                AppColors.primary,
              ),
            )
          else if (_searchController
              .text.isNotEmpty) ...[
            GestureDetector(
              onTap: _clearSearch,
              child: Icon(
                Icons.close,
                color: AppColors
                    .textSecondary,
                size: compact ? 18 : 20,
              ),
            ),

            const SizedBox(width: 8),

            GestureDetector(
              onTap: () {
                _searchTown(
                  _searchController.text,
                );
              },
              child: Icon(
                Icons
                    .arrow_circle_right_rounded,
                color:
                AppColors.primary,
                size: compact ? 23 : 26,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WIDE CONTROLS
  // ---------------------------------------------------------------------------

  Widget _buildControlsPanel({
    required double horizontalPadding,
    required bool isWideLayout,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        isWideLayout
            ? AppSpacing.xl
            : 0,
        horizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          if (isWideLayout) ...[
            const Text(
              'Station visibility',
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                FontWeight.bold,
                color:
                AppColors.textPrimary,
              ),
            ),
            const SizedBox(
              height: AppSpacing.sm,
            ),
          ],

          Container(
            padding:
            const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color:
              AppColors.background,
              borderRadius:
              BorderRadius.circular(12),
              border: Border.all(
                color:
                const Color(0xFFE5E7EB),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child:
                  _buildToggleButton(
                    'Nearby',
                    _isNearbySelected,
                  ),
                ),
                Expanded(
                  child:
                  _buildToggleButton(
                    'All Stations',
                    !_isNearbySelected,
                  ),
                ),
              ],
            ),
          ),

          _buildLocationStatus(),

          const SizedBox(
            height: AppSpacing.lg,
          ),

          if (isWideLayout) ...[
            const Text(
              'Filters',
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                FontWeight.bold,
                color:
                AppColors.textPrimary,
              ),
            ),
            const SizedBox(
              height: AppSpacing.sm,
            ),
          ],

          _buildFilterDropdown(
            label:
            _selectedConnectorType ==
                'All'
                ? 'Connector Type'
                : _selectedConnectorType,
            isActive:
            _selectedConnectorType !=
                'All',
            onTap: () {
              _showFilterSheet(
                'Connector Type',
                _connectorTypes,
                _selectedConnectorType,
                    (value) {
                  setState(() {
                    _selectedConnectorType =
                        value;
                  });
                },
              );
            },
          ),

          const SizedBox(
            height: AppSpacing.md,
          ),

          _buildFilterDropdown(
            label:
            _selectedChargingType ==
                'All'
                ? 'Charging Type'
                : '$_selectedChargingType Charging',
            isActive:
            _selectedChargingType !=
                'All',
            onTap: () {
              _showFilterSheet(
                'Charging Type',
                _chargingTypes,
                _selectedChargingType,
                    (value) {
                  setState(() {
                    _selectedChargingType =
                        value;
                  });
                },
              );
            },
          ),

          if (_selectedConnectorType !=
              'All' ||
              _selectedChargingType !=
                  'All') ...[
            const SizedBox(
              height: AppSpacing.sm,
            ),

            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (_selectedConnectorType !=
                    'All')
                  _buildActiveFilterChip(
                    _selectedConnectorType,
                        () {
                      setState(() {
                        _selectedConnectorType =
                        'All';
                      });
                    },
                  ),

                if (_selectedChargingType !=
                    'All')
                  _buildActiveFilterChip(
                    '$_selectedChargingType Charging',
                        () {
                      setState(() {
                        _selectedChargingType =
                        'All';
                      });
                    },
                  ),
              ],
            ),
          ],

          if (_showDistanceSlider) ...[
            const SizedBox(
              height: AppSpacing.lg,
            ),

            Row(
              mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,
              children: [
                const Text(
                  'Distance Radius',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                    FontWeight.w700,
                    color:
                    AppColors.textPrimary,
                  ),
                ),

                Container(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    AppColors.lightFill,
                    borderRadius:
                    BorderRadius.circular(
                      8,
                    ),
                  ),
                  child: Text(
                    '${_distanceValue.toInt()} km',
                    style:
                    const TextStyle(
                      fontSize: 13,
                      fontWeight:
                      FontWeight.bold,
                      color:
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            SizedBox(
              height: 36,
              child: SliderTheme(
                data:
                SliderTheme.of(context)
                    .copyWith(
                  activeTrackColor:
                  AppColors.primary,
                  inactiveTrackColor:
                  const Color(
                    0xFFD1D5DB,
                  ),
                  thumbColor:
                  AppColors.primary,
                  overlayColor:
                  AppColors.primary
                      .withOpacity(0.10),
                  trackHeight: 5,
                  thumbShape:
                  const RoundSliderThumbShape(
                    enabledThumbRadius: 9,
                  ),
                  overlayShape:
                  const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                  trackShape:
                  const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value:
                  _distanceValue,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  onChanged: (value) {
                    setState(() {
                      _distanceValue =
                          value;
                    });
                  },
                ),
              ),
            ),
          ],

          const SizedBox(
            height: AppSpacing.sm,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOCATION STATUS
  // ---------------------------------------------------------------------------

  Widget _buildLocationStatus() {
    if (_searchedTownPosition != null) {
      return Padding(
        padding:
        const EdgeInsets.only(
          top: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.place,
              color:
              AppColors.primary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Within ${_distanceValue.toInt()} km of '
                    '${_searchedTownName ?? 'searched area'}',
                maxLines: 2,
                overflow:
                TextOverflow.ellipsis,
                style:
                const TextStyle(
                  color:
                  AppColors.primary,
                  fontSize: 12,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_isNearbySelected) {
      return const SizedBox.shrink();
    }

    if (_isLoadingLocation) {
      return const Padding(
        padding: EdgeInsets.only(
          top: AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child:
              CircularProgressIndicator(
                strokeWidth: 2,
                color:
                AppColors.primary,
              ),
            ),
            SizedBox(width: 8),
            Text(
              'Getting your location...',
              style: TextStyle(
                color: AppColors
                    .textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    if (_currentUserPosition == null) {
      return Padding(
        padding:
        const EdgeInsets.only(
          top: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_off,
              color:
              AppColors.warning,
              size: 16,
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Location unavailable — showing all stations.',
                style: TextStyle(
                  color:
                  AppColors.warning,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(
              onPressed:
              _getUserLocation,
              child: const Text(
                'Retry',
                style: TextStyle(
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
      );
    }

    return Padding(
      padding:
      const EdgeInsets.only(
        top: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_on,
            color:
            AppColors.success,
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Showing stations within ${_distanceValue.toInt()} km',
              style:
              const TextStyle(
                color:
                AppColors.success,
                fontSize: 12,
                fontWeight:
                FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RESULTS
  // ---------------------------------------------------------------------------

  Widget _buildStationResults({
    required bool useGrid,
    required double horizontalPadding,
    required double bottomPadding,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stationsStream,
      builder: (
          context,
          snapshot,
          ) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child:
            CircularProgressIndicator(
              color:
              AppColors.primary,
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding:
              const EdgeInsets.all(
                AppSpacing.xxl,
              ),
              child: Text(
                'Unable to load stations.\n${snapshot.error}',
                textAlign:
                TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData ||
            snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'No stations found.',
            ),
          );
        }

        final List<QueryDocumentSnapshot>
        filtered =
        _filterStations(
          snapshot.data!.docs,
        );

        if (filtered.isEmpty) {
          return _buildNoStationsState();
        }

        if (!useGrid) {
          return ListView.builder(
            padding:
            EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.sm,
              horizontalPadding,
              bottomPadding,
            ),
            physics:
            const BouncingScrollPhysics(),
            itemCount:
            filtered.length + 1,
            itemBuilder: (
                context,
                index,
                ) {
              if (index == 0) {
                return Padding(
                  padding:
                  const EdgeInsets.only(
                    bottom:
                    AppSpacing.sm,
                  ),
                  child: Text(
                    '${filtered.length} station'
                        '${filtered.length == 1 ? '' : 's'} found',
                    style:
                    const TextStyle(
                      color: AppColors
                          .textSecondary,
                      fontSize: 13,
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),
                );
              }

              return _buildStationFromDocument(
                filtered[index - 1],
              );
            },
          );
        }

        return LayoutBuilder(
          builder: (
              context,
              constraints,
              ) {
            final int columnCount =
            constraints.maxWidth >= 800
                ? 2
                : 1;

            return GridView.builder(
              padding:
              EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.md,
                horizontalPadding,
                bottomPadding,
              ),
              physics:
              const AlwaysScrollableScrollPhysics(),
              itemCount: filtered.length,
              gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                columnCount,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                mainAxisExtent: 410,
              ),
              itemBuilder: (
                  context,
                  index,
                  ) {
                return _buildStationFromDocument(
                  filtered[index],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStationFromDocument(
      QueryDocumentSnapshot document,
      ) {
    final Map<String, dynamic> data =
    document.data()
    as Map<String, dynamic>;

    final int availablePlugs =
        int.tryParse(
          data['available_plugs']
              ?.toString() ??
              '0',
        ) ??
            0;

    final int totalSlots =
        int.tryParse(
          data['connector_slots']
              ?.toString() ??
              '0',
        ) ??
            0;

    final bool isAvailable =
        availablePlugs > 0;

    final String rawConnectors =
        data['supported_connector_types']
            ?.toString() ??
            'Unknown';

    final List<String> connectorList =
    rawConnectors
        .split(',')
        .map(
          (connector) =>
          connector.trim(),
    )
        .where(
          (connector) =>
      connector.isNotEmpty,
    )
        .toList();

    final double? latitude =
    double.tryParse(
      data['latitude']?.toString() ?? '',
    );

    final double? longitude =
    double.tryParse(
      data['longitude']?.toString() ?? '',
    );

    final String stationName =
        data['station_name']?.toString() ??
            'Unknown Station';

    final LatLng? distanceCenter =
        _searchedTownPosition ??
            _currentUserPosition;

    String distanceText = 'N/A';

    if (distanceCenter != null &&
        latitude != null &&
        longitude != null) {
      final double distanceKm =
      _calculateDistanceKm(
        distanceCenter.latitude,
        distanceCenter.longitude,
        latitude,
        longitude,
      );

      distanceText = distanceKm < 1
          ? '${(distanceKm * 1000).toInt()} m away'
          : '${distanceKm.toStringAsFixed(1)} km away';
    }

    return _buildStationCard(
      doc: document,
      name: stationName,
      address:
      data['address']?.toString() ??
          ((latitude != null &&
              longitude != null)
              ? 'Lat: ${latitude.toStringAsFixed(4)}, '
              'Lng: ${longitude.toStringAsFixed(4)}'
              : 'Location unavailable'),
      distance: distanceText,
      availabilityText:
      '$availablePlugs/$totalSlots Available',
      power:
      '${data['charging_power']?.toString() ?? '0'} kW',
      connectors: connectorList,
      statusColor: isAvailable
          ? AppColors.success
          : AppColors.danger,
      isAvailable: isAvailable,
      stationLatLng:
      latitude != null &&
          longitude != null
          ? LatLng(
        latitude,
        longitude,
      )
          : null,
      stationName: stationName,
    );
  }

  // ---------------------------------------------------------------------------
  // NO RESULTS
  // ---------------------------------------------------------------------------

  Widget _buildNoStationsState() {
    final bool radiusActive =
        _searchedTownPosition != null ||
            (_isNearbySelected &&
                _currentUserPosition != null);

    late final String message;

    if (_searchedTownPosition != null) {
      message =
      'No stations within ${_distanceValue.toInt()} km of '
          '${_searchedTownName ?? 'that location'}';
    } else if (_isNearbySelected &&
        _currentUserPosition != null) {
      message =
      'No stations within ${_distanceValue.toInt()} km '
          'of your location';
    } else {
      message =
      'No stations match the selected filters';
    }

    return Center(
      child: SingleChildScrollView(
        padding:
        const EdgeInsets.all(
          AppSpacing.xxxl,
        ),
        child: AppCard(
          padding:
          const EdgeInsets.all(
            AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration:
                const BoxDecoration(
                  color:
                  AppColors.lightFill,
                  shape:
                  BoxShape.circle,
                ),
                child: const Icon(
                  Icons
                      .ev_station_outlined,
                  size: 38,
                  color:
                  AppColors.primary,
                ),
              ),

              const SizedBox(
                height: AppSpacing.lg,
              ),

              Text(
                message,
                textAlign:
                TextAlign.center,
                style:
                const TextStyle(
                  color: AppColors
                      .textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              if (radiusActive) ...[
                const SizedBox(
                  height:
                  AppSpacing.lg,
                ),

                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _distanceValue =
                          (_distanceValue +
                              10)
                              .clamp(
                            1,
                            50,
                          );
                    });
                  },
                  icon: const Icon(
                    Icons.add,
                    color:
                    AppColors.primary,
                  ),
                  label: const Text(
                    'Increase radius',
                    style: TextStyle(
                      color:
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONTROL HELPERS
  // ---------------------------------------------------------------------------

  Widget _buildToggleButton(
      String text,
      bool isSelected,
      ) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isNearbySelected =
              text == 'Nearby';
        });

        if (text == 'Nearby' &&
            _currentUserPosition == null) {
          _getUserLocation();
        }
      },
      child: AnimatedContainer(
        duration:
        const Duration(
          milliseconds: 180,
        ),
        padding:
        const EdgeInsets.symmetric(
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius:
          BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: AppColors.primary
                  .withOpacity(
                0.20,
              ),
              blurRadius: 8,
              offset:
              const Offset(
                0,
                4,
              ),
            ),
          ]
              : [],
        ),
        child: Text(
          text,
          textAlign:
          TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : AppColors
                .textSecondary,
            fontWeight:
            FontWeight.w600,
            fontSize: 14,
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
        padding:
        const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.lightFill
              : AppColors.background,
          borderRadius:
          BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppColors.primary
                .withOpacity(0.50)
                : const Color(
              0xFFE5E7EB,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment:
          MainAxisAlignment
              .spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? AppColors.primary
                      : AppColors
                      .textPrimary,
                  fontSize: 13,
                  fontWeight: isActive
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
                overflow:
                TextOverflow.ellipsis,
              ),
            ),

            Icon(
              Icons
                  .keyboard_arrow_down,
              color: isActive
                  ? AppColors.primary
                  : AppColors
                  .textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFilterChip(
      String label,
      VoidCallback onRemove,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius:
        BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Text(
            label,
            style:
            const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight:
              FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close,
              color: Colors.white,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATION CARD
  // ---------------------------------------------------------------------------

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
    final Map<String, dynamic> data =
    doc.data()
    as Map<String, dynamic>;

    final bool isFavourite =
    _favoriteIds.contains(
      doc.id,
    );

    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: AppSpacing.lg,
      ),
      child: AppCard(
        padding:
        const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration:
                  BoxDecoration(
                    color:
                    AppColors.lightFill,
                    borderRadius:
                    BorderRadius.circular(
                      14,
                    ),
                  ),
                  child: const Icon(
                    Icons
                        .ev_station_rounded,
                    color:
                    AppColors.primary,
                    size: 27,
                  ),
                ),

                const SizedBox(
                  width: AppSpacing.md,
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
                          fontSize: 16,
                          fontWeight:
                          FontWeight.bold,
                          color: AppColors
                              .textPrimary,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow:
                        TextOverflow
                            .ellipsis,
                      ),

                      const SizedBox(
                        height: 5,
                      ),

                      Row(
                        children: [
                          const Icon(
                            Icons
                                .location_on_outlined,
                            size: 14,
                            color: AppColors
                                .textSecondary,
                          ),

                          const SizedBox(
                            width: 4,
                          ),

                          Expanded(
                            child: Text(
                              address,
                              style:
                              const TextStyle(
                                color: AppColors
                                    .textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow:
                              TextOverflow
                                  .ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(
                  width: AppSpacing.sm,
                ),

                GestureDetector(
                  onTap: () {
                    _toggleFavorite(
                      doc.id,
                      data,
                    );
                  },
                  child:
                  AnimatedContainer(
                    duration:
                    const Duration(
                      milliseconds: 200,
                    ),
                    padding:
                    const EdgeInsets.all(
                      8,
                    ),
                    decoration:
                    BoxDecoration(
                      color: isFavourite
                          ? Colors
                          .amber.shade50
                          : AppColors
                          .background,
                      shape:
                      BoxShape.circle,
                      border:
                      Border.all(
                        color: isFavourite
                            ? Colors.amber
                            .shade300
                            : const Color(
                          0xFFE5E7EB,
                        ),
                      ),
                    ),
                    child: Icon(
                      isFavourite
                          ? Icons
                          .star_rounded
                          : Icons
                          .star_outline_rounded,
                      color: isFavourite
                          ? Colors.amber
                          .shade600
                          : AppColors
                          .textSecondary,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: AppSpacing.lg,
            ),

            Row(
              children: [
                _buildStatusBadge(
                  statusColor,
                  availabilityText,
                ),

                const Spacer(),

                _buildSmallInfo(
                  icon:
                  Icons.near_me_rounded,
                  text: distance,
                  iconColor:
                  AppColors.primary,
                ),
              ],
            ),

            const SizedBox(
              height: AppSpacing.lg,
            ),

            const Divider(
              height: 1,
              color:
              Color(0xFFF0F1F3),
            ),

            const SizedBox(
              height: AppSpacing.lg,
            ),

            Row(
              children: [
                Expanded(
                  child:
                  _buildInfoBox(
                    icon: Icons
                        .flash_on_rounded,
                    value: power,
                    label:
                    'Charging Power',
                    color:
                    AppColors.warning,
                  ),
                ),

                const SizedBox(
                  width: AppSpacing.md,
                ),

                Expanded(
                  child:
                  _buildInfoBox(
                    icon:
                    Icons.power_rounded,
                    value:
                    availabilityText,
                    label:
                    'Availability',
                    color:
                    statusColor,
                  ),
                ),
              ],
            ),

            if (connectors.isNotEmpty) ...[
              const SizedBox(
                height: AppSpacing.lg,
              ),

              Wrap(
                spacing: AppSpacing.sm,
                runSpacing:
                AppSpacing.sm,
                children:
                connectors
                    .map(
                      (connector) =>
                      Container(
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal:
                          10,
                          vertical: 6,
                        ),
                        decoration:
                        BoxDecoration(
                          color: AppColors
                              .lightFill,
                          borderRadius:
                          BorderRadius
                              .circular(
                            10,
                          ),
                        ),
                        child: Text(
                          connector,
                          style:
                          const TextStyle(
                            color: AppColors
                                .primary,
                            fontSize: 11,
                            fontWeight:
                            FontWeight
                                .w700,
                          ),
                        ),
                      ),
                )
                    .toList(),
              ),
            ],

            const SizedBox(
              height: AppSpacing.xl,
            ),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child:
                    ElevatedButton.icon(
                      onPressed: isAvailable
                          ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) =>
                                BookStation(
                                  preSelectedStationId:
                                  doc.id,
                                  preSelectedStationName:
                                  stationName,
                                  stationData:
                                  data,
                                ),
                          ),
                        );
                      }
                          : null,
                      icon: const Icon(
                        Icons
                            .bookmark_add_rounded,
                        size: 18,
                      ),
                      label: Text(
                        isAvailable
                            ? 'Book'
                            : 'Full',
                        style:
                        const TextStyle(
                          fontWeight:
                          FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style:
                      ElevatedButton
                          .styleFrom(
                        backgroundColor:
                        isAvailable
                            ? AppColors
                            .primary
                            : const Color(
                          0xFFD1D5DB,
                        ),
                        foregroundColor:
                        Colors.white,
                        disabledBackgroundColor:
                        const Color(
                          0xFFD1D5DB,
                        ),
                        disabledForegroundColor:
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
                    ),
                  ),
                ),

                const SizedBox(
                  width: AppSpacing.md,
                ),

                Expanded(
                  child: SizedBox(
                    height: 48,
                    child:
                    OutlinedButton.icon(
                      onPressed:
                      stationLatLng ==
                          null
                          ? null
                          : () {
                        Navigator
                            .push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) =>
                                ChargingRoute(
                                  destination:
                                  stationLatLng,
                                  destinationName:
                                  stationName,
                                ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons
                            .directions_rounded,
                        size: 18,
                      ),
                      label:
                      const Text(
                        'Route',
                        style: TextStyle(
                          fontWeight:
                          FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style:
                      OutlinedButton
                          .styleFrom(
                        foregroundColor:
                        AppColors.primary,
                        disabledForegroundColor:
                        AppColors
                            .textSecondary,
                        side:
                        const BorderSide(
                          color:
                          AppColors.primary,
                          width: 1.4,
                        ),
                        shape:
                        RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius
                              .circular(
                            14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
      Color color,
      String text,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius:
        BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 5),

          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallInfo({
    required IconData icon,
    required String text,
    required Color iconColor,
  }) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: iconColor,
        ),

        const SizedBox(width: 5),

        Text(
          text,
          style:
          const TextStyle(
            color:
            AppColors.textSecondary,
            fontSize: 12,
            fontWeight:
            FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding:
      const EdgeInsets.all(
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color:
        color.withOpacity(0.07),
        borderRadius:
        BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration:
            BoxDecoration(
              color:
              color.withOpacity(0.12),
              borderRadius:
              BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: color,
            ),
          ),

          const SizedBox(
            width: AppSpacing.sm,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style:
                  const TextStyle(
                    color: AppColors
                        .textPrimary,
                    fontSize: 12,
                    fontWeight:
                    FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  label,
                  style:
                  const TextStyle(
                    color: AppColors
                        .textSecondary,
                    fontSize: 10,
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