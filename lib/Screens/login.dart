import 'package:chargepath/Widgets/loadingscreen.dart'; // Import the loader
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

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

  final Color _primaryColor = const Color(0xFF0253A4);
  final Color _lightFillColor = const Color(0xFFE6EFF8);



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

    // Trigger the Loading Screen
    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        await credential.user?.sendEmailVerification();
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
        final bool useWideLayout = constraints.maxWidth >= 850;

        return Stack(
          children: [
            if (useWideLayout)
              _buildWideLayout()
            else
              _buildMobileLayout(),
            if (_isLoading)
              const Opacity(
                opacity: 1.0,
                child: LoadingScreen(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Stack(
              children: [
                ClipPath(
                  clipper: BottomWaveClipper(),
                  child: Container(
                    height: size.height * 0.32,
                    width: double.infinity,
                    color: _primaryColor.withOpacity(0.8),
                    child: Stack(
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
                              color: _primaryColor,
                            );
                          },
                        ),
                        Container(
                          color: Colors.black.withOpacity(0.1),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 50,
                  left: 20,
                  child: InkWell(
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
              ),
              child: _buildAuthForm(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
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
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 36,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 470,
                      ),
                      child: _buildAuthForm(
                        isWideLayout: true,
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
              color: _primaryColor,
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
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (Navigator.canPop(context))
                Material(
                  color: Colors.white.withOpacity(0.15),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.28),
                  ),
                ),
                child: const Icon(
                  Icons.ev_station_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'ChargePath',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Plan routes, find charging stations, and reserve '
                    'charging slots from one place.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 17,
                  height: 1.55,
                ),
              ),
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
              const Spacer(),
              Text(
                'Drive smarter. Charge easier.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
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
                  fontSize: isWideLayout ? 34 : 32,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
            ),
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: _primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.ev_station_rounded,
                color: Colors.white,
                size: 25,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _isLogin
              ? 'Login to your account'
              : 'Sign up to get started',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 28),
        _buildCustomTextField(
          controller: _emailController,
          hintText: 'Email Address',
          icon: Icons.email_outlined,
        ),
        const SizedBox(height: 16),
        _buildCustomTextField(
          controller: _passwordController,
          hintText: 'Password',
          icon: Icons.lock_outline,
          isPassword: true,
        ),
        const SizedBox(height: 10),
        if (_isLogin)
          Row(
            children: [
              SizedBox(
                height: 24,
                width: 24,
                child: Checkbox(
                  value: _rememberMe,
                  activeColor: _primaryColor,
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
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _resetPassword,
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: _authenticate,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: Text(
              _isLogin
                  ? 'Login'
                  : 'Create Account',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _isLogin
                    ? "Don't have an account? "
                    : "Already have an account? ",
                style: TextStyle(
                  color: Colors.grey.shade600,
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
                  color: _primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
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
                  color: Colors.grey.shade400,
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
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: OutlinedButton.icon(
            onPressed: _signInWithGoogle,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: Colors.grey.shade300,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            icon: Image.network(
              'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/768px-Google_%22G%22_logo.svg.png',
              height: 24,
              width: 24,
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
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _lightFillColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !_isPasswordVisible,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey[600]),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(
              _isPasswordVisible
                  ? Icons.visibility
                  : Icons.visibility_off,
              color: Colors.grey[600],
            ),
            onPressed: () {
              setState(() {
                _isPasswordVisible = !_isPasswordVisible;
              });
            },
          )
              : null,
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[500]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height - 40);
    var firstControlPoint = Offset(size.width / 4, size.height);
    var firstEndPoint = Offset(size.width / 2.25, size.height - 30);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );
    var secondControlPoint = Offset(
      size.width - (size.width / 3.25),
      size.height - 80,
    );
    var secondEndPoint = Offset(size.width, size.height - 40);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
