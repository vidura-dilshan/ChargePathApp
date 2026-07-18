import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'favorites_db.dart';
import 'chargingroute.dart';

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
  // COLORS
  static const Color _primaryColor = Color(0xFF0253A4);
  static const Color _lightFillColor = Color(0xFFE6EFF8);

  // Favourites loaded from SQLite
  List<Map<String, dynamic>> _favorites = [];
  bool _isLoadingFavs = true;

  // ── RESOLVE DISPLAY NAME FROM FIREBASE AUTH ──────────────────────────────
  String get _displayName {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim();
    }

    final email = user?.email ?? '';

    if (email.isNotEmpty) {
      final prefix = email.split('@').first;
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
    final rows = await FavoritesDb.instance.getAllFavorites();
    if (!mounted) return;
    setState(() {
      _favorites = rows;
      _isLoadingFavs = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadFavorites();
  }

  // ── REMOVE WITH CONFIRMATION ─────────────────────────────────────────────
  Future<void> _confirmRemove(String stationId, String stationName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Remove Favourite',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Remove "$stationName" from your favourites?',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
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
      ),
    );
    if (confirmed == true) {
      await FavoritesDb.instance.removeFavorite(stationId);
    }
  }

  // ── NAVIGATE TO CHARGING ROUTE ───────────────────────────────────────────
  void _openRoute(Map<String, dynamic> fav) {
    final double? lat = double.tryParse(fav['latitude']?.toString() ?? '');
    final double? lng = double.tryParse(fav['longitude']?.toString() ?? '');
    final String name = fav['station_name']?.toString() ?? 'Charging Station';

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Location data unavailable for this station.'),
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
        builder: (_) => ChargingRoute(
          destination: LatLng(lat, lng),
          destinationName: name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. BACKGROUND HEADER WITH WAVE
          ClipPath(
            clipper: BottomWaveClipper(),
            child: Image.asset(
              'lib/Assets/homeimage.jpeg',
              height: size.height * 0.38,
              width: double.infinity,
              fit: BoxFit.cover,
              color: const Color(0xFF012B55).withOpacity(0.6),
              colorBlendMode: BlendMode.darken,
            ),
          ),

          // 2. MAIN CONTENT
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── TOP BAR (WITH DIRECT USER GREETING) ────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Direct Welcome Greeting instead of App Name
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
                      _buildGlassIconBtn(Icons.notifications_outlined),
                    ],
                  ),
                ),

                // Pushes the white container section back down to its exact original location below the wave
                SizedBox(height: (size.height * 0.09) + 110),

                // ── FAVOURITE STATIONS SECTION ─────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── HEADER ─────────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.amber.shade200,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber.shade600,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Favourite Stations',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            if (!_isLoadingFavs && _favorites.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
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
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── CONTENT ────────────────────────────────────────────
                      Expanded(
                        child: _isLoadingFavs
                            ? const Center(
                          child: CircularProgressIndicator(
                            color: _primaryColor,
                          ),
                        )
                            : _favorites.isEmpty
                            ? _buildEmptyFavourites()
                            : RefreshIndicator(
                          onRefresh: _loadFavorites,
                          color: _primaryColor,
                          child: ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                                24, 0, 24, 100),
                            itemCount: _favorites.length,
                            itemBuilder: (context, index) {
                              final fav = _favorites[index];
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 16),
                                child: _buildFavouriteCard(fav),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFavourites() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 110),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
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
                          'Tap the ⭐ star on any charging station in "Find Stations" to save it here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        GestureDetector(
                          onTap: widget.onNavigateToStations, // ← triggers tab switch
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: _lightFillColor,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.ev_station_rounded,
                                    color: _primaryColor, size: 20),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── FAVOURITE STATION CARD ───────────────────────────────────────────────
  Widget _buildFavouriteCard(Map<String, dynamic> fav) {
    final String name =
        fav['station_name']?.toString() ?? 'Unknown Station';
    final String address =
        fav['address']?.toString() ?? 'Address not available';
    final String power = fav['charging_power']?.toString() ?? '0';
    final int availablePlugs =
        int.tryParse(fav['available_plugs']?.toString() ?? '0') ?? 0;
    final int totalSlots =
        int.tryParse(fav['connector_slots']?.toString() ?? '0') ?? 0;
    final bool isAvailable = availablePlugs > 0;
    final String rawConnectors =
        fav['supported_connector_types']?.toString() ?? '';
    final List<String> connectors = rawConnectors
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .take(3)
        .toList();
    final Color statusColor = isAvailable ? Colors.green : Colors.red;
    final String stationId = fav['station_id'] as String;
    final double? lat = double.tryParse(fav['latitude']?.toString() ?? '');
    final double? lng = double.tryParse(fav['longitude']?.toString() ?? '');
    final bool hasLocation = lat != null && lng != null;

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
          // ── CARD HEADER ──────────────────────────────────────────────
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
                      name,
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

              // ── DELETE BUTTON ────────────────────────────────────────
              GestureDetector(
                onTap: () => _confirmRemove(stationId, name),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red.shade500,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF3F3F3)),
          const SizedBox(height: 14),

          // ── STATS ROW ────────────────────────────────────────────────
          Row(
            children: [
              _buildInfoChip(
                icon: Icons.flash_on_rounded,
                label: '$power kW',
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
                      isAvailable ? 'Available' : 'Unavailable',
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

          // ── CONNECTOR CHIPS ──────────────────────────────────────────
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

          const SizedBox(height: 16),

          // ── GET ROUTE BUTTON ─────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: hasLocation ? () => _openRoute(fav) : null,
              icon: Icon(
                Icons.directions_rounded,
                size: 18,
                color: hasLocation ? _primaryColor : Colors.grey.shade400,
              ),
              label: Text(
                hasLocation ? 'Get Route' : 'Location Unavailable',
                style: TextStyle(
                  color: hasLocation ? _primaryColor : Colors.grey.shade400,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color:
                  hasLocation ? _primaryColor : Colors.grey.shade300,
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
        Icon(icon, size: 14, color: iconColor),
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

  // ── GLASS ICON BUTTON ────────────────────────────────────────────────────
  Widget _buildGlassIconBtn(IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

// ── WAVE CLIPPER ──────────────────────────────────────────────────────────────
class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 50);

    final firstControlPoint = Offset(size.width / 4, size.height);
    final firstEndPoint = Offset(size.width / 2.25, size.height - 30);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    final secondControlPoint = Offset(
      size.width - (size.width / 3.25),
      size.height - 80,
    );
    final secondEndPoint = Offset(size.width, size.height - 40);
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
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}