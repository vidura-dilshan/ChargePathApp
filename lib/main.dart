import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

// -----------------------------------------------------------------------------
// AUTHENTICATION WRAPPER
// -----------------------------------------------------------------------------

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  static const String _driverRole = 'driver';

  static const Set<String> _validRoles = {
    'driver',
    'stationOwner',
  };

  Future<void>? _profileSetupFuture;
  String? _profileSetupUid;

  // ---------------------------------------------------------------------------
  // PASSWORD PROVIDER CHECK
  // ---------------------------------------------------------------------------

  bool _usesPasswordProvider(User user) {
    return user.providerData.any(
          (providerInfo) =>
      providerInfo.providerId == 'password',
    );
  }

  // ---------------------------------------------------------------------------
  // EMAIL VERIFICATION CHECK
  // ---------------------------------------------------------------------------

  bool _requiresEmailVerification(User user) {
    return _usesPasswordProvider(user) &&
        !user.emailVerified;
  }

  // ---------------------------------------------------------------------------
  // CREATE / UPDATE DRIVER PROFILE
  // ---------------------------------------------------------------------------
  //
  // IMPORTANT:
  //
  // This method is only called AFTER the verification gate.
  //
  // Therefore a newly-created email/password user does not receive
  // a Firestore profile until their email has been verified.
  // ---------------------------------------------------------------------------

  Future<void> _ensureDriverProfile(
      User originalUser,
      ) async {
    // Refresh Firebase Auth user information.
    await originalUser.reload();

    final User? user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception(
        'The authenticated user is no longer available.',
      );
    }

    // Password accounts must be verified before Firestore setup.
    if (_usesPasswordProvider(user) &&
        !user.emailVerified) {
      throw Exception(
        'Email verification is required before creating the profile.',
      );
    }

    // Refresh the Firebase ID token.
    //
    // This is important because Firestore security rules can
    // check request.auth.token.email_verified.
    await user.getIdToken(true);

    final DocumentReference<Map<String, dynamic>>
    userReference =
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    final DocumentSnapshot<Map<String, dynamic>>
    snapshot =
    await userReference.get();

    final Set<String> roles = <String>{};

    bool hasLegacyRoleField = false;
    bool hasCreatedAt = false;

    if (snapshot.exists) {
      final Map<String, dynamic> data =
          snapshot.data() ??
              <String, dynamic>{};

      // ---------------------------------------------------------
      // READ NEW ROLES ARRAY
      // ---------------------------------------------------------

      final dynamic existingRoles =
      data['roles'];

      if (existingRoles is List) {
        for (final dynamic role in existingRoles) {
          if (role is String &&
              _validRoles.contains(role)) {
            roles.add(role);
          }
        }
      }

      // ---------------------------------------------------------
      // MIGRATE OLD SINGLE ROLE FIELD
      // ---------------------------------------------------------

      if (data.containsKey('role')) {
        hasLegacyRoleField = true;

        final dynamic legacyRole =
        data['role'];

        if (legacyRole is String &&
            _validRoles.contains(legacyRole)) {
          roles.add(legacyRole);
        }
      }

      hasCreatedAt =
          data.containsKey('createdAt');
    }

    // This is the Driver app, so the authenticated user
    // receives Driver access.
    //
    // Existing stationOwner access is preserved.
    roles.add(_driverRole);

    final Map<String, dynamic> profileData = {
      'email': user.email,
      'roles': roles.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Only create createdAt once.
    if (!snapshot.exists || !hasCreatedAt) {
      profileData['createdAt'] =
          FieldValue.serverTimestamp();
    }

    // Delete the old role field after migration.
    if (hasLegacyRoleField) {
      profileData['role'] =
          FieldValue.delete();
    }

    await userReference.set(
      profileData,
      SetOptions(
        merge: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CACHE PROFILE SETUP
  // ---------------------------------------------------------------------------
  //
  // Without this, FutureBuilder could repeatedly execute Firestore writes
  // whenever the widget rebuilds.
  // ---------------------------------------------------------------------------

  Future<void> _getProfileSetupFuture(
      User user,
      ) {
    if (_profileSetupUid != user.uid ||
        _profileSetupFuture == null) {
      _profileSetupUid = user.uid;

      _profileSetupFuture =
          _ensureDriverProfile(user);
    }

    return _profileSetupFuture!;
  }

  // ---------------------------------------------------------------------------
  // EMAIL HAS BEEN VERIFIED
  // ---------------------------------------------------------------------------

  Future<void> _handleEmailVerified() async {
    final User? currentUser =
        FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      await currentUser.reload();

      final User? refreshedUser =
          FirebaseAuth.instance.currentUser;

      if (refreshedUser != null &&
          refreshedUser.emailVerified) {
        // Force-refresh the ID token so Firestore sees
        // email_verified = true.
        await refreshedUser.getIdToken(true);
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      // Force profile setup to run now that verification
      // has completed.
      _profileSetupUid = null;
      _profileSetupFuture = null;
    });
  }

  // ---------------------------------------------------------------------------
  // RETRY PROFILE SETUP
  // ---------------------------------------------------------------------------

  void _retryProfileSetup() {
    setState(() {
      _profileSetupUid = null;
      _profileSetupFuture = null;
    });
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // userChanges is better here than authStateChanges because
      // verification / reload changes can also update the user.
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        // ---------------------------------------------------------------------
        // FIREBASE IS CHECKING THE USER
        // ---------------------------------------------------------------------

        if (snapshot.connectionState ==
            ConnectionState.waiting) {
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
        // USER NOT LOGGED IN
        // ---------------------------------------------------------------------

        if (!snapshot.hasData) {
          _profileSetupUid = null;
          _profileSetupFuture = null;

          return const LogIn();
        }

        final User user =
            FirebaseAuth.instance.currentUser ??
                snapshot.data!;

        // ---------------------------------------------------------------------
        // EMAIL VERIFICATION REQUIRED
        // ---------------------------------------------------------------------

        if (_requiresEmailVerification(user)) {
          return EmailVerificationScreen(
            user: user,
            onVerified: _handleEmailVerified,
          );
        }

        // ---------------------------------------------------------------------
        // VERIFIED USER
        //
        // Only now do we create/update the Firestore profile.
        // ---------------------------------------------------------------------

        return FutureBuilder<void>(
          future: _getProfileSetupFuture(user),
          builder: (
              BuildContext context,
              AsyncSnapshot<void> profileSnapshot,
              ) {
            if (profileSnapshot.connectionState !=
                ConnectionState.done) {
              return const LoadingScreen();
            }

            if (profileSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.red,
                          size: 48,
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        const Text(
                          'Could not finish setting up your account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        Text(
                          '${profileSnapshot.error}',
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(
                          height: 20,
                        ),

                        ElevatedButton(
                          onPressed: _retryProfileSetup,
                          child: const Text(
                            'Try Again',
                          ),
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        TextButton(
                          onPressed: () async {
                            await FirebaseAuth.instance
                                .signOut();
                          },
                          child: const Text(
                            'Sign Out',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Firestore profile is now ready.
            return const MainScreen();
          },
        );
      },
    );
  }
}