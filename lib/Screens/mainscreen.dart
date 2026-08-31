import 'package:flutter/material.dart';

import 'package:chargepath/Screens/home.dart';
import 'package:chargepath/Screens/chargingstations.dart';
import 'package:chargepath/Screens/routeplanning.dart';
import 'package:chargepath/Screens/bookstation.dart';
import 'package:chargepath/Screens/profilepage.dart';

import 'package:chargepath/Theme/app_colors.dart';
import 'package:chargepath/Theme/app_spacing.dart';

import 'package:chargepath/Widgets/navigationbar.dart';
import 'package:chargepath/Widgets/responsive_layout.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
  });

  @override
  State<MainScreen> createState() =>
      _MainScreenState();
}

class _MainScreenState
    extends State<MainScreen> {
  int _selectedIndex = 0;

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  void _changePage(int index) {
    // Close the keyboard before changing pages.
    FocusManager.instance.primaryFocus
        ?.unfocus();

    if (_selectedIndex == index) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  void _openBookStation() {
    // Close keyboard before opening
    // the booking screen.
    FocusManager.instance.primaryFocus
        ?.unfocus();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
        const BookStation(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(
        onNavigateToStations: () {
          _changePage(1);
        },
      ),

      const FindStations(),

      const RoutePlanningPage(),

      const ProfilePage(),
    ];

    return ResponsiveLayout(
      mobile:
      _buildMobileLayout(pages),
      tablet:
      _buildTabletLayout(pages),
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE
  // ---------------------------------------------------------------------------

  Widget _buildMobileLayout(
      List<Widget> pages,
      ) {
    return Scaffold(
      backgroundColor:
      AppColors.background,

      // Keep the shell stable when the
      // keyboard opens inside child screens.
      resizeToAvoidBottomInset: false,

      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomNavBar(
              selectedIndex:
              _selectedIndex,
              onTabChange:
              _changePage,
              onCenterTap:
              _openBookStation,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLET / CAR
  // ---------------------------------------------------------------------------

  Widget _buildTabletLayout(
      List<Widget> pages,
      ) {
    return Scaffold(
      backgroundColor:
      AppColors.background,

      // Prevent the entire car/tablet UI
      // from shrinking when a keyboard opens.
      resizeToAvoidBottomInset: false,

      body: SafeArea(
        child: Row(
          children: [
            _buildTabletNavigation(),

            const VerticalDivider(
              width: 1,
              thickness: 1,
              color:
              Color(0xFFE5E7EB),
            ),

            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: pages,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLET NAVIGATION
  // ---------------------------------------------------------------------------

  Widget _buildTabletNavigation() {
    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final bool isShortHeight =
            constraints.maxHeight < 560;

        return Container(
          width:
          isShortHeight ? 96 : 112,
          decoration:
          const BoxDecoration(
            gradient:
            AppColors.primaryGradient,
          ),
          child: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: isShortHeight
                      ? AppSpacing.sm
                      : AppSpacing.md,
                ),

                _buildTabletLogo(
                  compact:
                  isShortHeight,
                ),

                SizedBox(
                  height: isShortHeight
                      ? AppSpacing.sm
                      : AppSpacing.md,
                ),

                Expanded(
                  child:
                  _buildNavigationRail(
                    compact:
                    isShortHeight,
                  ),
                ),

                _buildBookButton(
                  compact:
                  isShortHeight,
                ),

                SizedBox(
                  height: isShortHeight
                      ? AppSpacing.sm
                      : AppSpacing.md,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TABLET LOGO
  // ---------------------------------------------------------------------------

  Widget _buildTabletLogo({
    required bool compact,
  }) {
    return Column(
      children: [
        CircleAvatar(
          radius: compact ? 18 : 21,
          backgroundColor:
          AppColors.white,
          child: Icon(
            Icons
                .electric_car_rounded,
            color:
            AppColors.primary,
            size: compact ? 21 : 25,
          ),
        ),

        SizedBox(
          height: compact ? 4 : 6,
        ),

        Text(
          'ChargePath',
          style: TextStyle(
            color: Colors.white,
            fontSize:
            compact ? 9 : 11,
            fontWeight:
            FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION RAIL
  // ---------------------------------------------------------------------------

  Widget _buildNavigationRail({
    required bool compact,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // On short landscape screens, hide the labels.
        // This prevents the NavigationRail from overflowing vertically.
        final bool shortHeight =
            constraints.maxHeight < 300;

        return NavigationRail(
          selectedIndex: _selectedIndex,

          onDestinationSelected: _changePage,

          backgroundColor: Colors.transparent,

          /*
         * Important:
         * When the available rail height is small,
         * remove labels completely.
         */
          labelType: shortHeight
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,

          groupAlignment: 0,

          useIndicator: true,

          indicatorColor: Colors.white.withOpacity(
            0.18,
          ),

          minWidth: shortHeight
              ? 58
              : compact
              ? 64
              : 72,

          minExtendedWidth: shortHeight
              ? 58
              : compact
              ? 64
              : 72,

          selectedIconTheme: IconThemeData(
            color: Colors.white,
            size: shortHeight
                ? 20
                : compact
                ? 22
                : 26,
          ),

          unselectedIconTheme: IconThemeData(
            color: Colors.white.withOpacity(
              0.50,
            ),
            size: shortHeight
                ? 18
                : compact
                ? 20
                : 23,
          ),

          selectedLabelTextStyle: TextStyle(
            color: Colors.white,
            fontSize: compact ? 9 : 11,
            fontWeight: FontWeight.bold,
          ),

          unselectedLabelTextStyle: TextStyle(
            color: Colors.white.withOpacity(
              0.50,
            ),
            fontSize: compact ? 8 : 10,
          ),

          destinations: const [
            NavigationRailDestination(
              icon: Icon(
                Icons.home_rounded,
              ),
              selectedIcon: Icon(
                Icons.home_rounded,
              ),
              label: Text(
                'Home',
              ),
            ),

            NavigationRailDestination(
              icon: Icon(
                Icons.ev_station_rounded,
              ),
              selectedIcon: Icon(
                Icons.ev_station_rounded,
              ),
              label: Text(
                'Stations',
              ),
            ),

            NavigationRailDestination(
              icon: Icon(
                Icons.location_on_rounded,
              ),
              selectedIcon: Icon(
                Icons.location_on_rounded,
              ),
              label: Text(
                'Planner',
              ),
            ),

            NavigationRailDestination(
              icon: Icon(
                Icons.person_rounded,
              ),
              selectedIcon: Icon(
                Icons.person_rounded,
              ),
              label: Text(
                'Profile',
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BOOK BUTTON
  // ---------------------------------------------------------------------------

  Widget _buildBookButton({
    required bool compact,
  }) {
    return Padding(
      padding:
      EdgeInsets.symmetric(
        horizontal:
        compact ? 10 : 14,
      ),
      child: Material(
        color:
        AppColors.white,
        borderRadius:
        BorderRadius.circular(
          14,
        ),
        child: InkWell(
          onTap:
          _openBookStation,
          borderRadius:
          BorderRadius.circular(
            14,
          ),
          child: Padding(
            padding:
            EdgeInsets.symmetric(
              horizontal:
              compact ? 8 : 10,
              vertical:
              compact ? 7 : 9,
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Icon(
                  Icons
                      .bookmark_added_rounded,
                  color:
                  AppColors.primary,
                  size:
                  compact ? 20 : 23,
                ),

                SizedBox(
                  height:
                  compact ? 2 : 3,
                ),

                Text(
                  'Book',
                  style: TextStyle(
                    color:
                    AppColors.primary,
                    fontSize:
                    compact ? 9 : 10,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}