import 'dart:io';

class AppConfig {
  // ─── Ortam Seçimi ───
  // true = lokal test (emülatör/localhost), false = production (VDS)
  static const bool isTestMode = false;

  // ─── VDS (Production) ───
  static const String vdsApiUrl = 'https://api2.ogretimsayfam.com';
  static const String vdsWsUrl = 'wss://api2.ogretimsayfam.com';

  // ─── Test (Lokal) ───
  // Android emülatör: 10.0.2.2, iOS sim: localhost, fiziksel cihaz: PC'nin IP'si
  static String get _testHost {
    if (Platform.isAndroid) return '10.0.2.2';
    return 'localhost';
  }

  static String get testApiUrl => 'http://$_testHost:3000';
  static String get testWsUrl => 'ws://$_testHost:3000';

  // ─── Aktif URL'ler ───
  static String get apiUrl => isTestMode ? testApiUrl : vdsApiUrl;
  static String get wsUrl => isTestMode ? testWsUrl : vdsWsUrl;

  // ─── API Endpoints ───
  static const String statusEndpoint = '/api/status';
  static const String conversationsEndpoint = '/api/conversations';
  static const String messagesEndpoint = '/api/messages';
  static const String sessionsEndpoint = '/api/sessions';

  static String conversationMessagesEndpoint(String convId) =>
      '/api/conversations/$convId/messages';
  static String deleteConversationEndpoint(String convId) =>
      '/api/conversations/$convId';
  static String sessionEndpoint(String requestId) =>
      '/api/sessions/$requestId';

  // ─── Auth Endpoints ───
  static const String loginEndpoint = '/api/auth/login';
  static const String registerEndpoint = '/api/auth/register';
  static const String meEndpoint = '/api/auth/me';
  static const String passwordChangeEndpoint = '/api/auth/password';
  static const String deleteAccountEndpoint = '/api/auth/delete-account';

  // ─── Guest Endpoints ───
  static const String guestTokenEndpoint = '/api/guest/token';
  static const String guestMessageEndpoint = '/api/guest/message';

  // ─── User Endpoints ───
  static const String userStatsEndpoint = '/api/user/stats';
  static const String userProfileEndpoint = '/api/user/profile';
  static const String bugReportEndpoint = '/api/reports/bug';

  // ─── WebSocket ───
  static String wsEndpoint(String token) =>
      '/ws?role=user&token=$token';

  // ─── Eski Endpoints (geriye uyum) ───
  static const String uploadEndpoint = '/api/upload';

  // ─── Canvas URL Builder ───
  static String canvasLiveUrl(String requestId, String token, String? imageUrl) {
    final base = Uri.encodeComponent(apiUrl);
    final img = imageUrl != null ? '&imageUrl=${Uri.encodeComponent(imageUrl)}' : '';
    return '$apiUrl/public/canvas.html?mode=live&requestId=$requestId&token=$token&baseUrl=$base$img&fill=1';
  }

  static String canvasReplayUrl(String requestId, String token) {
    final base = Uri.encodeComponent(apiUrl);
    return '$apiUrl/public/canvas.html?mode=replay&requestId=$requestId&token=$token&baseUrl=$base&cizimUrl=$base&fill=1';
  }

  // ─── Timeouts ───
  static const Duration connectionTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration wsReconnectDelay = Duration(seconds: 3);
}
