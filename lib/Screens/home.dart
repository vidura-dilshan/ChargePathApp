import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'chargingroute.dart';
import 'favorites_db.dart';

class HomePage extends StatefulWidget {
  final VoidCallback? onNavigateToStations;

  const HomePage({
    super.key,
    this.onNavigateToStations,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _primaryColor = Color(0xFF0253A4);
  static const Color _lightFillColor = Color(0xFFE6EFF8);

  List<Map<String, dynamic>> _favorites = [];
  bool _isLoadingFavs = true;

  String get _displayName {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user?.displayName != null &&
        user!.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim();
    }

    final String email = user?.email ?? '';

    if (email.isNotEmpty) {
      final String prefix = email.split('@').first;

      return prefix
          .split(RegExp(r'[._\-]'))
          .map(
            (word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '',
      )
          .join(' ')
          .trim();
    }

    return 'User';
  }

  @override
  void initState() {
    super.initState();

    _loadFavorites();
    FavoritesDb.favoritesChanged.addListener(_onFavoritesChanged);
  }

  @override
  void dispose() {
    FavoritesDb.favoritesChanged.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    if (mounted) {
      setState(() {
        _isLoadingFavs = true;
      });
    }

    try {
      // SQLite is not currently being used on Flutter Web.
      // This allows the responsive layout to be tested in Chrome.
      if (kIsWeb) {
        if (!mounted) {
          return;
        }

        setState(() {
          _favorites = [];
        });

        return;
      }

      final List<Map<String, dynamic>> rows =
      await FavoritesDb.instance.getAllFavorites();

      if (!mounted) {
        return;
      }

      setState(() {
        _favorites = rows;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load favourites: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      setState(() {
        _favorites = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFavs = false;
        });
      }
    }
  }

  Future<void> _confirmRemove(
      String stationId,
      String stationName,
      ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Remove Favourite',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Remove "$stationName" from your favourites?',
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await FavoritesDb.instance.removeFavorite(stationId);
    }
  }

  void _openRoute(Map<String, dynamic> favourite) {
    final double? latitude = double.tryParse(
      favourite['latitude']?.toString() ?? '',
    );

    final double? longitude = double.tryParse(
      favourite['longitude']?.toString() ?? '',
    );

    final String stationName =
        favourite['station_name']?.toString() ??
            'Charging Station';

    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Location data unavailable for this station.',
          ),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return ChargingRoute(
            destination: LatLng(latitude, longitude),
            destinationName: stationName,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useTabletLayout =
            constraints.maxWidth >= 700;

        if (useTabletLayout) {
          return _buildTabletLayout();
        }

        return _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    final Size screenSize = MediaQuery.of(context).size;

    final double headerHeight = screenSize.height * 0.38;

    final double contentSpacerHeight =
    (headerHeight - 72).clamp(175.0, 245.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          ClipPath(
            clipper: BottomWaveClipper(),
            child: Image.asset(
              'lib/Assets/homeimage.jpeg',
              height: headerHeight,
              width: double.infinity,
              fit: BoxFit.cover,
              color: const Color(0xFF012B55).withOpacity(0.6),
              colorBlendMode: BlendMode.darken,
              errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stackTrace,
                  ) {
                return Container(
                  height: headerHeight,
                  width: double.infinity,
                  color: _primaryColor,
                );
              },
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMobileHeader(),

                SizedBox(
                  height: contentSpacerHeight,
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildFavouriteSection(
                      useGrid: false,
                      horizontalPadding: 24,
                      bottomPadding: 100,
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

  Widget _buildTabletLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: _buildTabletHeroSection(),
            ),
            Expanded(
              flex: 6,
              child: Container(
                color: const Color(0xFFF4F7FB),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    28,
                    24,
                    28,
                    20,
                  ),
                  child: _buildFavouriteSection(
                    useGrid: true,
                    horizontalPadding: 0,
                    bottomPadding: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        24,
        10,
        24,
        12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _displayName,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _buildGlassIconButton(
            Icons.notifications_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildTabletHeroSection() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'lib/Assets/homeimage.jpeg',
          fit: BoxFit.cover,
          errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stackTrace,
              ) {
            return Container(
              color: _primaryColor,
            );
          },
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF012B55).withOpacity(0.88),
                const Color(0xFF0253A4).withOpacity(0.70),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: _buildGlassIconButton(
                  Icons.notifications_outlined,
                ),
              ),
              const Spacer(),
              Text(
                'Welcome back,',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1.1,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 18),
              Text(
                'Find charging stations, plan your journey, '
                    'and continue driving with confidence.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: widget.onNavigateToStations,
                  icon: const Icon(
                    Icons.ev_station_rounded,
                    size: 22,
                  ),
                  label: const Text(
                    'Find Charging Stations',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _primaryColor,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFavouriteSection({
    required bool useGrid,
    required double horizontalPadding,
    required double bottomPadding,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
          ),
          child: _buildFavouriteHeader(),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _buildFavouriteContent(
            useGrid: useGrid,
            horizontalPadding: horizontalPadding,
            bottomPadding: bottomPadding,
          ),
        ),
      ],
    );
  }

  Widget _buildFavouriteHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: Colors.amber.shade200,
            ),
          ),
          child: Icon(
            Icons.star_rounded,
            color: Colors.amber.shade600,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Favourite Stations',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        if (!_isLoadingFavs && _favorites.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: _lightFillColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_favorites.length}',
              style: const TextStyle(
                color: _primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFavouriteContent({
    required bool useGrid,
    required double horizontalPadding,
    required double bottomPadding,
  }) {
    if (_isLoadingFavs) {
      return const Center(
        child: CircularProgressIndicator(
          color: _primaryColor,
        ),
      );
    }

    if (_favorites.isEmpty) {
      return _buildEmptyFavourites(
        horizontalPadding: horizontalPadding,
        bottomPadding: bottomPadding,
      );
    }

    if (!useGrid) {
      return RefreshIndicator(
        onRefresh: _loadFavorites,
        color: _primaryColor,
        child: ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            bottomPadding,
          ),
          itemCount: _favorites.length,
          itemBuilder: (context, index) {
            final Map<String, dynamic> favourite =
            _favorites[index];

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildFavouriteCard(favourite),
            );
          },
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final int columnCount =
        constraints.maxWidth >= 850 ? 2 : 1;

        return RefreshIndicator(
          onRefresh: _loadFavorites,
          color: _primaryColor,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: bottomPadding,
            ),
            itemCount: _favorites.length,
            gridDelegate:
            SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columnCount,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
              mainAxisExtent: 360,
            ),
            itemBuilder: (context, index) {
              return _buildFavouriteCard(
                _favorites[index],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyFavourites({
    required double horizontalPadding,
    required double bottomPadding,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                6,
                horizontalPadding,
                bottomPadding,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 600,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryColor.withOpacity(0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.amber.shade200,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.star_outline_rounded,
                            size: 42,
                            color: Colors.amber.shade500,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'No Favourites Yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the star on any charging station in '
                              '"Find Stations" to save it here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Material(
                          color: _lightFillColor,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: widget.onNavigateToStations,
                            borderRadius: BorderRadius.circular(16),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.ev_station_rounded,
                                    color: _primaryColor,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Go to Find Stations',
                                    style: TextStyle(
                                      color: _primaryColor,
                                      fontWeight: FontWeight.w600,
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
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavouriteCard(
      Map<String, dynamic> favourite,
      ) {
    final String stationName =
        favourite['station_name']?.toString() ??
            'Unknown Station';

    final String address =
        favourite['address']?.toString() ??
            'Address not available';

    final String chargingPower =
        favourite['charging_power']?.toString() ?? '0';

    final int availablePlugs = int.tryParse(
      favourite['available_plugs']?.toString() ?? '0',
    ) ??
        0;

    final int totalSlots = int.tryParse(
      favourite['connector_slots']?.toString() ?? '0',
    ) ??
        0;

    final bool isAvailable = availablePlugs > 0;

    final String rawConnectors =
        favourite['supported_connector_types']?.toString() ??
            '';

    final List<String> connectors = rawConnectors
        .split(',')
        .map((connector) => connector.trim())
        .where((connector) => connector.isNotEmpty)
        .take(3)
        .toList();

    final Color statusColor =
    isAvailable ? Colors.green : Colors.red;

    final String stationId =
        favourite['station_id']?.toString() ?? '';

    final double? latitude = double.tryParse(
      favourite['latitude']?.toString() ?? '',
    );

    final double? longitude = double.tryParse(
      favourite['longitude']?.toString() ?? '',
    );

    final bool hasLocation =
        latitude != null && longitude != null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _lightFillColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.ev_station_rounded,
                  color: _primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stationName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            address,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.red.shade50,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () {
                    _confirmRemove(
                      stationId,
                      stationName,
                    );
                  },
                  customBorder: const CircleBorder(),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.red.shade200,
                      ),
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red.shade500,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(
            height: 1,
            color: Color(0xFFF3F3F3),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildInfoChip(
                icon: Icons.flash_on_rounded,
                label: '$chargingPower kW',
                iconColor: Colors.orange.shade600,
              ),
              const SizedBox(width: 10),
              _buildInfoChip(
                icon: Icons.power_rounded,
                label: '$availablePlugs/$totalSlots plugs',
                iconColor: statusColor,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isAvailable
                          ? 'Available'
                          : 'Unavailable',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (connectors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: connectors.map((connector) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _lightFillColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    connector,
                    style: const TextStyle(
                      color: _primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: hasLocation
                  ? () {
                _openRoute(favourite);
              }
                  : null,
              icon: Icon(
                Icons.directions_rounded,
                size: 18,
                color: hasLocation
                    ? _primaryColor
                    : Colors.grey.shade400,
              ),
              label: Text(
                hasLocation
                    ? 'Get Route'
                    : 'Location Unavailable',
                style: TextStyle(
                  color: hasLocation
                      ? _primaryColor
                      : Colors.grey.shade400,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: hasLocation
                      ? _primaryColor
                      : Colors.grey.shade300,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color iconColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: iconColor,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassIconButton(IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10,
          sigmaY: 10,
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final Path path = Path();

    path.lineTo(0, size.height - 50);

    final Offset firstControlPoint = Offset(
      size.width / 4,
      size.height,
    );

    final Offset firstEndPoint = Offset(
      size.width / 2.25,
      size.height - 30,
    );

    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    final Offset secondControlPoint = Offset(
      size.width - (size.width / 3.25),
      size.height - 80,
    );

    final Offset secondEndPoint = Offset(
      size.width,
      size.height - 40,
    );

    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );

    path.lineTo(size.width, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(
      CustomClipper<Path> oldClipper,
      ) {
    return false;
  }
}