import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
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

/// Entry widget wherever sign-in is set up (web, and Android once configured). Watches Firebase auth state and only lets the two
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
      return const Scaffold(body: LoadingView(label: 'Checking access…'));
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IconWell(Icons.lock_outline_rounded, size: 64),
                  const SizedBox(height: 20),
                  Text('No access yet', style: AppText.title.copyWith(fontSize: 24)),
                  const SizedBox(height: 8),
                  Text(
                    'This Google account isn\'t on the list. Ask the owner to add it under User access.',
                    textAlign: TextAlign.center,
                    style: AppText.callout,
                  ),
                  const SizedBox(height: 16),
                  // Shown verbatim so a near-miss (an extra dot, googlemail.com,
                  // the wrong account in the picker) is immediately obvious.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.control,
                      border: Border.all(color: AppColors.hairlineStrong),
                    ),
                    child: SelectableText(
                      email ?? 'no email on this account',
                      textAlign: TextAlign.center,
                      style: AppText.bodyStrong.copyWith(fontFamily: 'monospace', fontSize: 14),
                    ),
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 12),
                    Text(reason!, textAlign: TextAlign.center, style: AppText.footnote),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout_rounded, size: 20),
                    label: const Text('Use another account'),
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
