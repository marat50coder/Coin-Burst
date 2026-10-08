import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fullscreen immersive
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // If the user swipes to reveal the system bars (immersive sticky), draw
  // them as solid black so they match the SafeArea letterbox behind the
  // game canvas.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  // Loading screen allows both orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const CoinBurstApp());
}

class CoinBurstApp extends StatelessWidget {
  const CoinBurstApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coin Burst',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const LoadingScreen(),
    );
  }
}
