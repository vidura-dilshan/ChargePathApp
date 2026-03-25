import 'package:flutter/material.dart';
import 'package:chargepath/Screens/home.dart';
import 'package:chargepath/Screens/chargingstations.dart';
import 'package:chargepath/Screens/routeplanning.dart';
import 'package:chargepath/Screens/bookstation.dart';
import 'package:chargepath/Widgets/navigationbar.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // All tab pages live here — they stay alive and never re-build on tab switch
  final List<Widget> _pages = const [
    HomePage(),
    FindStations(),
    RoutePlanningPage()
    // ProfilePage(), // replace with your actual profile screen
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // IndexedStack keeps all pages mounted — no rebuilds, no lag
          IndexedStack(
            index: _selectedIndex,
            children: _pages,
          ),

          // Floating nav bar on top
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomNavBar(
              selectedIndex: _selectedIndex,
              onTabChange: (index) {
                setState(() => _selectedIndex = index);
              },
              onCenterTap: () {
                // BookStation is a separate flow, so push it as a modal
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BookStation()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}