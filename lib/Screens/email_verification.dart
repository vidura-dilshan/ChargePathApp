import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const Color _primaryColor = Color(0xFF0253A4);
  static const Color _lightFillColor = Color(0xFFE6EFF8);

  bool _isChecking = false;
  bool _isSending = false;

  Future<void> _checkVerification() async {
    setState(() => _isChecking = true);

    try {
      await widget.user.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && user.emailVerified) {
        widget.onVerified();
        return;
      }

      _showMessage('Email not verified yet. Please check your inbox.');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Could not check verification status.');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resendVerification() async {
    setState(() => _isSending = true);

    try {
      await widget.user.sendEmailVerification();
      _showMessage('Verification email sent.');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Could not send verification email.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.user.email ?? 'your email address';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  color: _lightFillColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  color: _primaryColor,
                  size: 36,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Verify your email',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to $email. Open that link, then return here and continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _checkVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isChecking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'I verified my email',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: OutlinedButton(
                  onPressed: _isSending ? null : _resendVerification,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: const BorderSide(color: _primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _isSending ? 'Sending...' : 'Resend email',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: _signOut,
                child: const Text('Use a different account'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
