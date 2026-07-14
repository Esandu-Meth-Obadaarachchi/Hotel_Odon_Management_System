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

  // Firebase Google auth is web-only. On mobile we go straight to HomeScreen.
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey, // Add this line for image processing
    home: kIsWeb ? const AuthGate() : HomeScreen(),
  ));
}
