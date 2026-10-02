import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'features/auth/auth_gate.dart';
import 'features/home/home_screen.dart';
import 'firebase_options.dart';

// Add this global navigator key for image processing
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Google sign-in runs wherever Firebase is configured: the web, and Android
  // once its options are filled in (see firebase_options.dart). Signed-in
  // requests carry an ID token, which is how the backend knows who added or
  // edited a booking. Elsewhere the app opens straight to HomeScreen.
  var signInEnabled = false;
  final options = DefaultFirebaseOptions.signInPlatform;
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options);
      signInEnabled = true;
    } catch (e) {
      // A bad Android config must not stop the hotel from working.
      if (kIsWeb) rethrow;
      debugPrint('[auth] Firebase init failed, continuing without sign-in: $e');
    }
  }

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey, // Add this line for image processing
    home: signInEnabled ? const AuthGate() : HomeScreen(),
  ));
}
