import 'package:flutter/material.dart';
import 'package:chargepath/Screens/home.dart';
import 'package:chargepath/Screens/chargingstations.dart';
import 'package:chargepath/Screens/routeplanning.dart';
import 'package:chargepath/Screens/bookstation.dart';
import 'package:chargepath/Widgets/navigationbar.dart';
import 'package:chargepath/Screens/profilepage.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(
        onNavigateToStations: () => setState(() => _selectedIndex = 1),
      ),
      const FindStations(),
      const RoutePlanningPage(),
      const ProfilePage(),
    ];

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