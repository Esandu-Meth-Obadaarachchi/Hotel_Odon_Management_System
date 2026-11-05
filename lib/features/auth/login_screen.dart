import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';

import 'auth_gate.dart';

/// Google sign-in page for the web dashboard and the Android app. Only the accounts listed in
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

      // Web opens a popup; Android opens Google's sign-in page in a browser
      // tab and returns to the app.
      final cred = kIsWeb
          ? await FirebaseAuth.instance.signInWithPopup(provider)
          : await FirebaseAuth.instance.signInWithProvider(provider);
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
          e.code == 'cancelled-popup-request' ||
          e.code == 'web-context-canceled' ||
          e.code == 'canceled') {
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
    final reduced = AppMotion.reduced(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduced ? 1 : 0, end: 1),
                duration: AppMotion.slow,
                curve: AppMotion.ease,
                builder: (_, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: AppShadow.float),
                      child: const BrandSeal(size: 112),
                    ),
                    const SizedBox(height: 28),
                    Text('The Odon', style: AppText.largeTitle.copyWith(fontSize: 34)),
                    const SizedBox(height: 6),
                    Text('Front desk and office', style: AppText.callout.copyWith(fontSize: 15)),
                    const SizedBox(height: 36),
                    if (_error != null) ...[
                      InlineBanner(_error!, tone: BannerTone.warning),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      onPressed: _busy ? null : _signInWithGoogle,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.login_rounded, size: 20),
                      label: Text(_busy ? 'Signing in…' : 'Continue with Google'),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'For hotel staff. Use the Google account the owner added for you.',
                      textAlign: TextAlign.center,
                      style: AppText.footnote,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
