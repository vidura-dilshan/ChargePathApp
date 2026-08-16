import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'Theme/app_theme.dart';
import 'firebase_options.dart';
import 'Screens/email_verification.dart';
import 'Screens/login.dart';
import 'Screens/mainscreen.dart';
import 'Widgets/loadingscreen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChargePath',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const _AppStartup(),
    );
  }
}

// -----------------------------------------------------------------------------
// APPLICATION STARTUP
// -----------------------------------------------------------------------------
//
// Firebase is initialized here so the loading screen can be shown
// while Firebase is starting.
//

class _AppStartup extends StatefulWidget {
  const _AppStartup();

  @override
  State<_AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<_AppStartup> {
  late final Future<void> _firebaseInitialization;

  @override
  void initState() {
    super.initState();

    _firebaseInitialization = Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _firebaseInitialization,
      builder: (context, snapshot) {
        // Firebase is still starting.
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingScreen();
        }

        // Firebase startup failed.
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Startup error:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          );
        }

        // Firebase has started successfully.
        return const AuthWrapper();
      },
    );
  }
}

// -----------------------------------------------------------------------------
// AUTHENTICATION WRAPPER
// -----------------------------------------------------------------------------
//
// This listens to Firebase authentication changes.
//
// It decides whether the user should see:
//
// Loading screen
// Login screen
// Email verification screen
// Main application screen
//

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  // ---------------------------------------------------------------------------
  // CHECK EMAIL VERIFICATION
  // ---------------------------------------------------------------------------

  bool _requiresEmailVerification(User user) {
    final bool usesPasswordProvider = user.providerData.any(
          (providerInfo) => providerInfo.providerId == 'password',
    );

    return usesPasswordProvider && !user.emailVerified;
  }

  // ---------------------------------------------------------------------------
  // HANDLE VERIFIED EMAIL
  // ---------------------------------------------------------------------------

  Future<void> _handleEmailVerified() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      await currentUser.reload();
    }

    if (!mounted) {
      return;
    }

    // Rebuild AuthWrapper so the new email verification state
    // can be checked.
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ---------------------------------------------------------------------
        // FIREBASE IS CHECKING THE CURRENT USER
        // ---------------------------------------------------------------------

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        // ---------------------------------------------------------------------
        // AUTHENTICATION ERROR
        // ---------------------------------------------------------------------

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Authentication error:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          );
        }

        // ---------------------------------------------------------------------
        // USER IS LOGGED IN
        // ---------------------------------------------------------------------

        if (snapshot.hasData) {
          final User user = snapshot.data!;

          // Email/password accounts must verify their email.
          if (_requiresEmailVerification(user)) {
            return EmailVerificationScreen(
              user: user,
              onVerified: _handleEmailVerified,
            );
          }

          // User is authenticated and ready to enter the app.
          return const MainScreen();
        }

        // ---------------------------------------------------------------------
        // USER IS NOT LOGGED IN
        // ---------------------------------------------------------------------

        return const LogIn();
      },
    );
  }
}