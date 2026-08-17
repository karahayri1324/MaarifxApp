import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';
import '../models/server_notice.dart';

// ─── VDS WebSocket Mesaj Tipleri ───
enum VdsMessageType {
  connected,
  streamToken,
  streamData,
  streamImage,
  streamAudio,
  streamThinking,
  streamThinkingDone,
  requestProcessing,
  requestComplete,
  requestError,
  notice,          // AÇIK UÇLU sunucu bildirimi (kota/ban/duyuru…) — sebep app'te TANIMLI DEĞİL
  ping,
  pong,
  unknown,
}

class VdsMessage {
  final VdsMessageType type;
  final Map<String, dynamic> data;

  VdsMessage({required this.type, required this.data});
}

// ─── VDS API Yanıtları ───
class SendMessageResult {
  final String conversationId;
  final String userMessageId;
  final String aiMessageId;
  final String requestId;
  final String? imagePath;
  final bool processorNotified;

  /// İsteğin GERÇEKTEN hangi modda gönderildiği (sunucudan gelmez, gönderen
  /// doldurur). Ekranın oynatıcıya geçip geçmeyeceği buna bakmalı: global
  /// toggle "çizim açık" dese bile fotoğrafsız mesaj çizimsize düşürülüyor,
  /// bu durumda canvas AÇILMAMALI.
  bool drawOnImageUsed = true;

  SendMessageResult({
    required this.conversationId,
    required this.userMessageId,
    required this.aiMessageId,
    required this.requestId,
    this.imagePath,
    required this.processorNotified,
  });

  factory SendMessageResult.fromJson(Map<String, dynamic> json) {
    return SendMessageResult(
      conversationId: json['conversationId'] as String,
      userMessageId: json['userMessageId'] as String,
      aiMessageId: json['aiMessageId'] as String,
      requestId: json['requestId'] as String,
      imagePath: json['imagePath'] as String?,
      processorNotified: json['processorNotified'] as bool? ?? false,
    );
  }
}

class ConversationSummary {
  final String id;
  final String title;
  final DateTime updatedAt;
  final int messageCount;
  final String? lastMessage;

  ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
    this.lastMessage,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Sohbet',
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      messageCount: json['message_count'] as int? ?? 0,
      lastMessage: json['last_message'] as String?,
    );
  }
}

class VdsMessageData {
  final String id;
  final String conversationId;
  final String type; // 'user' or 'ai'
  final String? text;
  final String? imagePath;
  final String status;
  final String? requestId;
  final String? requestStatus;
  final List<dynamic>? sessionCommands;
  final List<dynamic>? sessionAudioCommands;
  final List<dynamic>? sessionRenderedSteps;
  final int? sessionDuration;
  final String? resultImagePath;
  final bool? drawOnImage; // null = eski kayıt (bilinmiyor), true = çizimli, false = sözel
  final DateTime createdAt;

  VdsMessageData({
    required this.id,
    required this.conversationId,
    required this.type,
    this.text,
    this.imagePath,
    required this.status,
    this.requestId,
    this.requestStatus,
    this.sessionCommands,
    this.sessionAudioCommands,
    this.sessionRenderedSteps,
    this.sessionDuration,
    this.resultImagePath,
    this.drawOnImage,
    required this.createdAt,
  });

  factory VdsMessageData.fromJson(Map<String, dynamic> json) {
    return VdsMessageData(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      type: json['type'] as String,
      text: json['text'] as String?,
      imagePath: json['image_path'] as String?,
      status: json['status'] as String? ?? 'complete',
      requestId: json['request_id'] as String?,
      requestStatus: json['request_status'] as String?,
      sessionCommands: json['session_commands'] != null
          ? (json['session_commands'] is String
              ? jsonDecode(json['session_commands'] as String)
              : json['session_commands'])
          : null,
      sessionAudioCommands: json['session_audio_commands'] != null
          ? (json['session_audio_commands'] is String
              ? jsonDecode(json['session_audio_commands'] as String)
              : json['session_audio_commands'])
          : null,
      sessionRenderedSteps: json['session_rendered_steps'] != null
          ? (json['session_rendered_steps'] is String
              ? jsonDecode(json['session_rendered_steps'] as String)
              : json['session_rendered_steps'])
          : null,
      sessionDuration: json['session_duration'] as int?,
      resultImagePath: json['result_image_path'] as String?,
      drawOnImage: json['draw_on_image'] != null
          ? (json['draw_on_image'] == 1 || json['draw_on_image'] == true)
          : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class SessionData {
  final String requestId;
  final List<dynamic> commands;
  final List<dynamic> audioCommands;
  final List<dynamic> renderedSteps;
  final int duration;
  final String? originalImage;
  final String? resultImage;
  final String? prompt;
  final String? userText;
  final String? aiText;
  final String status;

  /// Session'da çizim/adım verisi var mı?
  bool get hasVisualData =>
      commands.isNotEmpty || audioCommands.isNotEmpty || renderedSteps.isNotEmpty;

  SessionData({
    required this.requestId,
    required this.commands,
    required this.audioCommands,
    required this.renderedSteps,
    required this.duration,
    this.originalImage,
    this.resultImage,
    this.prompt,
    this.userText,
    this.aiText,
    required this.status,
  });

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      requestId: json['requestId'] as String,
      commands: json['commands'] as List<dynamic>? ?? [],
      audioCommands: json['audioCommands'] as List<dynamic>? ?? [],
      renderedSteps: json['renderedSteps'] as List<dynamic>? ?? [],
      duration: json['duration'] as int? ?? 0,
      originalImage: json['originalImage'] as String?,
      resultImage: json['resultImage'] as String?,
      prompt: json['prompt'] as String?,
      userText: json['userText'] as String?,
      aiText: json['aiText'] as String?,
      status: json['status'] as String? ?? 'unknown',
    );
  }
}

// ─── Rate Limit Exception ───
class RateLimitException implements Exception {
  final String message;
  final int used;
  final int limit;
  final String type; // 'guest', 'user', 'organization'

  RateLimitException({
    required this.message,
    required this.used,
    required this.limit,
    required this.type,
  });
}

// ─── Sohbet Modu Kilidi (HTTP 409) ───
/// Sohbetin modu (çizimli/çizimsiz) ilk istekte kilitlenir; karşıt modda
/// gönderim sunucu tarafından reddedilir.
class ConversationModeLockedException implements Exception {
  final String message;
  final bool conversationMode; // true = sohbet çizimli, false = çizimsiz

  ConversationModeLockedException({
    required this.message,
    required this.conversationMode,
  });
}

// ─── VDS Service ───
class VdsService {
  String? _authToken;
  String? _userId;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isDisposed = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempt = 0;

  final _messageController = StreamController<VdsMessage>.broadcast();
  Stream<VdsMessage> get messageStream => _messageController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => _isConnected;

  // ─── Auth ───

  void setAuth(String token, String userId) {
    _authToken = token;
    _userId = userId;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${_authToken ?? ''}',
        'Content-Type': 'application/json',
      };

  String get _baseUrl => AppConfig.apiUrl;

  // ─── HTTP API ───

  /// Sunucu durumunu kontrol et
  Future<Map<String, dynamic>?> checkStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl${AppConfig.statusEndpoint}'),
      ).timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Mesaj gönder (fotoğraf + metin)
  Future<SendMessageResult?> sendMessage({
    File? imageFile,
    String? text,
    String? conversationId,
    int detailLevel = 3,
    String? classLevel,
    String? studentName,
    bool drawOnImage = true,
    bool enableThinking = true,
    String model = '3.0',
    int? samimiyet,
    String? studentIntro,
    List<int>? markedRegion,
    String? hintRef,
    String? studentQuestion,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl${AppConfig.messagesEndpoint}');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer ${_authToken ?? ''}';

      if (text != null && text.isNotEmpty) {
        request.fields['text'] = text;
      }
      if (conversationId != null) {
        request.fields['conversationId'] = conversationId;
      }
      request.fields['detailLevel'] = detailLevel.toString();
      request.fields['drawOnImage'] = drawOnImage.toString();
      request.fields['enableThinking'] = enableThinking.toString();
      request.fields['model'] = model;
      if (classLevel != null) {
        request.fields['classLevel'] = classLevel;
      }
      if (studentName != null && studentName.isNotEmpty) {
        request.fields['studentName'] = studentName;
      }
      // Etkileşim alanları: samimiyet, kendini-tanıt, işaretli bölge, Hint yanıtı.
      if (samimiyet != null) {
        request.fields['samimiyet'] = samimiyet.toString();
      }
      if (studentIntro != null && studentIntro.isNotEmpty) {
        request.fields['studentIntro'] = studentIntro;
      }
      if (markedRegion != null && markedRegion.length == 4) {
        request.fields['markedRegion'] = jsonEncode(markedRegion);
      }
      if (hintRef != null && hintRef.isNotEmpty) {
        request.fields['hintRef'] = hintRef;
      }
      // İşaretli bölge takip notu → sunucu studentQuestion → <ogrenci_sorusu>
      if (studentQuestion != null && studentQuestion.isNotEmpty) {
        request.fields['studentQuestion'] = studentQuestion;
      }

      if (imageFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', imageFile.path),
        );
      }

      final streamedResponse = await request.send().timeout(
            AppConfig.receiveTimeout,
          );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SendMessageResult.fromJson(data);
      }
      // Bildirim varsa O kazanır (sunucunun yazdığı serbest metin); yoksa
      // aşağıdaki eski rate-limit yolu çalışır — geriye dönük uyumlu.
      _throwIfNotice(response);
      if (response.statusCode == 429) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rl = data['rateLimit'] as Map<String, dynamic>? ?? {};
        throw RateLimitException(
          message: data['error'] as String? ?? 'Rate limit aşıldı',
          used: rl['used'] as int? ?? 0,
          limit: rl['limit'] as int? ?? 0,
          type: rl['type'] as String? ?? 'user',
        );
      }
      _throwIfConvModeLocked(response);
      return null;
    } catch (e) {
      // KRİTİK: tipli istisnalar buradan geçmeli, yoksa null'a düşüp generic
      // "Mesaj gönderilemedi" hatasına dönüşürler.
      if (e is ServerNoticeException) rethrow;
      if (e is RateLimitException) rethrow;
      if (e is ConversationModeLockedException) rethrow;
      return null;
    }
  }

  /// AÇIK UÇLU BİLDİRİM KAPISI. Sunucu HERHANGİ bir durum kodunda govdeye
  /// `notice` koyduysa onu fırlat — uygulama sebebi bilmez, mesajı gösterir.
  /// Yeni senaryolar (okul banı, bakım, duyuru…) app güncellemesi gerektirmez.
  void _throwIfNotice(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    ServerNotice? notice;
    try {
      notice = ServerNotice.fromBody(jsonDecode(response.body));
    } catch (_) {
      notice = null;   // govde JSON değil → çağıran eski yoluna devam etsin
    }
    if (notice != null) {
      throw ServerNoticeException(notice, statusCode: response.statusCode);
    }
  }

  /// 409 CONV_MODE_LOCKED → tipli istisna (sohbet modu kilidi).
  void _throwIfConvModeLocked(http.Response response) {
    if (response.statusCode != 409) return;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] != 'CONV_MODE_LOCKED') return;
    throw ConversationModeLockedException(
      message: data['error'] as String? ?? 'Bu sohbetin modu değiştirilemez.',
      conversationMode: data['conversationMode'] == true,
    );
  }

  /// Sohbetleri listele (pagination destekli)
  Future<({List<ConversationSummary> conversations, int total})> getConversations({int limit = 0, int offset = 0}) async {
    try {
      final queryParams = <String, String>{};
      if (limit > 0) {
        queryParams['limit'] = limit.toString();
        queryParams['offset'] = offset.toString();
      }
      final uri = Uri.parse('$_baseUrl${AppConfig.conversationsEndpoint}')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(
        uri,
        headers: _headers,
      ).timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final conversations = (data['conversations'] as List<dynamic>)
            .map((c) => ConversationSummary.fromJson(c as Map<String, dynamic>))
            .toList();
        final total = data['total'] as int? ?? conversations.length;
        return (conversations: conversations, total: total);
      }
      return (conversations: <ConversationSummary>[], total: 0);
    } catch (e) {
      return (conversations: <ConversationSummary>[], total: 0);
    }
  }

  /// Sohbet mesajlarını getir.
  /// [mode]: sohbetin kalıcı modu (çizimli/çizimsiz) — null = kilitsiz
  /// (kayıt yok, legacy satır, ya da alanı henüz göndermeyen eski sunucu).
  /// Bu alan SUNUCUDAN gelir; per-mesaj draw_on_image'dan türetilmemeli
  /// (hint-devam turları gizleniyor, quiz cevapları çizimli sohbette 0 taşıyor).
  Future<({List<VdsMessageData> messages, bool? mode})> getConversationMessages(
      String conversationId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl${AppConfig.conversationMessagesEndpoint(conversationId)}'),
        headers: _headers,
      ).timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final messages = data['messages'] as List<dynamic>;
        return (
          messages: messages
              .map((m) => VdsMessageData.fromJson(m as Map<String, dynamic>))
              .toList(),
          mode: data['conversationMode'] as bool?,
        );
      }
      return (messages: <VdsMessageData>[], mode: null);
    } catch (e) {
      return (messages: <VdsMessageData>[], mode: null);
    }
  }

  /// Sohbeti sil
  Future<bool> deleteConversation(String conversationId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl${AppConfig.deleteConversationEndpoint(conversationId)}'),
        headers: _headers,
      ).timeout(AppConfig.connectionTimeout);

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Oturum verisini getir (replay için)
  Future<SessionData?> getSessionData(String requestId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl${AppConfig.sessionEndpoint(requestId)}'),
        headers: _headers,
      ).timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SessionData.fromJson(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Görüntü URL'si oluştur
  String getImageUrl(String imagePath) {
    if (imagePath.startsWith('http')) return imagePath;
    return '$_baseUrl$imagePath';
  }

  // ─── User Profile & Settings ───

  /// Şifre değiştir
  Future<Map<String, dynamic>> changePassword(String currentPassword, String newPassword) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl${AppConfig.passwordChangeEndpoint}'),
        headers: _headers,
        body: jsonEncode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      ).timeout(AppConfig.connectionTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? data['error'] ?? '',
      };
    } on SocketException catch (_) {
      return {'success': false, 'message': 'İnternet bağlantısı bulunamadı. Bağlantınızı kontrol edin.'};
    } on TimeoutException catch (_) {
      return {'success': false, 'message': 'İstek zaman aşımına uğradı. Lütfen tekrar deneyin.'};
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası oluştu. Lütfen tekrar deneyin.'};
    }
  }

  /// Kullanıcı istatistikleri
  Future<Map<String, dynamic>?> getUserStats() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl${AppConfig.userStatsEndpoint}'),
        headers: _headers,
      ).timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Profil güncelle (sınıf seviyesi)
  /// Profil güncelle. Yalnız VERİLEN alanlar gönderilir — biri güncellenirken
  /// diğerleri yanlışlıkla null'lanmasın.
  Future<bool> updateProfile({String? classLevel, String? displayName, String? studentIntro}) async {
    try {
      final govde = <String, dynamic>{};
      if (classLevel != null) govde['classLevel'] = classLevel;
      if (displayName != null) govde['displayName'] = displayName;
      if (studentIntro != null) govde['studentIntro'] = studentIntro;
      if (govde.isEmpty) return true;

      final response = await http.put(
        Uri.parse('$_baseUrl${AppConfig.userProfileEndpoint}'),
        headers: _headers,
        body: jsonEncode(govde),
      ).timeout(AppConfig.connectionTimeout);

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Profil oku (sınıf, ad, tanıtım metni). Tanıtım SUNUCUDA saklanır; cihaz
  /// değiştiren öğrenci ayarlar ekranını boş bulmasın diye buradan çekilir.
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl${AppConfig.userProfileEndpoint}'),
        headers: _headers,
      ).timeout(AppConfig.connectionTimeout);
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Sunucu tarafı özellik bayrakları (uzaktan aç/kapa).
  /// Şu an: samimiyet4Enabled (okul/kullanıcı bazında "Çok samimi" kilidi),
  /// model.maxEnabled + MAX kotası. Okunamazsa null → çağıran güvenli
  /// varsayılanında kalır (özelliği yok saymaz, gizlemez).
  Future<Map<String, dynamic>?> getAppConfig() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/app-config'),
        headers: _headers,
      ).timeout(AppConfig.connectionTimeout);
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Hesabi sil
  Future<Map<String, dynamic>> deleteAccount() async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl${AppConfig.deleteAccountEndpoint}'),
        headers: _headers,
      ).timeout(AppConfig.connectionTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? data['error'] ?? '',
      };
    } catch (e) {
      return {'success': false, 'message': 'Hesap silme sırasında hata oluştu.'};
    }
  }

  /// Misafir mesaj gonder
  Future<SendMessageResult?> sendGuestMessage({
    String? deviceId,
    File? imageFile,
    String? text,
    String? conversationId,
    int detailLevel = 3,
    String? classLevel,
    String? studentName,
    bool drawOnImage = true,
    bool enableThinking = true,
    String model = '3.0',
    int? samimiyet,
    String? studentIntro,
    List<int>? markedRegion,
    String? hintRef,
    String? studentQuestion,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl${AppConfig.guestMessageEndpoint}');
      final request = http.MultipartRequest('POST', uri);

      if (deviceId != null) {
        request.headers['x-device-id'] = deviceId;
      }

      if (text != null && text.isNotEmpty) {
        request.fields['text'] = text;
      }
      if (conversationId != null) {
        request.fields['conversationId'] = conversationId;
      }
      request.fields['detailLevel'] = detailLevel.toString();
      request.fields['drawOnImage'] = drawOnImage.toString();
      request.fields['enableThinking'] = enableThinking.toString();
      request.fields['model'] = model;
      if (classLevel != null) {
        request.fields['classLevel'] = classLevel;
      }
      if (studentName != null && studentName.isNotEmpty) {
        request.fields['studentName'] = studentName;
      }
      if (samimiyet != null) {
        request.fields['samimiyet'] = samimiyet.toString();
      }
      if (studentIntro != null && studentIntro.isNotEmpty) {
        request.fields['studentIntro'] = studentIntro;
      }
      if (markedRegion != null && markedRegion.length == 4) {
        request.fields['markedRegion'] = jsonEncode(markedRegion);
      }
      if (hintRef != null && hintRef.isNotEmpty) {
        request.fields['hintRef'] = hintRef;
      }
      // İşaretli bölge takip notu → sunucu studentQuestion → <ogrenci_sorusu>
      if (studentQuestion != null && studentQuestion.isNotEmpty) {
        request.fields['studentQuestion'] = studentQuestion;
      }

      if (imageFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', imageFile.path),
        );
      }

      final streamedResponse = await request.send().timeout(
            AppConfig.receiveTimeout,
          );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SendMessageResult.fromJson(data);
      }
      // Bildirim varsa O kazanır (sunucunun yazdığı serbest metin); yoksa
      // aşağıdaki eski rate-limit yolu çalışır — geriye dönük uyumlu.
      _throwIfNotice(response);
      if (response.statusCode == 429) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rl = data['rateLimit'] as Map<String, dynamic>? ?? {};
        throw RateLimitException(
          message: data['error'] as String? ?? 'Rate limit aşıldı',
          used: rl['used'] as int? ?? 0,
          limit: rl['limit'] as int? ?? 0,
          type: rl['type'] as String? ?? 'guest',
        );
      }
      _throwIfConvModeLocked(response);
      return null;
    } catch (e) {
      if (e is ServerNoticeException) rethrow;
      if (e is RateLimitException) rethrow;
      if (e is ConversationModeLockedException) rethrow;
      return null;
    }
  }

  /// Hata raporu gönder
  Future<bool> submitBugReport(String message) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl${AppConfig.bugReportEndpoint}'),
        headers: _headers,
        body: jsonEncode({'message': message}),
      ).timeout(AppConfig.connectionTimeout);

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ─── WebSocket ───

  void connectWebSocket() {
    if (_isDisposed || _authToken == null) return;

    // Eski kanal varsa önce kapat — çift bağlantı ve leak önlenir.
    // _channel'ı ÖNCE null'a çekiyoruz ki eski kanalın onDone'u
    // (aşağıdaki identity guard sayesinde) reconnect tetiklemesin.
    final old = _channel;
    if (old != null) {
      _channel = null;
      try {
        old.sink.close();
      } catch (_) {
        // ignore
      }
    }

    final wsUrl = '${AppConfig.wsUrl}${AppConfig.wsEndpoint(_authToken!)}';

    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = channel;

      channel.stream.listen(
        (message) {
          if (_channel != channel) return; // stale kanal — yok say
          if (!_isConnected) {
            _isConnected = true;
            _reconnectAttempt = 0;
            _connectionController.add(true);
            _startPingTimer();
          }
          _handleMessage(message);
        },
        onError: (error) {
          if (_channel == channel) _handleDisconnect();
        },
        onDone: () {
          if (_channel == channel) _handleDisconnect();
        },
      );

      // Bağlantı bekleme
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_channel == channel && !_isConnected && !_isDisposed) {
          _isConnected = true;
          _connectionController.add(true);
          _startPingTimer();
        }
      });
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final data = jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final typeStr = data['type'] as String? ?? '';
      final type = _parseMessageType(typeStr);
      _messageController.add(VdsMessage(type: type, data: data));
    } catch (e) {
      // ignore
    }
  }

  VdsMessageType _parseMessageType(String type) {
    switch (type) {
      case 'connected':
        return VdsMessageType.connected;
      case 'stream_token':
        return VdsMessageType.streamToken;
      case 'stream_data':
        return VdsMessageType.streamData;
      case 'stream_image':
        return VdsMessageType.streamImage;
      case 'stream_audio':
        return VdsMessageType.streamAudio;
      case 'stream_thinking':
        return VdsMessageType.streamThinking;
      case 'stream_thinking_done':
        return VdsMessageType.streamThinkingDone;
      case 'request_processing':
        return VdsMessageType.requestProcessing;
      case 'request_complete':
        return VdsMessageType.requestComplete;
      case 'request_error':
        return VdsMessageType.requestError;
      case 'notice':
        return VdsMessageType.notice;
      case 'ping':
        return VdsMessageType.ping;
      case 'pong':
        return VdsMessageType.pong;
      default:
        return VdsMessageType.unknown;
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _connectionController.add(false);
    _stopPingTimer();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    final delay = _getReconnectDelay();
    _reconnectTimer = Timer(delay, () {
      if (!_isDisposed && !_isConnected) {
        connectWebSocket();
      }
    });
  }

  /// İlk 5 deneme 3s, sonra 5s → 12s → 30s → 60s (max)
  Duration _getReconnectDelay() {
    if (_reconnectAttempt <= 5) return const Duration(seconds: 3);
    // exp clamp: çok uzun kopukluklarda pow() sonucu int64'ü aşıp
    // round()'un patlamasını önler (sonuç zaten 60'a clamp'leniyor)
    final exp = (_reconnectAttempt - 6).clamp(0, 8);
    final seconds = (5 * math.pow(2.5, exp)).round().clamp(5, 60);
    return Duration(seconds: seconds);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendPing();
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _sendPing() {
    if (!_isConnected) return;
    try {
      _channel?.sink.add(jsonEncode({'type': 'ping'}));
    } catch (e) {
      // ignore
    }
  }

  void disconnectWebSocket() {
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _reconnectAttempt = 0;
  }

  void dispose() {
    _isDisposed = true;
    disconnectWebSocket();
    _messageController.close();
    _connectionController.close();
  }
}
