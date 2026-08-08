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
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useTabletLayout =
            constraints.maxWidth >= ResponsiveBreakpoints.tabletWidth;

        if (useTabletLayout) {
          return tablet;
        }

        return mobile;
      },
    );
  }
}