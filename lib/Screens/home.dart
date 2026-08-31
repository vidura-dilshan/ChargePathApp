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

  // ---------------------------------------------------------------------------
  // DISPLAY NAME
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // LIFE CYCLE
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // LOAD FAVOURITES
  // ---------------------------------------------------------------------------

  Future<void> _loadFavorites() async {
    // Avoid showing the spinner on subsequent refreshes to prevent
    // the UI from flashing between states.
    final bool showSpinner = _favorites.isEmpty;

    if (showSpinner && mounted) {
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
          _isLoadingFavs = false;
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
        _isLoadingFavs = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load favourites: $error');
      debugPrintStack(
        stackTrace: stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _favorites = [];
        _isLoadingFavs = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // REMOVE FAVOURITE
  // ---------------------------------------------------------------------------

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
                Navigator.pop(
                  dialogContext,
                  false,
                );
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
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Remove',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await FavoritesDb.instance.removeFavorite(
        stationId,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // OPEN ROUTE
  // ---------------------------------------------------------------------------

  void _openRoute(
      Map<String, dynamic> favourite,
      ) {
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

  // ---------------------------------------------------------------------------
  // RESPONSIVE BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return _buildMobileLayout();
  }

  // ===========================================================================
  // MOBILE
  // ===========================================================================

  Widget _buildMobileLayout() {
    final bool isLandscape =
        MediaQuery.orientationOf(context) ==
            Orientation.landscape;

    /*
     * Portrait keeps the original large hero.
     *
     * Landscape uses a smaller hero because the screen has
     * much less vertical space.
     */
    final double heroHeight =
    isLandscape ? 165 : 225;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ---------------------------------------------------------------
            // HERO (PINNED)
            // ---------------------------------------------------------------

            _buildHeroSection(
              compact: true,
              mobileHeight: heroHeight,
              mobileLandscape: isLandscape,
            ),

            SizedBox(
              height: isLandscape
                  ? AppSpacing.md
                  : AppSpacing.xxl,
            ),

            // ---------------------------------------------------------------
            // FAVOURITES HEADER (PINNED)
            // ---------------------------------------------------------------

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
              ),
              child: AppSectionHeader(
                icon: Icons.star_rounded,
                title: 'Favourite Stations',
                subtitle: 'Your saved charging locations',
                trailing:
                !_isLoadingFavs &&
                    _favorites.isNotEmpty
                    ? _buildCountBadge()
                    : null,
              ),
            ),

            SizedBox(
              height: isLandscape
                  ? AppSpacing.md
                  : AppSpacing.lg,
            ),

            // ---------------------------------------------------------------
            // SCROLLABLE CARDS AREA
            // ---------------------------------------------------------------

            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadFavorites,
                color: AppColors.primary,
                child: CustomScrollView(
                  cacheExtent: 500,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  slivers: [
                    // ---------------------------------------------------------------
                    // LOADING
                    // ---------------------------------------------------------------

                    if (_isLoadingFavs)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 50,
                          ),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      )

                    // ---------------------------------------------------------------
                    // EMPTY FAVOURITES
                    // ---------------------------------------------------------------

                    else if (_favorites.isEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          isLandscape ? 80 : 120,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _buildMobileEmptyFavourites(
                            compact: isLandscape,
                          ),
                        ),
                      )

                    // ---------------------------------------------------------------
                    // FAVOURITE CARDS
                    // ---------------------------------------------------------------

                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          isLandscape ? 80 : 120,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              return RepaintBoundary(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom:
                                    index ==
                                        _favorites.length - 1
                                        ? 0
                                        : AppSpacing.lg,
                                  ),
                                  child: _buildFavouriteCard(
                                    _favorites[index],
                                  ),
                                ),
                              );
                            },
                            childCount: _favorites.length,
                            addAutomaticKeepAlives: true,
                            addRepaintBoundaries: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TABLET
  // ===========================================================================

  Widget _buildTabletLayout() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            // Hero section.
            Expanded(
              flex: 3,
              child: _buildHeroSection(
                compact: false,
              ),
            ),

            const SizedBox(
              width: AppSpacing.lg,
            ),

            // Favourite stations.
            Expanded(
              flex: 7,
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

  // ===========================================================================
  // HERO SECTION
  // ===========================================================================

  Widget _buildHeroSection({
    required bool compact,
    double? mobileHeight,
    bool mobileLandscape = false,
  }) {
    /*
     * Landscape mobile values are deliberately smaller to ensure
     * everything comfortably fits inside the hero.
     */

    final double heroPadding;

    if (mobileLandscape) {
      heroPadding = 12;
    } else if (compact) {
      heroPadding = 18;
    } else {
      heroPadding = 28;
    }

    final double welcomeFontSize =
    mobileLandscape
        ? 11
        : compact
        ? 14
        : 18;

    final double nameFontSize =
    mobileLandscape
        ? 22
        : compact
        ? 28
        : 38;

    final double descriptionFontSize =
    mobileLandscape
        ? 11
        : compact
        ? 13
        : 15;

    final bool useWave = compact && !mobileLandscape;

    final Widget heroContent = SizedBox(
      height: compact
          ? (mobileHeight ?? 285)
          : double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
            // ---------------------------------------------------------------
            // BACKGROUND IMAGE
            // ---------------------------------------------------------------

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

            // ---------------------------------------------------------------
            // BLUE OVERLAY
            // ---------------------------------------------------------------

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF012B55)
                        .withOpacity(0.92),
                    AppColors.primary
                        .withOpacity(0.70),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            // ---------------------------------------------------------------
            // HERO CONTENT
            // ---------------------------------------------------------------

            Padding(
              padding: EdgeInsets.all(
                heroPadding,
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  if (!useWave)
                    Align(
                      alignment: Alignment.topRight,
                      child: _buildGlassIconButton(
                        Icons.notifications_outlined,
                        compact: compact,
                        extraCompact: mobileLandscape,
                      ),
                    ),

                  if (!useWave) const Spacer(),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ---------------------------------------------------------
                            // WELCOME TEXT
                            // ---------------------------------------------------------
          
                            Text(
                              'Welcome back,',
                              style: TextStyle(
                                color: Colors.white
                                    .withOpacity(0.82),
                                fontSize: welcomeFontSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
          
                            SizedBox(
                              height: mobileLandscape
                                  ? 2
                                  : compact
                                  ? 5
                                  : 8,
                            ),
          
                            // ---------------------------------------------------------
                            // USER NAME
                            // ---------------------------------------------------------
          
                            Text(
                              _displayName,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: nameFontSize,
                                height: 1.1,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines:
                              compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
          
                            SizedBox(
                              height: mobileLandscape
                                  ? 3
                                  : compact
                                  ? 7
                                  : 12,
                            ),
          
                            // ---------------------------------------------------------
                            // DESCRIPTION
                            // ---------------------------------------------------------
          
                            Text(
                              'Find charging stations, plan your journey, '
                                  'and continue driving with confidence.',
                              style: TextStyle(
                                color: Colors.white
                                    .withOpacity(0.82),
                                fontSize:
                                descriptionFontSize,
                                height:
                                mobileLandscape
                                    ? 1.2
                                    : 1.45,
                              ),
                              maxLines:
                              mobileLandscape
                                  ? 1
                                  : compact
                                  ? 2
                                  : 3,
                              overflow:
                              TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (useWave)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: _buildGlassIconButton(
                            Icons.notifications_outlined,
                            compact: compact,
                            extraCompact: mobileLandscape,
                          ),
                        ),
                    ],
                  ),

                  SizedBox(
                    height: mobileLandscape
                        ? 4
                        : compact
                        ? 8
                        : 12,
                  ),

                  if (useWave) const Spacer(),

                ],
              ),
            ),
          ],
        ),
      );

    return useWave
        ? ClipPath(
            clipper: BottomWaveClipper(),
            child: heroContent,
          )
        : ClipRRect(
            borderRadius: BorderRadius.zero,
            child: heroContent,
          );
  }

  // ===========================================================================
  // TABLET FAVOURITES SECTION
  // ===========================================================================

  Widget _buildFavouriteSection({
    required bool useGrid,
    required double bottomPadding,
  }) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          icon: Icons.star_rounded,
          title: 'Favourite Stations',
          subtitle: 'Your saved charging locations',
          trailing:
          !_isLoadingFavs &&
              _favorites.isNotEmpty
              ? _buildCountBadge()
              : null,
        ),

        const SizedBox(
          height: AppSpacing.lg,
        ),

        Expanded(
          child: _buildFavouriteContent(
            useGrid: useGrid,
            bottomPadding: bottomPadding,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COUNT BADGE
  // ---------------------------------------------------------------------------

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

  // ===========================================================================
  // TABLET FAVOURITE CONTENT
  // ===========================================================================

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
          physics:
          const AlwaysScrollableScrollPhysics(
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
        constraints.maxWidth >= 850
            ? 2
            : 1;

        return RefreshIndicator(
          onRefresh: _loadFavorites,
          color: AppColors.primary,
          child: GridView.builder(
            physics:
            const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: bottomPadding,
            ),
            itemCount: _favorites.length,
            gridDelegate:
            SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columnCount,
              crossAxisSpacing:
              AppSpacing.lg,
              mainAxisSpacing:
              AppSpacing.lg,
              mainAxisExtent: 335,
            ),
            itemBuilder: (
                context,
                index,
                ) {
              return _buildFavouriteCard(
                _favorites[index],
              );
            },
          ),
        );
      },
    );
  }

  // ===========================================================================
  // MOBILE EMPTY FAVOURITES
  // ===========================================================================

  Widget _buildMobileEmptyFavourites({
    required bool compact,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 620,
        ),
        child: AppCard(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 20 : 24,
            vertical: compact ? 18 : 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 54 : 72,
                height: compact ? 54 : 72,
                decoration:
                const BoxDecoration(
                  color: AppColors.lightFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.star_outline_rounded,
                  size: compact ? 28 : 36,
                  color: AppColors.primary,
                ),
              ),

              SizedBox(
                height: compact
                    ? AppSpacing.md
                    : AppSpacing.xl,
              ),

              Text(
                'No Favourites Yet',
                style: TextStyle(
                  fontSize:
                  compact ? 16 : 18,
                  fontWeight:
                  FontWeight.bold,
                  color:
                  AppColors.textPrimary,
                ),
              ),

              SizedBox(
                height: compact
                    ? 4
                    : AppSpacing.sm,
              ),

              Text(
                'Save charging stations you use frequently '
                    'and they will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                  AppColors.textSecondary,
                  fontSize:
                  compact ? 11 : 13,
                  height: 1.5,
                ),
              ),

              SizedBox(
                height: compact
                    ? AppSpacing.lg
                    : AppSpacing.xl,
              ),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    widget.onNavigateToStations?.call();
                  },
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text(
                    'Find stations',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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

  // ===========================================================================
  // TABLET EMPTY STATE
  // ===========================================================================

  Widget _buildEmptyFavourites({
    required double bottomPadding,
  }) {
    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        return SingleChildScrollView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
              constraints.maxHeight,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: bottomPadding,
              ),
              child: Align(
                alignment:
                Alignment.topCenter,
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(
                    maxWidth: 620,
                  ),
                  child: AppCard(
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
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
                                .star_outline_rounded,
                            size: 36,
                            color:
                            AppColors.primary,
                          ),
                        ),

                        const SizedBox(
                          height:
                          AppSpacing.xl,
                        ),

                        const Text(
                          'No Favourites Yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight:
                            FontWeight.bold,
                            color: AppColors
                                .textPrimary,
                          ),
                        ),

                        const SizedBox(
                          height:
                          AppSpacing.sm,
                        ),

                        const Text(
                          'Save charging stations you use frequently '
                              'and they will appear here.',
                          textAlign:
                          TextAlign.center,
                          style: TextStyle(
                            color: AppColors
                                .textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(
                          height:
                          AppSpacing.xl,
                        ),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              widget.onNavigateToStations?.call();
                            },
                            icon: const Icon(Icons.search_rounded, size: 18),
                            label: const Text(
                              'Find stations',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
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

  // ===========================================================================
  // FAVOURITE CARD
  // ===========================================================================

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
        favourite['charging_power']?.toString() ??
            '0';

    final int availablePlugs =
        int.tryParse(
          favourite['available_plugs']
              ?.toString() ??
              '0',
        ) ??
            0;

    final int totalSlots =
        int.tryParse(
          favourite['connector_slots']
              ?.toString() ??
              '0',
        ) ??
            0;

    final bool isAvailable =
        availablePlugs > 0;

    final String rawConnectors =
        favourite['supported_connector_types']
            ?.toString() ??
            '';

    final List<String> connectors =
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
        .take(3)
        .toList();

    final Color statusColor =
    isAvailable
        ? AppColors.success
        : AppColors.danger;

    final String stationId =
        favourite['station_id']?.toString() ??
            '';

    final double? latitude =
    double.tryParse(
      favourite['latitude']?.toString() ??
          '',
    );

    final double? longitude =
    double.tryParse(
      favourite['longitude']?.toString() ??
          '',
    );

    final bool hasLocation =
        latitude != null &&
            longitude != null;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          // -----------------------------------------------------------------
          // STATION HEADER
          // -----------------------------------------------------------------

          Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color:
                  AppColors.lightFill,
                  borderRadius:
                  BorderRadius.circular(
                    14,
                  ),
                ),
                child: const Icon(
                  Icons.ev_station_rounded,
                  color: AppColors.primary,
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
                      stationName,
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
                            maxLines: 1,
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

              Material(
                color:
                const Color(0xFFFFEEEE),
                shape:
                const CircleBorder(),
                child: InkWell(
                  onTap: () {
                    _confirmRemove(
                      stationId,
                      stationName,
                    );
                  },
                  customBorder:
                  const CircleBorder(),
                  child: const Padding(
                    padding:
                    EdgeInsets.all(
                      9,
                    ),
                    child: Icon(
                      Icons
                          .delete_outline_rounded,
                      color:
                      AppColors.danger,
                      size: 19,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: AppSpacing.lg,
          ),

          const Divider(
            height: 1,
            color: Color(0xFFF0F1F3),
          ),

          const SizedBox(
            height: AppSpacing.lg,
          ),

          // -----------------------------------------------------------------
          // POWER / PLUGS / STATUS
          // -----------------------------------------------------------------

          Row(
            children: [
              Expanded(
                child: _buildInfoItem(
                  icon:
                  Icons.flash_on_rounded,
                  value:
                  '$chargingPower kW',
                  label: 'Power',
                  iconColor:
                  AppColors.warning,
                ),
              ),

              const SizedBox(
                width: AppSpacing.sm,
              ),

              Expanded(
                child: _buildInfoItem(
                  icon:
                  Icons.power_rounded,
                  value:
                  '$availablePlugs/$totalSlots',
                  label: 'Plugs',
                  iconColor:
                  statusColor,
                ),
              ),

              const SizedBox(
                width: AppSpacing.sm,
              ),

              _buildStatusBadge(
                available:
                isAvailable,
                color: statusColor,
              ),
            ],
          ),

          // -----------------------------------------------------------------
          // CONNECTORS
          // -----------------------------------------------------------------

          if (connectors.isNotEmpty) ...[
            const SizedBox(
              height: AppSpacing.lg,
            ),

            Wrap(
              spacing: AppSpacing.sm,
              runSpacing:
              AppSpacing.sm,
              children: connectors
                  .map(
                      (connector) {
                    return Container(
                      padding:
                      const EdgeInsets
                          .symmetric(
                        horizontal: 10,
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
                          FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ],

          const SizedBox(
            height: AppSpacing.xl,
          ),

          // -----------------------------------------------------------------
          // ROUTE BUTTON
          // -----------------------------------------------------------------

          SizedBox(
            width: double.infinity,
            height: 46,
            child:
            OutlinedButton.icon(
              onPressed:
              hasLocation
                  ? () {
                _openRoute(
                  favourite,
                );
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
                style:
                const TextStyle(
                  fontWeight:
                  FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style:
              OutlinedButton.styleFrom(
                foregroundColor:
                AppColors.primary,
                disabledForegroundColor:
                AppColors
                    .textSecondary,
                side: BorderSide(
                  color: hasLocation
                      ? AppColors.primary
                      : const Color(
                    0xFFD1D5DB,
                  ),
                  width: 1.4,
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // INFO ITEM
  // ===========================================================================

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
            color:
            iconColor.withOpacity(
              0.10,
            ),
            borderRadius:
            BorderRadius.circular(
              10,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: iconColor,
          ),
        ),

        const SizedBox(
          width: 7,
        ),

        Flexible(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style:
                const TextStyle(
                  color:
                  AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight:
                  FontWeight.w700,
                ),
                maxLines: 1,
                overflow:
                TextOverflow.ellipsis,
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
    );
  }

  // ===========================================================================
  // STATUS BADGE
  // ===========================================================================

  Widget _buildStatusBadge({
    required bool available,
    required Color color,
  }) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(
          0.10,
        ),
        borderRadius:
        BorderRadius.circular(
          20,
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape:
              BoxShape.circle,
            ),
          ),

          const SizedBox(
            width: 5,
          ),

          Text(
            available
                ? 'Available'
                : 'Full',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // GLASS NOTIFICATION BUTTON
  // ===========================================================================

  Widget _buildGlassIconButton(
      IconData icon, {
        required bool compact,
        bool extraCompact = false,
      }) {
    final double padding;

    if (extraCompact) {
      padding = 7;
    } else if (compact) {
      padding = 10;
    } else {
      padding = 12;
    }

    final double iconSize;

    if (extraCompact) {
      iconSize = 18;
    } else if (compact) {
      iconSize = 21;
    } else {
      iconSize = 24;
    }

    return ClipRRect(
      borderRadius:
      BorderRadius.circular(
        14,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10,
          sigmaY: 10,
        ),
        child: Container(
          padding: EdgeInsets.all(
            padding,
          ),
          decoration: BoxDecoration(
            color:
            Colors.white.withOpacity(
              0.15,
            ),
            border: Border.all(
              color:
              Colors.white.withOpacity(
                0.20,
              ),
            ),
            borderRadius:
            BorderRadius.circular(
              14,
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    
    path.lineTo(0, size.height - 10);

    path.quadraticBezierTo(
      size.width * 0.25, size.height,
      size.width * 0.5, size.height - 25,
    );

    path.quadraticBezierTo(
      size.width * 0.75, size.height - 50,
      size.width, size.height - 40,
    );

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}