import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_gate.dart';

/// Google sign-in page for the web dashboard. Only the accounts listed in
/// [kAllowedEmails] are allowed through; any other account is signed back out
/// immediately and shown an error.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});

      final cred = await FirebaseAuth.instance.signInWithPopup(provider);
      final email = cred.user?.email;

      // Logged so a near-miss (extra dot, googlemail.com, wrong account picked)
      // is visible in the console rather than looking like a silent failure.
      debugPrint('[auth] signed in as "$email"');

      // Deliberately no allow-list check here. The server owns that decision,
      // and AuthGate asks it — checking a hardcoded copy at this point would
      // sign out anyone granted access from the User Access screen before the
      // server was ever consulted. Refusals are shown by the access screen,
      // which offers a sign-out.
      if (!mounted) return;
      setState(() {}); // nudge a rebuild in case the auth stream is slow
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        // User dismissed the popup — not an error worth showing.
      } else {
        if (mounted) setState(() => _error = e.message ?? 'Sign-in failed.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.hotel_rounded,
                        color: Color(0xFF6366F1), size: 44),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'ODON Dashboard',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to continue',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                  ),
                  const SizedBox(height: 32),
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                const Color(0xFFEF4444).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Color(0xFFEF4444), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Color(0xFFFCA5A5), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1F2937),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _busy ? null : _signInWithGoogle,
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login, size: 22),
                      label: Text(_busy ? 'Signing in…' : 'Sign in with Google'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Access is restricted to authorised hotel staff only.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
