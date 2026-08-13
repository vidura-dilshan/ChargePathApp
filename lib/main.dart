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

// ── APPLICATION STARTUP ───────────────────────────────────────────────────────
//
// Firebase is initialized here instead of directly inside main().
// This allows the loading screen to appear while Firebase is starting.

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
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingScreen();
        }

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

        return const AuthWrapper();
      },
    );
  }
}

// ── AUTHENTICATION WRAPPER ───────────────────────────────────────────────────
//
// This listens for Firebase authentication changes and decides which screen
// should be displayed.

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _requiresEmailVerification(User user) {
    final bool usesPasswordProvider = user.providerData.any(
          (providerInfo) => providerInfo.providerId == 'password',
    );

    return usesPasswordProvider && !user.emailVerified;
  }

  Future<void> _handleEmailVerified() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      await currentUser.reload();
    }

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final Widget currentScreen;

        if (snapshot.connectionState == ConnectionState.waiting) {
          currentScreen = const LoadingScreen(
            key: ValueKey('loading'),
          );
        } else if (snapshot.hasError) {
          currentScreen = Scaffold(
            key: const ValueKey('authentication-error'),
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
        } else if (snapshot.hasData) {
          final User user = snapshot.data!;

          if (_requiresEmailVerification(user)) {
            currentScreen = EmailVerificationScreen(
              key: const ValueKey('email-verification'),
              user: user,
              onVerified: _handleEmailVerified,
            );
          } else {
            currentScreen = const MainScreen(
              key: ValueKey('main-screen'),
            );
          }
        } else {
          currentScreen = const LogIn(
            key: ValueKey('login-screen'),
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          transitionBuilder: (
              Widget child,
              Animation<double> animation,
              ) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: currentScreen,
        );
      },
    );
  }
}