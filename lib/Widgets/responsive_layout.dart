import 'package:flutter/material.dart';
import 'package:chargepath/Widgets/responsive_breakpoints.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget tablet;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.tablet,
  });

  @override
  Widget build(BuildContext context) {
    // Always use the mobile layout for tablets as well.
    return mobile;
  }
}