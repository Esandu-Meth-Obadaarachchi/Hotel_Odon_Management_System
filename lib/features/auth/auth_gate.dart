import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:odon_booking/core/api/api_service.dart';

import '../home/home_screen.dart';
import 'login_screen.dart';

/// Who the current user is, as decided by the server. Set once the access
/// check passes so other screens (e.g. the admin tile) can read it without
/// asking again.
class CurrentUser {
  CurrentUser({required this.email, required this.name, required this.isAdmin});

  final String email;
  final String name;
  final bool isAdmin;

  static CurrentUser? current;
}

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
      // userChanges() fires on sign-in, sign-out and token refresh. Seeding it
      // with the user Firebase already holds means a popup sign-in that does
      // not immediately push through the stream still advances the UI, instead
      // of leaving the user staring at the login page.
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        // The server owns the allow-list; ask it rather than trusting a list
        // compiled into the app.
        return _AccessCheck(user: user);
      },
    );
  }
}

/// Asks the backend whether this account may use the dashboard.
///
/// Falls back to the built-in [kAllowedEmails] when the server cannot answer
/// (older backend without /me, or no network), so an outage can never lock the
/// owners out of their own hotel.
class _AccessCheck extends StatefulWidget {
  const _AccessCheck({required this.user});

  final User user;

  @override
  State<_AccessCheck> createState() => _AccessCheckState();
}

class _AccessCheckState extends State<_AccessCheck> {
  final _api = ApiService();
  bool _checking = true;
  bool _allowed = false;
  String? _deniedReason;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant _AccessCheck old) {
    super.didUpdateWidget(old);
    if (old.user.uid != widget.user.uid) _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _deniedReason = null;
    });

    final email = widget.user.email;
    try {
      final me = await _api.fetchMe();
      if (!mounted) return;

      if (me != null) {
        CurrentUser.current = CurrentUser(
          email: me['email']?.toString() ?? email ?? '',
          name: me['name']?.toString() ?? '',
          isAdmin: me['isAdmin'] == true,
        );
        setState(() {
          _allowed = true;
          _checking = false;
        });
        return;
      }

      // Server could not answer — fall back to the built-in list.
      final ok = isAllowedEmail(email);
      CurrentUser.current = ok
          ? CurrentUser(
              email: email ?? '',
              name: widget.user.displayName ?? '',
              // Without the server we cannot know; treat the built-in accounts
              // as admins so access management stays reachable.
              isAdmin: true,
            )
          : null;
      setState(() {
        _allowed = ok;
        _checking = false;
      });
    } on ApiAuthException catch (e) {
      if (!mounted) return;
      CurrentUser.current = null;
      setState(() {
        _allowed = false;
        _deniedReason = e.message;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_allowed) {
      return _AccessDeniedScreen(
        email: widget.user.email,
        reason: _deniedReason,
      );
    }
    return HomeScreen();
  }
}

class _AccessDeniedScreen extends StatelessWidget {
  const _AccessDeniedScreen({required this.email, this.reason});

  final String? email;
  final String? reason;

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
                const Text(
                  'This account is not authorised to use this dashboard.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                ),
                const SizedBox(height: 14),
                // Shown verbatim so a near-miss (an extra dot, googlemail.com,
                // the wrong account in the picker) is immediately obvious.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: SelectableText(
                    email ?? 'no email on this account',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (reason != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    reason!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                ],
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
