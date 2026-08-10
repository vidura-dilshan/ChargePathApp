import 'package:flutter/material.dart';
import 'package:chargepath/Screens/home.dart';
import 'package:chargepath/Screens/chargingstations.dart';
import 'package:chargepath/Screens/routeplanning.dart';
import 'package:chargepath/Screens/bookstation.dart';
import 'package:chargepath/Screens/profilepage.dart';
import 'package:chargepath/Widgets/navigationbar.dart';
import 'package:chargepath/Widgets/responsive_layout.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  void _changePage(int index) {
    // Close the keyboard before changing pages.
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _selectedIndex = index;
    });
  }

  void _openBookStation() {
    // Close the keyboard before opening the booking screen.
    FocusManager.instance.primaryFocus?.unfocus();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BookStation(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(
        onNavigateToStations: () => _changePage(1),
      ),
      const FindStations(),
      const RoutePlanningPage(),
      const ProfilePage(),
    ];

    return ResponsiveLayout(
      mobile: _buildMobileLayout(pages),
      tablet: _buildTabletLayout(pages),
    );
  }

  Widget _buildMobileLayout(List<Widget> pages) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomNavBar(
              selectedIndex: _selectedIndex,
              onTabChange: _changePage,
              onCenterTap: _openBookStation,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(List<Widget> pages) {
    return Scaffold(
      // Important:
      // Do not shrink the entire EV/tablet interface when
      // the on-screen keyboard appears.
      resizeToAvoidBottomInset: false,

      body: SafeArea(
        child: Row(
          children: [
            _buildTabletNavigation(),

            const VerticalDivider(
              width: 1,
              thickness: 1,
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

  Widget _buildTabletNavigation() {
    return Container(
      width: 112,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0253A4),
            Color(0xFF034485),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                const SizedBox(height: 14),

                const CircleAvatar(
                  radius: 21,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.electric_car_rounded,
                    color: Color(0xFF0253A4),
                    size: 25,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'ChargePath',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Expanded(
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _changePage,

                    backgroundColor: Colors.transparent,

                    labelType: NavigationRailLabelType.all,

                    groupAlignment: 0,

                    useIndicator: true,

                    indicatorColor:
                    Colors.white.withOpacity(0.18),

                    minWidth: 72,

                    selectedIconTheme:
                    const IconThemeData(
                      color: Colors.white,
                      size: 26,
                    ),

                    unselectedIconTheme:
                    IconThemeData(
                      color: Colors.white.withOpacity(0.5),
                      size: 23,
                    ),

                    selectedLabelTextStyle:
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),

                    unselectedLabelTextStyle:
                    TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),

                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(
                          Icons.home_rounded,
                        ),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(
                          Icons.ev_station_rounded,
                        ),
                        label: Text('Stations'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(
                          Icons.location_on_rounded,
                        ),
                        label: Text('Planner'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(
                          Icons.person_rounded,
                        ),
                        label: Text('Profile'),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  child: Material(
                    color: Colors.white,
                    borderRadius:
                    BorderRadius.circular(14),
                    child: InkWell(
                      onTap: _openBookStation,
                      borderRadius:
                      BorderRadius.circular(14),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bookmark_added_rounded,
                              color: Color(0xFF0253A4),
                              size: 23,
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Book',
                              style: TextStyle(
                                color:
                                Color(0xFF0253A4),
                                fontSize: 10,
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}