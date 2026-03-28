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

  final List<Widget> _pages = const [
    HomePage(),        // index 0 — Home
    FindStations(),    // index 1 — Charging Stations
    RoutePlanningPage(), // index 2 — Map / Route Planning
    // ProfilePage(),  // index 3 — Profile (add when ready)
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: _pages,
          ),
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