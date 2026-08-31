import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:chargepath/Theme/app_colors.dart';
import 'package:chargepath/Theme/app_spacing.dart';
import 'package:chargepath/Widgets/app_card.dart';
import 'package:chargepath/Widgets/app_primary_button.dart';
import 'package:chargepath/Widgets/app_section_header.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.user,
    required this.onVerified,
  });

  final User user;
  final VoidCallback onVerified;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends State<EmailVerificationScreen> {
  bool _isChecking = false;
  bool _isSending = false;

  Future<void> _checkVerification() async {
    if (_isChecking) {
      return;
    }

    setState(() {
      _isChecking = true;
    });

    try {
      await widget.user.reload();

      final User? user =
          FirebaseAuth.instance.currentUser;

      if (user != null &&
          user.emailVerified) {
        widget.onVerified();
        return;
      }

      _showMessage(
        'Email not verified yet. Please check your inbox.',
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(
        error.message ??
            'Could not check verification status.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _resendVerification() async {
    if (_isSending) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await widget.user.sendEmailVerification();

      _showMessage(
        'Verification email sent.',
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(
        error.message ??
            'Could not send verification email.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Google Sign-In may not be active for every session.
    }

    await FirebaseAuth.instance.signOut();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    final ScaffoldMessengerState messenger =
    ScaffoldMessenger.of(context);

    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
          context,
          constraints,
          ) {
        final bool useWideLayout =
            constraints.maxWidth >= 800;

        final bool isShortHeight =
            constraints.maxHeight < 620;

        if (useWideLayout) {
          return _buildWideLayout(
            isShortHeight: isShortHeight,
          );
        }

        return _buildMobileLayout(
          isShortHeight: isShortHeight,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE
  // ---------------------------------------------------------------------------

  Widget _buildMobileLayout({
    required bool isShortHeight,
  }) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildMobileHeader(
              isShortHeight: isShortHeight,
            ),

            Expanded(
              child: SingleChildScrollView(
                physics:
                const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  isShortHeight
                      ? AppSpacing.md
                      : AppSpacing.xl,
                  AppSpacing.lg,
                  MediaQuery.of(context)
                      .padding
                      .bottom +
                      AppSpacing.xxl,
                ),
                child: _buildVerificationCard(
                  compact:
                  isShortHeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileHeader({
    required bool isShortHeight,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        isShortHeight
            ? AppSpacing.md
            : AppSpacing.lg,
        AppSpacing.lg,
        isShortHeight
            ? AppSpacing.lg
            : AppSpacing.xl,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: Row(
        children: [
          Container(
            width: isShortHeight ? 40 : 46,
            height: isShortHeight ? 40 : 46,
            decoration: BoxDecoration(
              color:
              Colors.white.withOpacity(0.14),
              borderRadius:
              BorderRadius.circular(14),
              border: Border.all(
                color:
                Colors.white.withOpacity(0.20),
              ),
            ),
            child: const Icon(
              Icons.mark_email_unread_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),

          const SizedBox(
            width: AppSpacing.md,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Verify Email',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize:
                    isShortHeight ? 20 : 22,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                if (!isShortHeight) ...[
                  const SizedBox(height: 3),

                  Text(
                    'One final step before you continue.',
                    style: TextStyle(
                      color: Colors.white
                          .withOpacity(0.80),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLET / CAR
  // ---------------------------------------------------------------------------

  Widget _buildWideLayout({
    required bool isShortHeight,
  }) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: _buildBrandPanel(
                isShortHeight:
                isShortHeight,
              ),
            ),

            Expanded(
              flex: 5,
              child: Container(
                color: AppColors.background,
                child: Center(
                  child: SingleChildScrollView(
                    physics:
                    const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal:
                      isShortHeight
                          ? AppSpacing.xxl
                          : 48,
                      vertical:
                      isShortHeight
                          ? AppSpacing.md
                          : AppSpacing.xxxl,
                    ),
                    child: ConstrainedBox(
                      constraints:
                      const BoxConstraints(
                        maxWidth: 520,
                      ),
                      child:
                      _buildVerificationCard(
                        compact:
                        isShortHeight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandPanel({
    required bool isShortHeight,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'lib/Assets/loginimage.jpeg',
            fit: BoxFit.cover,
            color:
            const Color(0xFF012B55)
                .withOpacity(0.58),
            colorBlendMode:
            BlendMode.darken,
            errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
                ) {
              return const SizedBox.shrink();
            },
          ),

          Padding(
            padding: EdgeInsets.all(
              isShortHeight ? 28 : 48,
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Container(
                  width:
                  isShortHeight ? 52 : 66,
                  height:
                  isShortHeight ? 52 : 66,
                  decoration: BoxDecoration(
                    color: Colors.white
                        .withOpacity(0.16),
                    borderRadius:
                    BorderRadius.circular(
                      isShortHeight ? 16 : 20,
                    ),
                    border: Border.all(
                      color: Colors.white
                          .withOpacity(0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.ev_station_rounded,
                    color: Colors.white,
                    size:
                    isShortHeight ? 28 : 34,
                  ),
                ),

                const Spacer(),

                Text(
                  'Almost there.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize:
                    isShortHeight ? 30 : 40,
                    fontWeight:
                    FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),

                SizedBox(
                  height:
                  isShortHeight ? 8 : 12,
                ),

                Text(
                  'Verify your email to finish setting up your ChargePath account.',
                  style: TextStyle(
                    color: Colors.white
                        .withOpacity(0.82),
                    fontSize:
                    isShortHeight ? 14 : 17,
                    height: 1.5,
                  ),
                ),

                const Spacer(),

                Text(
                  'Drive smarter. Charge easier.',
                  style: TextStyle(
                    color: Colors.white
                        .withOpacity(0.68),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VERIFICATION CARD
  // ---------------------------------------------------------------------------

  Widget _buildVerificationCard({
    required bool compact,
  }) {
    final String email =
        widget.user.email ??
            'your email address';

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: EdgeInsets.all(
          compact
              ? AppSpacing.lg
              : AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: compact ? 62 : 76,
                height: compact ? 62 : 76,
                decoration:
                const BoxDecoration(
                  color:
                  AppColors.lightFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons
                      .mark_email_unread_rounded,
                  color:
                  AppColors.primary,
                  size: compact ? 30 : 36,
                ),
              ),
            ),

            SizedBox(
              height:
              compact
                  ? AppSpacing.md
                  : AppSpacing.xl,
            ),

            Text(
              'Verify your email',
              textAlign:
              TextAlign.center,
              style: TextStyle(
                color:
                AppColors.primary,
                fontSize:
                compact ? 24 : 28,
                fontWeight:
                FontWeight.bold,
              ),
            ),

            SizedBox(
              height:
              compact
                  ? AppSpacing.sm
                  : AppSpacing.md,
            ),

            Text(
              'We sent a verification link to',
              textAlign:
              TextAlign.center,
              style: TextStyle(
                color: AppColors
                    .textSecondary,
                fontSize:
                compact ? 13 : 14,
              ),
            ),

            const SizedBox(height: 6),

            Container(
              padding:
              const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color:
                AppColors.lightFill,
                borderRadius:
                BorderRadius.circular(
                  12,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.email_rounded,
                    color:
                    AppColors.primary,
                    size: 18,
                  ),

                  const SizedBox(
                    width: AppSpacing.sm,
                  ),

                  Expanded(
                    child: Text(
                      email,
                      textAlign:
                      TextAlign.center,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style:
                      const TextStyle(
                        color:
                        AppColors.primary,
                        fontWeight:
                        FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(
              height:
              compact
                  ? AppSpacing.md
                  : AppSpacing.xl,
            ),

            const AppSectionHeader(
              icon: Icons
                  .checklist_rounded,
              title: 'What to do next',
            ),

            SizedBox(
              height:
              compact
                  ? AppSpacing.sm
                  : AppSpacing.md,
            ),

            _buildStep(
              number: 1,
              text:
              'Open the verification email sent by ChargePath.',
            ),

            SizedBox(
              height:
              compact ? 8 : 10,
            ),

            _buildStep(
              number: 2,
              text:
              'Tap the verification link in the email.',
            ),

            SizedBox(
              height:
              compact ? 8 : 10,
            ),

            _buildStep(
              number: 3,
              text:
              'Return here and tap the verification button.',
            ),

            SizedBox(
              height:
              compact
                  ? AppSpacing.lg
                  : AppSpacing.xxl,
            ),

            AppPrimaryButton(
              text:
              'I verified my email',
              icon:
              Icons.verified_rounded,
              isLoading: _isChecking,
              onPressed:
              _isChecking
                  ? null
                  : _checkVerification,
            ),

            SizedBox(
              height:
              compact
                  ? AppSpacing.sm
                  : AppSpacing.md,
            ),

            SizedBox(
              height: compact ? 48 : 54,
              child: OutlinedButton.icon(
                onPressed:
                _isSending
                    ? null
                    : _resendVerification,
                icon: _isSending
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color:
                    AppColors.primary,
                  ),
                )
                    : const Icon(
                  Icons
                      .outgoing_mail,
                  size: 19,
                ),
                label: Text(
                  _isSending
                      ? 'Sending...'
                      : 'Resend email',
                  style:
                  const TextStyle(
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
                style:
                OutlinedButton.styleFrom(
                  foregroundColor:
                  AppColors.primary,
                  side: const BorderSide(
                    color:
                    AppColors.primary,
                    width: 1.3,
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

            SizedBox(
              height:
              compact ? 4 : 8,
            ),

            TextButton(
              onPressed: _signOut,
              child: const Text(
                'Use a different account',
                style: TextStyle(
                  color:
                  AppColors.textSecondary,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep({
    required int number,
    required String text,
  }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration:
          const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$number',
              style:
              const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight:
                FontWeight.bold,
              ),
            ),
          ),
        ),

        const SizedBox(
          width: AppSpacing.sm,
        ),

        Expanded(
          child: Padding(
            padding:
            const EdgeInsets.only(
              top: 3,
            ),
            child: Text(
              text,
              style:
              const TextStyle(
                color:
                AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
