import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import 'chat/chat_screen.dart';

/// Açılış: yazı-logo soldan sağa "yazılır", altta yayıncı satırı belirir,
/// sonra sohbete geçilir. Elastik zıplama, dönme ve parlama bilerek yok.
///
/// Süre: 0,2 s bekleme + 0,9 s yazım + 0,45 s yayıncı; en erken 1,9 s'de
/// geçiş (kimlik doğrulama daha uzun sürerse onu bekler).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _authReady = false;

  late final AnimationController _controller;
  late final Animation<double> _yazim;   // 0 → 1: soldan sağa açılma
  late final Animation<double> _yayinci; // alt satır opaklığı

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _yazim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.64, curve: Curves.easeInOutCubic),
    );
    _yayinci = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.66, 1.0, curve: Curves.easeOut),
    );
    _startAnimation();
    _checkAuth();
  }

  Future<void> _startAnimation() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _controller.forward();

    await Future.delayed(const Duration(milliseconds: 1700));
    if (!mounted) return;

    while (!_authReady && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!mounted) return;
    _navigateToChatScreen();
  }

  Future<void> _checkAuth() async {
    final authProvider = context.read<AuthProvider>();

    while (authProvider.status == AuthStatus.unknown && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (mounted) {
      _authReady = true;
    }
  }

  void _navigateToChatScreen() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return const ChatScreen();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final azHareket = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: context.bgSecondary,
      body: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _yazim,
              builder: (context, child) {
                final t = azHareket ? 1.0 : _yazim.value;
                return ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: t.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Image.asset(
                context.wordmarkAsset,
                width: 190,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 44 + MediaQuery.of(context).padding.bottom,
            child: FadeTransition(
              opacity: azHareket ? const AlwaysStoppedAnimation(1.0) : _yayinci,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/Ogretimsayfam.png',
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'bir ÖğretimSayfam uygulaması',
                    style: TextStyle(fontSize: 12, color: context.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
