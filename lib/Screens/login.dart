import 'package:chargepath/Widgets/loadingscreen.dart'; // Import the loader
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:chargepath/Theme/app_colors.dart';
import 'package:chargepath/Theme/app_spacing.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LogIn extends StatefulWidget {
  const LogIn({super.key});

  @override
  State<LogIn> createState() => _LogInState();
}

class _LogInState extends State<LogIn> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false; // This controls the full screen loader
  bool _rememberMe = false;
  bool _isPasswordVisible = false;


  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validateInputs() {
    if (_emailController.text.trim().isEmpty) {
      _showErrorDialog("Please enter your email address.");
      return false;
    }
    if (!RegExp(
      r"^[^\s@]+@[^\s@]+\.[^\s@]+$",
    ).hasMatch(_emailController.text.trim())) {
      _showErrorDialog("Please enter a valid email address.");
      return false;
    }
    if (_passwordController.text.trim().isEmpty) {
      _showErrorDialog("Please enter your password.");
      return false;
    }
    if (!_isLogin && _passwordController.text.trim().length < 6) {
      _showErrorDialog("Password must be at least 6 characters long.");
      return false;
    }
    return true;
  }

  Future<void> _authenticate() async {
    if (!_validateInputs()) return;

    // Close the keyboard before showing the loading screen.
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        final UserCredential credential =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        final User? user = credential.user;

        if (user != null) {
          // Create the application profile for this Firebase user.
          // Since this account was registered through the Main app,
          // its role is permanently marked as a driver.
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'email': user.email,
            'role': 'driver',
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Send the normal ChargePath verification email.
          await user.sendEmailVerification();
        }
      }
      // Success is handled by AuthWrapper in main.dart
    } on FirebaseAuthException catch (e) {
      // If error, turn off loading so user can retry
      if (mounted) setState(() => _isLoading = false);

      String errorMessage = "An error occurred";
      switch (e.code) {
        case 'user-not-found':
          errorMessage = "No user found for that email.";
          break;
        case 'wrong-password':
          errorMessage = "Wrong password provided.";
          break;
        case 'email-already-in-use':
          errorMessage = "The account already exists.";
          break;
        case 'weak-password':
          errorMessage = "The password provided is too weak.";
          break;
        case 'invalid-email':
          errorMessage = "The email address is invalid.";
          break;
        case 'network-request-failed':
          errorMessage = "Check your internet connection.";
          break;
        default:
          errorMessage = e.message ?? "Authentication failed.";
      }
      _showErrorDialog(errorMessage);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showErrorDialog("An unexpected error occurred: $e");
    }
  }

  Future<void> _resetPassword() async {
    final String email = _emailController.text.trim();

    if (email.isEmpty) {
      _showErrorDialog(
        "Please enter your email address before resetting your password.",
      );
      return;
    }

    if (!RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(email)) {
      _showErrorDialog("Please enter a valid email address.");
      return;
    }

    setState(() {
      FocusManager.instance.primaryFocus?.unfocus();
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text("Password Reset Email Sent"),
            content: Text(
              "A password reset link has been sent to $email. "
                  "Please check your inbox and spam folder.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text("Okay"),
              ),
            ],
          );
        },
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      String errorMessage;

      switch (error.code) {
        case "invalid-email":
          errorMessage = "The email address is invalid.";
          break;

        case "user-not-found":
          errorMessage = "No account was found with this email address.";
          break;

        case "network-request-failed":
          errorMessage = "Please check your internet connection.";
          break;

        case "too-many-requests":
          errorMessage =
          "Too many reset attempts were made. Please try again later.";
          break;

        default:
          errorMessage =
              error.message ?? "Unable to send the password reset email.";
      }

      _showErrorDialog(errorMessage);
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      _showErrorDialog("An unexpected error occurred.");
    }
  }

  Future<void> _signInWithGoogle() async {
    // Close keyboard before opening Google authentication.
    FocusManager.instance.primaryFocus?.unfocus();

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      if (kIsWeb) {
        // Flutter Web uses Firebase's browser popup directly.
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();

        googleProvider.setCustomParameters({
          'prompt': 'select_account',
        });

        await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        // Android and iOS continue using the Google Sign-In package.
        final GoogleSignIn googleSignIn = GoogleSignIn();

        final GoogleSignInAccount? googleUser =
        await googleSignIn.signIn();

        // The user closed the Google account selection window.
        if (googleUser == null) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }

          return;
        }

        final GoogleSignInAuthentication googleAuthentication =
        await googleUser.authentication;

        final OAuthCredential credential =
        GoogleAuthProvider.credential(
          accessToken: googleAuthentication.accessToken,
          idToken: googleAuthentication.idToken,
        );

        await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      debugPrint('Firebase Auth code: ${error.code}');
      debugPrint('Firebase Auth message: ${error.message}');

      String errorMessage;

      switch (error.code) {
        case 'popup-closed-by-user':
          errorMessage =
          'The Google sign-in window was closed before signing in.';
          break;

        case 'popup-blocked':
          errorMessage =
          'The browser blocked the Google sign-in popup. '
              'Please allow popups and try again.';
          break;

        case 'cancelled-popup-request':
          errorMessage =
          'Another Google sign-in request is already open.';
          break;

        case 'account-exists-with-different-credential':
          errorMessage =
          'An account already exists with this email using '
              'another sign-in method.';
          break;

        case 'network-request-failed':
          errorMessage =
          'Please check your internet connection and try again.';
          break;

        case 'operation-not-allowed':
          errorMessage =
          'Google Sign-In is not enabled in Firebase Authentication.';
          break;

        default:
          errorMessage =
              error.message ?? 'Google authentication failed.';
      }

      _showErrorDialog(errorMessage);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      debugPrint('Google Sign-In code: ${error.code}');
      debugPrint('Google Sign-In message: ${error.message}');
      debugPrint('Google Sign-In details: ${error.details}');

      _showErrorDialog(
        error.message ??
            'Google Sign-In failed. Please verify the app configuration.',
      );
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      debugPrint('Google Sign-In error: $error');
      debugPrint('Stack trace: $stackTrace');

      _showErrorDialog(
        'Google Sign-In failed.\n\n$error',
      );
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Action Required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Okay'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useWideLayout =
            constraints.maxWidth >= 850;

        final bool isShortHeight =
            constraints.maxHeight < 750;

        return Stack(
          children: [
            if (useWideLayout)
              _buildWideLayout(
                isShortHeight: isShortHeight,
              )
            else
              _buildMobileLayout(
                isShortHeight: isShortHeight,
              ),

            if (_isLoading)
              const Positioned.fill(
                child: LoadingScreen(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMobileLayout({
    required bool isShortHeight,
  }) {
    final bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            isPortrait
                ? ClipPath(
                    clipper: BottomWaveClipper(),
                    child: _buildMobileBrandHeader(
                      isShortHeight: isShortHeight,
                      isPortrait: true,
                    ),
                  )
                : _buildMobileBrandHeader(
                    isShortHeight: isShortHeight,
                    isPortrait: false,
                  ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  isShortHeight
                      ? AppSpacing.md
                      : AppSpacing.lg,
                  AppSpacing.lg,
                  MediaQuery.of(context).padding.bottom +
                      AppSpacing.lg,
                ),
                child: _buildAuthForm(
                  isCompactHeight: isShortHeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileBrandHeader({
    required bool isShortHeight,
    bool isPortrait = true,
  }) {
    final double screenHeight = MediaQuery.of(context).size.height;

    double headerHeight = screenHeight * (isShortHeight ? 0.25 : 0.30);
    if (headerHeight < 210) headerHeight = 210;

    return SizedBox(
      height: headerHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'lib/Assets/loginimage.jpeg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
                ) {
              return Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                ),
              );
            },
          ),

          // Dark overlay so the logo/text stay readable.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF012B55).withOpacity(0.72),
                  const Color(0xFF0253A4).withOpacity(0.28),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (Navigator.canPop(context))
                  Padding(
                    padding: EdgeInsets.only(bottom: isPortrait ? 16.0 : 0.0),
                    child: Material(
                      color: Colors.white.withOpacity(0.16),
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                        },
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),

                if (!isPortrait) const Spacer(),

                const Row(
                  children: [
                    Icon(
                      Icons.ev_station_rounded,
                      color: Colors.white,
                      size: 30,
                    ),

                    SizedBox(
                      width: AppSpacing.sm,
                    ),

                    Text(
                      'ChargePath',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: AppSpacing.sm,
                ),

                Text(
                  'Drive smarter. Charge easier.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                if (isPortrait) const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout({
    required bool isShortHeight,
  }) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 11,
              child: _buildBrandPanel(),
            ),

            Expanded(
              flex: 9,
              child: Container(
                color: Colors.white,
                child: Center(
                  child: SingleChildScrollView(
                    physics:
                    const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal:
                      isShortHeight ? 32 : 48,
                      vertical:
                      isShortHeight ? 10 : 36,
                    ),
                    child: ConstrainedBox(
                      constraints:
                      const BoxConstraints(
                        maxWidth: 470,
                      ),
                      child: _buildAuthForm(
                        isWideLayout: true,
                        isCompactHeight:
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

  Widget _buildBrandPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isShortHeight = constraints.maxHeight < 560;

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'lib/Assets/loginimage.jpeg',
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

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF012B55).withOpacity(0.93),
                    const Color(0xFF0253A4).withOpacity(0.70),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.all(
                isShortHeight ? 28 : 48,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                  constraints.maxHeight -
                      (isShortHeight ? 56 : 96),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: isShortHeight ? 50 : 66,
                        height: isShortHeight ? 50 : 66,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(
                            isShortHeight ? 16 : 20,
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.28),
                          ),
                        ),
                        child: Icon(
                          Icons.ev_station_rounded,
                          color: Colors.white,
                          size: isShortHeight ? 26 : 34,
                        ),
                      ),

                      SizedBox(
                        height: isShortHeight ? 28 : 80,
                      ),

                      Text(
                        'ChargePath',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isShortHeight ? 30 : 40,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),

                      SizedBox(
                        height: isShortHeight ? 8 : 12,
                      ),

                      Text(
                        'Plan routes, find charging stations, and reserve '
                            'charging slots from one place.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.82),
                          fontSize: isShortHeight ? 14 : 17,
                          height: 1.5,
                        ),
                      ),

                      if (!isShortHeight) ...[
                        const SizedBox(height: 28),

                        _buildBrandFeature(
                          Icons.route_rounded,
                          'EV-aware route planning',
                        ),

                        const SizedBox(height: 14),

                        _buildBrandFeature(
                          Icons.ev_station_rounded,
                          'Nearby charging stations',
                        ),

                        const SizedBox(height: 14),

                        _buildBrandFeature(
                          Icons.calendar_month_rounded,
                          'Simple station reservations',
                        ),
                      ],

                      const Spacer(),

                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          'Drive smarter. Charge easier.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBrandFeature(
      IconData icon,
      String text,
      ) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthForm({
    bool isWideLayout = false,
    bool isCompactHeight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: isWideLayout ? 0 : 10,
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                _isLogin
                    ? 'Welcome Back'
                    : 'Create Account',
                style: TextStyle(
                  fontSize: isWideLayout
                      ? (isCompactHeight ? 28 : 34)
                      : (isCompactHeight ? 24 : 28),
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
            Container(
              height: isCompactHeight ? 36 : 44,
              width: isCompactHeight ? 36 : 44,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.ev_station_rounded,
                color: Colors.white,
                size: isCompactHeight ? 20 : 25,
              ),
            ),
          ],
        ),
        SizedBox(
          height: isCompactHeight ? 4 : 8,
        ),
        Text(
          _isLogin
              ? 'Login to your account'
              : 'Sign up to get started',
          style: TextStyle(
            fontSize: isCompactHeight ? 13 : 16,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(
          height: isCompactHeight ? 12 : 20,
        ),
        _buildCustomTextField(
          controller: _emailController,
          hintText: 'Email Address',
          icon: Icons.email_outlined,
          isCompact: isCompactHeight,
        ),
        SizedBox(
          height: isCompactHeight ? 8 : 14,
        ),
        _buildCustomTextField(
          controller: _passwordController,
          hintText: 'Password',
          icon: Icons.lock_outline,
          isPassword: true,
          isCompact: isCompactHeight,
        ),
        SizedBox(
          height: isCompactHeight ? 4 : 8,
        ),
        if (_isLogin)
          Row(
            children: [
              SizedBox(
                height: isCompactHeight ? 20 : 24,
                width: isCompactHeight ? 20 : 24,
                child: Checkbox(
                  value: _rememberMe,
                  activeColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  onChanged: (bool? value) {
                    setState(() {
                      _rememberMe = value ?? false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Remember me',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: isCompactHeight ? 12 : 14,
                  ),
                ),
              ),
              TextButton(
                onPressed: _resetPassword,
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: isCompactHeight ? 12 : 14,
                  ),
                ),
              ),
            ],
          ),
        SizedBox(
          height: isCompactHeight ? 10 : 20,
        ),
        SizedBox(
          width: double.infinity,
          height: isCompactHeight ? 46 : 54,
          child: ElevatedButton(
            onPressed: _authenticate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _isLogin ? 'Login' : 'Create Account',
              style: TextStyle(
                fontSize: isCompactHeight ? 14 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        SizedBox(
          height: isCompactHeight ? 8 : 12,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _isLogin
                    ? "Don't have an account? "
                    : "Already have an account? ",
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: isCompactHeight ? 12 : 14,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isLogin = !_isLogin;
                });
              },
              child: Text(
                _isLogin
                    ? 'Sign up'
                    : 'Login',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: isCompactHeight ? 12 : 14,
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: isCompactHeight ? 8 : 14,
        ),
        Row(
          children: [
            Expanded(
              child: Divider(
                color: Colors.grey.shade300,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
              ),
              child: Text(
                'OR',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: Colors.grey.shade300,
              ),
            ),
          ],
        ),
        SizedBox(
          height: isCompactHeight ? 8 : 14,
        ),
        SizedBox(
          width: double.infinity,
          height: isCompactHeight ? 46 : 54,
          child: OutlinedButton.icon(
            onPressed: _signInWithGoogle,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: Colors.grey.shade300,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: Image.network(
              'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/768px-Google_%22G%22_logo.svg.png',
              height: isCompactHeight ? 20 : 24,
              width: isCompactHeight ? 20 : 24,
              errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stackTrace,
                  ) {
                return const Icon(
                  Icons.account_circle_outlined,
                  size: 24,
                );
              },
            ),
            label: const Text(
              'Sign in with Google',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        SizedBox(
          height: isCompactHeight ? 4 : 20,
        ),
      ],
    );
  }

  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    bool isCompact = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        prefixIcon: Icon(
          icon,
          color: AppColors.textSecondary,
        ),
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(
            _isPasswordVisible
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            color: AppColors.textSecondary,
          ),
          onPressed: () {
            setState(() {
              _isPasswordVisible = !_isPasswordVisible;
            });
          },
        )
            : null,
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppColors.textSecondary,
        ),
        filled: true,
        fillColor: AppColors.lightFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 1.4,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isCompact ? 11 : 16,
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