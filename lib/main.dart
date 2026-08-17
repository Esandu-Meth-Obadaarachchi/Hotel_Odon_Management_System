import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'features/auth/auth_gate.dart';
import 'firebase_options.dart';

// Add this global navigator key for image processing
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// The Firebase project whose ID tokens the backend trusts (its
/// FIREBASE_PROJECT_ID). If a platform initialises against anything else, every
/// request will be rejected with a 401, so we fail loudly instead.
const String kExpectedFirebaseProject = 'odon-dashboard-fin';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initError;
  try {
    if (kIsWeb) {
      // Web has no google-services file; its config is compiled in.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      // Android/iOS read google-services.json / GoogleService-Info.plist via
      // the platform Firebase plugins, so no explicit options are needed.
      await Firebase.initializeApp();
    }

    final projectId = Firebase.app().options.projectId;
    if (projectId != kExpectedFirebaseProject) {
      initError =
          'This build is configured for the Firebase project "$projectId", but '
          'the server only accepts sign-ins from "$kExpectedFirebaseProject". '
          'Replace android/app/google-services.json (or the iOS plist) with the '
          'one from the $kExpectedFirebaseProject project and rebuild.';
    }
  } catch (e) {
    initError = 'Firebase could not start: $e';
  }

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey, // Add this line for image processing
    home: initError != null ? _ConfigErrorScreen(message: initError) : const AuthGate(),
  ));
}

/// Shown instead of the app when Firebase is misconfigured. Without this the
/// symptom would be a working login followed by every request failing.
class _ConfigErrorScreen extends StatelessWidget {
  const _ConfigErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_suggest_rounded,
                    color: Color(0xFFF59E0B), size: 60),
                const SizedBox(height: 20),
                const Text(
                  'Configuration problem',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
