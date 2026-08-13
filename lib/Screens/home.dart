import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:chargepath/Theme/app_colors.dart';
import 'package:chargepath/Theme/app_spacing.dart';
import 'package:chargepath/Widgets/app_card.dart';
import 'package:chargepath/Widgets/app_section_header.dart';

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
      // SQLite is currently not used on Flutter Web.
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
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
          backgroundColor: AppColors.danger,
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
            destination: LatLng(
              latitude,
              longitude,
            ),
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
            // Full-width square hero.
            _buildHeroSection(
              compact: true,
            ),

            const SizedBox(height: AppSpacing.xxl),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                child: _buildFavouriteSection(
                  useGrid: false,
                  bottomPadding: 110,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLET
  // ---------------------------------------------------------------------------

  Widget _buildTabletLayout() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            // Hero sits flush with the navigation rail
            // and fills the full available height.
            Expanded(
              flex: 4,
              child: _buildHeroSection(
                compact: false,
              ),
            ),

            const SizedBox(width: AppSpacing.lg),

            // Only the favourites panel gets outer padding.
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  AppSpacing.xxl,
                  AppSpacing.xxl,
                  AppSpacing.xxl,
                ),
                child: _buildFavouriteSection(
                  useGrid: true,
                  bottomPadding: AppSpacing.xl,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED HERO
  // ---------------------------------------------------------------------------

  Widget _buildHeroSection({
    required bool compact,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: SizedBox(
        height: compact ? 285 : double.infinity,
        child: Stack(
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
                  color: AppColors.primary,
                );
              },
            ),

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF012B55).withOpacity(0.92),
                    AppColors.primary.withOpacity(0.70),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            Padding(
              padding: EdgeInsets.all(
                compact ? 22 : 34,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: _buildGlassIconButton(
                      Icons.notifications_outlined,
                      compact: compact,
                    ),
                  ),

                  const Spacer(),

                  Text(
                    'Welcome back,',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontSize: compact ? 14 : 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  SizedBox(
                    height: compact ? 5 : 8,
                  ),

                  Text(
                    _displayName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 28 : 38,
                      height: 1.1,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  SizedBox(
                    height: compact ? 10 : 18,
                  ),

                  Text(
                    'Find charging stations, plan your journey, '
                        'and continue driving with confidence.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontSize: compact ? 13 : 15,
                      height: 1.45,
                    ),
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),

                  SizedBox(
                    height: compact ? 18 : 28,
                  ),

                  SizedBox(
                    height: compact ? 48 : 54,
                    child: ElevatedButton.icon(
                      onPressed: widget.onNavigateToStations,
                      icon: Icon(
                        Icons.ev_station_rounded,
                        size: compact ? 19 : 22,
                      ),
                      label: Text(
                        compact
                            ? 'Find Stations'
                            : 'Find Charging Stations',
                        style: TextStyle(
                          fontSize: compact ? 13 : 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 18 : 24,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
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
  }

  // ---------------------------------------------------------------------------
  // FAVOURITES SECTION
  // ---------------------------------------------------------------------------

  Widget _buildFavouriteSection({
    required bool useGrid,
    required double bottomPadding,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          icon: Icons.star_rounded,
          title: 'Favourite Stations',
          subtitle: 'Your saved charging locations',
          trailing: !_isLoadingFavs && _favorites.isNotEmpty
              ? _buildCountBadge()
              : null,
        ),

        const SizedBox(height: AppSpacing.lg),

        Expanded(
          child: _buildFavouriteContent(
            useGrid: useGrid,
            bottomPadding: bottomPadding,
          ),
        ),
      ],
    );
  }

  Widget _buildCountBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.lightFill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${_favorites.length}',
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildFavouriteContent({
    required bool useGrid,
    required double bottomPadding,
  }) {
    if (_isLoadingFavs) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (_favorites.isEmpty) {
      return _buildEmptyFavourites(
        bottomPadding: bottomPadding,
      );
    }

    if (!useGrid) {
      return RefreshIndicator(
        onRefresh: _loadFavorites,
        color: AppColors.primary,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.only(
            bottom: bottomPadding,
          ),
          itemCount: _favorites.length,
          separatorBuilder: (_, __) {
            return const SizedBox(
              height: AppSpacing.lg,
            );
          },
          itemBuilder: (context, index) {
            return _buildFavouriteCard(
              _favorites[index],
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
          color: AppColors.primary,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: bottomPadding,
            ),
            itemCount: _favorites.length,
            gridDelegate:
            SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columnCount,
              crossAxisSpacing: AppSpacing.lg,
              mainAxisSpacing: AppSpacing.lg,
              mainAxisExtent: 335,
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

  // ---------------------------------------------------------------------------
  // EMPTY STATE
  // ---------------------------------------------------------------------------

  Widget _buildEmptyFavourites({
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
              padding: EdgeInsets.only(
                bottom: bottomPadding,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 620,
                  ),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: AppColors.lightFill,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.star_outline_rounded,
                            size: 36,
                            color: AppColors.primary,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.xl),

                        const Text(
                          'No Favourites Yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.sm),

                        const Text(
                          'Save charging stations you use frequently '
                              'and they will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.xl),

                        SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: widget.onNavigateToStations,
                            icon: const Icon(
                              Icons.ev_station_rounded,
                              size: 19,
                            ),
                            label: const Text(
                              'Find Stations',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                              AppColors.lightFill,
                              foregroundColor:
                              AppColors.primary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(14),
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

  // ---------------------------------------------------------------------------
  // FAVOURITE CARD
  // ---------------------------------------------------------------------------

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
        favourite['supported_connector_types']
            ?.toString() ??
            '';

    final List<String> connectors = rawConnectors
        .split(',')
        .map((connector) => connector.trim())
        .where((connector) => connector.isNotEmpty)
        .take(3)
        .toList();

    final Color statusColor = isAvailable
        ? AppColors.success
        : AppColors.danger;

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

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.lightFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.ev_station_rounded,
                  color: AppColors.primary,
                  size: 27,
                ),
              ),

              const SizedBox(width: AppSpacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stationName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),

                        const SizedBox(width: 4),

                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
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

              const SizedBox(width: AppSpacing.sm),

              Material(
                color: const Color(0xFFFFEEEE),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () {
                    _confirmRemove(
                      stationId,
                      stationName,
                    );
                  },
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                      size: 19,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          const Divider(
            height: 1,
            color: Color(0xFFF0F1F3),
          ),

          const SizedBox(height: AppSpacing.lg),

          Row(
            children: [
              Expanded(
                child: _buildInfoItem(
                  icon: Icons.flash_on_rounded,
                  value: '$chargingPower kW',
                  label: 'Power',
                  iconColor: AppColors.warning,
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              Expanded(
                child: _buildInfoItem(
                  icon: Icons.power_rounded,
                  value: '$availablePlugs/$totalSlots',
                  label: 'Plugs',
                  iconColor: statusColor,
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              _buildStatusBadge(
                available: isAvailable,
                color: statusColor,
              ),
            ],
          ),

          if (connectors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),

            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: connectors.map((connector) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.lightFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    connector,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: hasLocation
                  ? () {
                _openRoute(favourite);
              }
                  : null,
              icon: const Icon(
                Icons.directions_rounded,
                size: 18,
              ),
              label: Text(
                hasLocation
                    ? 'Get Route'
                    : 'Location Unavailable',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                disabledForegroundColor:
                AppColors.textSecondary,
                side: BorderSide(
                  color: hasLocation
                      ? AppColors.primary
                      : const Color(0xFFD1D5DB),
                  width: 1.4,
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

  Widget _buildInfoItem({
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: iconColor,
          ),
        ),

        const SizedBox(width: 7),

        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge({
    required bool available,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 5),

          Text(
            available ? 'Available' : 'Full',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GLASS BUTTON
  // ---------------------------------------------------------------------------

  Widget _buildGlassIconButton(
      IconData icon, {
        required bool compact,
      }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10,
          sigmaY: 10,
        ),
        child: Container(
          padding: EdgeInsets.all(
            compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            border: Border.all(
              color: Colors.white.withOpacity(0.20),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: compact ? 21 : 24,
          ),
        ),
      ),
    );
  }
}