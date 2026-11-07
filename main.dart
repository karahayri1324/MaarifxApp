import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'services/uzak_ayarlar.dart';
import 'widgets/common/guncelleme_kapisi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Edge-to-edge mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const MaarifxApp());
}

class MaarifxApp extends StatelessWidget {
  const MaarifxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        ),
        // Uzaktan ayarlar (model adı, zorunlu güncelleme, gizlilik, duyurular):
        // açılışta hemen çekilir; hata uygulamayı durdurmaz.
        ChangeNotifierProvider(
          create: (_) => UzakAyarlar()..yukle(zorla: true),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final isDark = themeProvider.isDarkMode;
          final overlayStyle = SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          );

          SystemChrome.setSystemUIOverlayStyle(overlayStyle);

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: MaterialApp(
              title: 'MaariFx',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.themeMode,
              home: const SplashScreen(),
              // Zorunlu güncelleme kilidi + isteğe bağlı güncelleme kartı: TÜM
              // ekranların (ve diyalogların) üstünde.
              builder: (context, child) =>
                  GuncellemeKapisi(child: child ?? const SizedBox.shrink()),
              // Adlandırılmış rotalar: SUNUCU bildirim butonu (NoticeAction kind:route)
              // uygulama-içi bir yola gidebilsin diye. Bunlar tanımlı olmadan
              // runNoticeAction'daki pushNamed başarısız oluyordu (ör. misafir
              // limit balonundaki "Kayıt ol"). '/' BURAYA konmaz — home ile çakışır.
              routes: {
                '/login': (_) => const LoginScreen(),
                '/register': (_) => const RegisterScreen(),
              },
            ),
          );
        },
      ),
    );
  }
}
