import 'package:flutter/material.dart';
import 'package:chargepath/Theme/app_colors.dart';

class CustomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTabChange;
  final VoidCallback onCenterTap;

  const CustomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTabChange,
    required this.onCenterTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        /*
         * If this widget is narrow and tall, it is being used
         * as the left-side navigation rail.
         */
        final bool useSideRail =
            constraints.maxHeight > constraints.maxWidth &&
            constraints.maxWidth < 180;

        if (useSideRail) {
          return _buildSideRail(context, constraints);
        }

        return _buildBottomBar(context, constraints);
      },
    );
  }

  // ===========================================================================
  // SIDE NAVIGATION RAIL
  // ===========================================================================

  Widget _buildSideRail(BuildContext context, BoxConstraints constraints) {
    /*
     * Phone landscape screens have very little usable height.
     *
     * Under 500px we remove text labels and use an icon-only rail.
     * This is the important change that removes the remaining
     * 16px RenderFlex overflow.
     */
    final bool isShortLandscape = constraints.maxHeight < 500;

    final double railWidth = isShortLandscape ? 88 : 104;

    return Container(
      width: railWidth,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: Color(0x330253A4),
            blurRadius: 18,
            spreadRadius: 1,
            offset: Offset(4, 0),
          ),
        ],
      ),

      /*
       * We deliberately do not add another bottom SafeArea here.
       * MainScreen/Scaffold already gives us the usable content area.
       *
       * Adding another bottom SafeArea can consume extra vertical
       * pixels on Android landscape.
       */
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 7,
          vertical: isShortLandscape ? 5 : 12,
        ),
        child: Column(
          children: [
            // -----------------------------------------------------------------
            // LOGO
            // -----------------------------------------------------------------
            _buildRailLogo(compact: isShortLandscape),

            SizedBox(height: isShortLandscape ? 4 : 12),

            // -----------------------------------------------------------------
            // MAIN NAVIGATION
            //
            // Expanded means these buttons must use only the space
            // available between the logo and Book button.
            // -----------------------------------------------------------------
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildRailNavItem(
                    index: 0,
                    icon: Icons.home_rounded,
                    label: 'Home',
                    compact: isShortLandscape,
                  ),

                  _buildRailNavItem(
                    index: 1,
                    icon: Icons.ev_station_rounded,
                    label: 'Stations',
                    compact: isShortLandscape,
                  ),

                  _buildRailNavItem(
                    index: 2,
                    icon: Icons.location_on_rounded,
                    label: 'Planner',
                    compact: isShortLandscape,
                  ),

                  _buildRailNavItem(
                    index: 3,
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    compact: isShortLandscape,
                  ),
                ],
              ),
            ),

            SizedBox(height: isShortLandscape ? 4 : 10),

            // -----------------------------------------------------------------
            // BOOK BUTTON
            // -----------------------------------------------------------------
            _buildRailBookButton(compact: isShortLandscape),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // RAIL LOGO
  // ===========================================================================

  Widget _buildRailLogo({required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 38 : 46,
          height: compact ? 38 : 46,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.directions_car_rounded,
            color: AppColors.primary,
            size: compact ? 20 : 24,
          ),
        ),

        /*
         * Hide ChargePath text on short landscape screens.
         * The logo itself is enough in this mode.
         */
        if (!compact) ...[
          const SizedBox(height: 4),
          const Text(
            'ChargePath',
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // RAIL NAV ITEM
  // ===========================================================================

  Widget _buildRailNavItem({
    required int index,
    required IconData icon,
    required String label,
    required bool compact,
  }) {
    final bool isSelected = selectedIndex == index;

    return GestureDetector(
      onTap: () {
        onTabChange(index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        width: double.infinity,

        /*
         * In short landscape mode we use a fixed small height.
         * This guarantees four items fit in the remaining rail.
         */
        height: compact ? 38 : 58,

        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 11 : 14),
        ),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.48),
              size: compact
                  ? isSelected
                        ? 22
                        : 20
                  : isSelected
                  ? 25
                  : 23,
            ),

            /*
             * IMPORTANT:
             *
             * Labels are completely removed on short landscape
             * screens. Previously they were still taking vertical
             * space, which is why you still had the 16px overflow.
             */
            if (!compact) ...[
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withOpacity(0.48),
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // RAIL BOOK BUTTON
  // ===========================================================================

  Widget _buildRailBookButton({required bool compact}) {
    return GestureDetector(
      onTap: onCenterTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 40 : 48,
            height: compact ? 40 : 48,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(compact ? 11 : 14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x280253A4),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              Icons.bookmark_added_rounded,
              color: AppColors.primary,
              size: compact ? 19 : 23,
            ),
          ),

          /*
           * Hide Book text in short landscape mode too.
           */
          if (!compact) ...[
            const SizedBox(height: 4),
            const Text(
              'Book',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // BOTTOM NAVIGATION BAR
  // ===========================================================================

  Widget _buildBottomBar(BuildContext context, BoxConstraints constraints) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);

    final double deviceBottomPadding = mediaQuery.padding.bottom;

    final bool isGestureNavigation = mediaQuery.systemGestureInsets.bottom > 20;

    final bool isLandscape = mediaQuery.orientation == Orientation.landscape;

    /*
     * Landscape phones are height-constrained and some devices still report
     * a bottom inset around 16px. Adding that inset to the fixed bar height is
     * what causes the small bottom overflow. In landscape this bar is already
     * anchored to the bottom edge and the labels are hidden, so we keep the
     * inset out of the bar's height.
     */
    final double bottomSafePadding = isLandscape || isGestureNavigation
        ? 0
        : deviceBottomPadding;

    final bool hasTightHeight =
        constraints.hasBoundedHeight && constraints.maxHeight < 70;

    final double navBarHeight = isLandscape || hasTightHeight ? 48 : 70;

    final double centerButtonSize = isLandscape || hasTightHeight ? 38 : 52;

    final double centerButtonTop = isLandscape || hasTightHeight ? -8 : -18;

    return Container(
      height: navBarHeight + bottomSafePadding,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: Color(0x330253A4),
            blurRadius: 18,
            spreadRadius: 1,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomSafePadding),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isLandscape ? 8 : 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildBottomNavItem(
                      index: 0,
                      icon: Icons.home_rounded,
                      label: 'Home',
                      isLandscape: isLandscape,
                    ),
                  ),

                  Expanded(
                    child: _buildBottomNavItem(
                      index: 1,
                      icon: Icons.ev_station_rounded,
                      label: 'Stations',
                      isLandscape: isLandscape,
                    ),
                  ),

                  SizedBox(width: isLandscape ? 46 : 64),

                  Expanded(
                    child: _buildBottomNavItem(
                      index: 2,
                      icon: Icons.location_on_rounded,
                      label: 'Planner',
                      isLandscape: isLandscape,
                    ),
                  ),

                  Expanded(
                    child: _buildBottomNavItem(
                      index: 3,
                      icon: Icons.person_rounded,
                      label: 'Profile',
                      isLandscape: isLandscape,
                    ),
                  ),
                ],
              ),
            ),

            // -----------------------------------------------------------------
            // BOOK BUTTON
            // -----------------------------------------------------------------
            Positioned(
              top: centerButtonTop,
              child: GestureDetector(
                onTap: onCenterTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: centerButtonSize,
                  height: centerButtonSize,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x280253A4),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.bookmark_added_rounded,
                    color: AppColors.primary,
                    size: isLandscape ? 19 : 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // BOTTOM NAV ITEM
  // ===========================================================================

  Widget _buildBottomNavItem({
    required int index,
    required IconData icon,
    required String label,
    required bool isLandscape,
  }) {
    final bool isSelected = selectedIndex == index;

    return GestureDetector(
      onTap: () {
        onTabChange(index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 4 : 8,
          vertical: isLandscape ? 3 : 7,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(isLandscape ? 10 : 14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.45),
              size: isLandscape
                  ? isSelected
                        ? 22
                        : 20
                  : isSelected
                  ? 26
                  : 24,
            ),

            /*
             * Bottom labels are also removed in landscape.
             */
            if (!isLandscape) ...[
              const SizedBox(height: 4),

              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withOpacity(0.45),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  letterSpacing: 0.3,
                ),
              ),
            ],

            SizedBox(height: isLandscape ? 2 : 3),

            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 3,
              width: isSelected
                  ? isLandscape
                        ? 14
                        : 18
                  : 0,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
