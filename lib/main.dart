import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Screens/login.dart';
import 'Screens/mainscreen.dart';
import 'Widgets/loadingscreen.dart';

void main() async {
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
      // scaffoldBackgroundColor matches LoadingScreen so any
      // un-painted frame shows brand color, never white.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0253A4)),
        scaffoldBackgroundColor: const Color(0xFFF0F6FF),
        useMaterial3: true,
      ),
      home: const _AppStartup(),
    );
  }
}

// ── STARTUP ──────────────────────────────────────────────────────────────────
// Shown as the very first widget so LoadingScreen appears on frame 1.

class _AppStartup extends StatefulWidget {
  const _AppStartup();

  @override
  State<_AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<_AppStartup> {
  late final Future<void> _init;

  @override
  void initState() {
    super.initState();
    _init = Firebase.initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
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
                  "Startup error:\n${snapshot.error}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
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

// ── AUTH WRAPPER ──────────────────────────────────────────────────────────────
// AnimatedSwitcher with a FadeTransition eliminates the white frame that
// appears when StreamBuilder rebuilds between LoadingScreen and MainScreen.
// Without this, Flutter needs one unpainted frame to lay out the new widget —
// AnimatedSwitcher keeps the old widget (LoadingScreen) visible until the
// new one (MainScreen / LogIn) is fully ready to paint.

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Determine which child to show
        final Widget child;
        if (snapshot.connectionState == ConnectionState.waiting) {
          child = const LoadingScreen(key: ValueKey('loading'));
        } else if (snapshot.hasError) {
          child = const Scaffold(
            key: ValueKey('error'),
            body: Center(child: Text("Auth Error")),
          );
        } else if (snapshot.hasData) {
          child = const MainScreen(key: ValueKey('main'));
        } else {
          child = const LogIn(key: ValueKey('login'));
        }

        // AnimatedSwitcher fades between widgets instead of cutting,
        // which hides the one-frame white gap on every state transition.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: child,
        );
      },
    );
  }
}