import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import 'login_screen.dart';

/// The only Gmail accounts allowed to use the web dashboard.
/// Compared case-insensitively. Anyone else is signed straight back out.
const Set<String> kAllowedEmails = {
  'dinushaobadaarachchi@gmail.com',
  'eobadaarachchi@gmail.com',
};

bool isAllowedEmail(String? email) {
  if (email == null) return false;
  return kAllowedEmails.contains(email.trim().toLowerCase());
}

/// Web-only entry widget. Watches Firebase auth state and only lets the two
/// allow-listed accounts through to [HomeScreen]. Everyone else sees the login
/// page (or an "access denied" message if they signed in with a wrong account).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        if (!isAllowedEmail(user.email)) {
          return _AccessDeniedScreen(email: user.email);
        }

        return HomeScreen();
      },
    );
  }
}

class _AccessDeniedScreen extends StatelessWidget {
  const _AccessDeniedScreen({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, color: Color(0xFFEF4444), size: 64),
                const SizedBox(height: 20),
                const Text(
                  'Access denied',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${email ?? 'This account'} is not authorised to use this '
                  'dashboard. Please sign in with an approved account.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
