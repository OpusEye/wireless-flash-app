import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'screens/home_screen.dart';

void main() {
  // Оптимизация для release сборки
  WidgetsFlutterBinding.ensureInitialized();
  
  // Отключаем лишнюю отладочную информацию в release
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  
  runApp(const WirelessFlashApp());
}

class WirelessFlashApp extends StatelessWidget {
  const WirelessFlashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppState(),
      child: MaterialApp(
        title: 'Wireless Flash',
        debugShowCheckedModeBanner: false,
        // Оптимизация производительности
        checkerboardOffscreenLayers: false,
        checkerboardRasterCacheImages: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          // Отключаем анимации splashFactory для быстрого отклика
          splashFactory: NoSplash.splashFactory,
          cardTheme: const CardThemeData(
            elevation: 2,
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
        ),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
