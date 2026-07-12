import 'package:chargepath/Widgets/loadingscreen.dart'; // Import the loader
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';

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
      final GoogleSignIn googleSignIn = GoogleSignIn();

      // Opens the Google account selection window.
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      // The user closed the account selection window.
      if (googleUser == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Gets the authentication tokens from Google.
      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Uses the Google credential to sign in to Firebase.
      await FirebaseAuth.instance.signInWithCredential(credential);

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

      debugPrint("Firebase Auth code: ${error.code}");
      debugPrint("Firebase Auth message: ${error.message}");

      _showErrorDialog(
        "Firebase error: ${error.code}\n\n"
            "${error.message ?? 'Google authentication failed.'}",
      );
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      debugPrint("Google Sign-In code: ${error.code}");
      debugPrint("Google Sign-In message: ${error.message}");
      debugPrint("Google Sign-In details: ${error.details}");

      _showErrorDialog(
        "Google Sign-In error: ${error.code}\n\n"
            "${error.message ?? 'Please verify your Firebase configuration.'}",
      );
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      debugPrint("Google Sign-In error: $error");
      debugPrint("Stack trace: $stackTrace");

      _showErrorDialog(
        "Google Sign-In failed.\n\n$error",
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
    final Size size = MediaQuery.of(context).size;

    return Stack(
      children: [
        // 1. THE ACTUAL LOGIN PAGE
        Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(
            child: Column(
              children: [
                // HEADER
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
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(color: _primaryColor),
                            ),
                            Container(color: Colors.black.withOpacity(0.1)),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 50,
                      left: 20,
                      child: InkWell(
                        onTap: () {
                          if (Navigator.canPop(context)) Navigator.pop(context);
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

                // FORM
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            _isLogin ? 'Welcome Back' : 'Create Account',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            height: 40,
                            width: 40,
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.ev_station_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin
                            ? 'Login to your account'
                            : 'Sign up to get started',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 25),
                      _buildCustomTextField(
                        controller: _emailController,
                        hintText: 'Email Address',
                        icon: Icons.email_outlined,
                      ),
                      const SizedBox(height: 15),
                      _buildCustomTextField(
                        controller: _passwordController,
                        hintText: 'Password',
                        icon: Icons.lock_outline,
                        isPassword: true,
                      ),
                      const SizedBox(height: 10),
                      if (_isLogin)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
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
                                    onChanged: (value) =>
                                        setState(() => _rememberMe = value!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Remember me',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
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
                      const SizedBox(height: 25),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _authenticate, // Logic handles loading now
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            _isLogin ? 'Login' : 'Create Account',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isLogin
                                ? "Don't have an account? "
                                : "Already have an account? ",
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isLogin = !_isLogin;
                              });
                            },
                            child: Text(
                              _isLogin ? "Sign up" : "Login",
                              style: TextStyle(
                                color: _primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Center(
                        child: Text(
                          "OR",
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: OutlinedButton.icon(
                          onPressed: _signInWithGoogle,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          icon: Image.network(
                            'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/768px-Google_%22G%22_logo.svg.png',
                            height: 24,
                            width: 24,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.error),
                          ),
                          label: const Text(
                            "Sign in with Google",
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
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. THE LOADING OVERLAY
        if (_isLoading)
          const Opacity(
            opacity: 1.0,
            child: LoadingScreen(), // This covers the entire screen
          ),
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
