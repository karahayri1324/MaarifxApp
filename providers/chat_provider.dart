import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../services/vds_service.dart';

class ChatProvider extends ChangeNotifier {
  final VdsService _vdsService;

  List<ChatMessage> messages = [];
  final Set<String> _activeRequests = {};
  bool isConnected = false;
  bool _serverReachable = true;
  bool _hasInternet = true;

  // true if any request is active
  bool get isProcessing => _activeRequests.isNotEmpty;

  // Settings
  int _detailLevel = 3;
  bool _showStepData = false;
  bool _drawOnImage = true;
  bool _enableThinking = true;

  // Conversation
  String? _currentConversationId;
  String? _userId;
  String? _displayName;
  bool _isGuest = false;
  String? _deviceId;

  // Retry data: errorMessageId -> {imageFile, prompt, classLevel}
  final Map<String, _RetryData> _retryData = {};

  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;

  int get detailLevel => _detailLevel;
  bool get showStepData => _showStepData;
  bool get drawOnImage => _drawOnImage;
  bool get enableThinking => _enableThinking;
  bool get serverReachable => _serverReachable;
  bool get hasInternet => _hasInternet;
  String? get currentConversationId => _currentConversationId;
  VdsService get vdsService => _vdsService;

  ChatProvider({
    VdsService? vdsService,
  }) : _vdsService = vdsService ?? VdsService() {
    _loadSettings();
  }

  void setAuth(String? userId, String? token, {bool isGuest = false, String? deviceId, String? displayName}) {
    _userId = userId;
    _isGuest = isGuest;
    _deviceId = deviceId;
    _displayName = displayName;

    if (userId != null && token != null) {
      _vdsService.setAuth(token, userId);
      _connectWebSocket();
    }
  }

  void _connectWebSocket() {
    _connectionSubscription?.cancel();
    _messageSubscription?.cancel();

    _connectionSubscription = _vdsService.connectionStream.listen((connected) {
      isConnected = connected;
      notifyListeners();
    });

    _messageSubscription = _vdsService.messageStream.listen(_handleVdsMessage);
    _vdsService.connectWebSocket();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _detailLevel = prefs.getInt('detailLevel') ?? 3;
    _showStepData = prefs.getBool('showStepData') ?? false;
    _drawOnImage = prefs.getBool('drawOnImage') ?? true;
    _enableThinking = prefs.getBool('enableThinking') ?? true;
    notifyListeners();
  }

  Future<void> setDetailLevel(int level) async {
    _detailLevel = level.clamp(1, 5);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('detailLevel', _detailLevel);
    notifyListeners();
  }

  Future<void> setShowStepData(bool value) async {
    _showStepData = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showStepData', _showStepData);
    notifyListeners();
  }

  Future<void> setDrawOnImage(bool value) async {
    _drawOnImage = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drawOnImage', _drawOnImage);
    notifyListeners();
  }

  Future<void> setEnableThinking(bool value) async {
    _enableThinking = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enableThinking', _enableThinking);
    notifyListeners();
  }

  // ─── Helper: requestId ile AI mesajını bul ───

  int _findAiMsgIndex(String? requestId) {
    if (requestId == null) return -1;
    return messages.indexWhere(
      (m) => m.requestId == requestId && m.type == MessageType.ai,
    );
  }

  // ─── VDS WebSocket Mesaj İşleme ───

  void _handleVdsMessage(VdsMessage msg) {
    switch (msg.type) {
      case VdsMessageType.streamToken:
        _handleStreamToken(msg.data);
        break;
      case VdsMessageType.streamData:
        _handleStreamData(msg.data);
        break;
      case VdsMessageType.streamImage:
        _handleStreamImage(msg.data);
        break;
      case VdsMessageType.streamAudio:
        _handleStreamAudio(msg.data);
        break;
      case VdsMessageType.streamThinking:
        _handleStreamThinking(msg.data);
        break;
      case VdsMessageType.streamThinkingDone:
        _handleStreamThinkingDone(msg.data);
        break;
      case VdsMessageType.requestProcessing:
        break;
      case VdsMessageType.requestComplete:
        _handleRequestComplete(msg.data);
        break;
      case VdsMessageType.requestError:
        _handleRequestError(msg.data);
        break;
      default:
        break;
    }
  }

  void _handleStreamToken(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (requestId == null || !_activeRequests.contains(requestId)) return;

    // Direct chat modunda tokenleri canli goster
    final msgIndex = _findAiMsgIndex(requestId);
    if (msgIndex == -1) return;
    if (!messages[msgIndex].isDirectChat) return;

    final token = data['token'] as String? ?? '';
    messages[msgIndex].text += token;
    notifyListeners();
  }

  void _handleStreamThinking(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (requestId == null || !_activeRequests.contains(requestId)) return;

    final msgIndex = _findAiMsgIndex(requestId);
    if (msgIndex == -1) return;
    if (!messages[msgIndex].isDirectChat) return;

    final token = data['token'] as String? ?? '';
    messages[msgIndex].thinkingText += token;
    notifyListeners();
  }

  void _handleStreamThinkingDone(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (requestId == null || !_activeRequests.contains(requestId)) return;

    final msgIndex = _findAiMsgIndex(requestId);
    if (msgIndex == -1) return;
    if (!messages[msgIndex].isDirectChat) return;

    messages[msgIndex].thinkingDone = true;
    notifyListeners();
  }

  void _handleStreamData(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (requestId == null || !_activeRequests.contains(requestId)) return;

    final streamData = data['data'] as Map<String, dynamic>? ?? {};
    final msgIndex = _findAiMsgIndex(requestId);
    if (msgIndex == -1) return;

    if (streamData.containsKey('command')) {
      messages[msgIndex].sessionCommands ??= [];
      messages[msgIndex].sessionCommands!.add(streamData['command']);
      messages[msgIndex].hasSessionData = true;
    }
    if (streamData.containsKey('audioCommand')) {
      messages[msgIndex].sessionAudioCommands ??= [];
      messages[msgIndex].sessionAudioCommands!.add(streamData['audioCommand']);
    }
    if (streamData.containsKey('renderedStep')) {
      messages[msgIndex].hasSessionData = true;
    }
    notifyListeners();
  }

  void _handleStreamAudio(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (requestId == null || !_activeRequests.contains(requestId)) return;

    final msgIndex = _findAiMsgIndex(requestId);
    if (msgIndex != -1) {
      messages[msgIndex].hasSessionData = true;
    }
  }

  void _handleStreamImage(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (requestId == null || !_activeRequests.contains(requestId)) return;

    final imageBase64 = data['imageBase64'] as String?;
    final step = data['step'] as int?;
    final totalSteps = data['totalSteps'] as int?;

    if (imageBase64 == null) return;

    final msgIndex = _findAiMsgIndex(requestId);
    if (msgIndex == -1) return;

    messages[msgIndex].imageBase64 = imageBase64;

    if (step != null && totalSteps != null) {
      while (messages[msgIndex].stepImages.length <= step) {
        messages[msgIndex].stepImages.add('');
      }
      messages[msgIndex].stepImages[step] = imageBase64;
      messages[msgIndex].hasSteps = totalSteps > 1;
      messages[msgIndex].totalSteps = totalSteps;
      messages[msgIndex].currentStep = step;
    }

    notifyListeners();
  }

  void _handleRequestComplete(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (requestId == null) return;

    _activeRequests.remove(requestId);

    final msgIndex = _findAiMsgIndex(requestId);
    if (msgIndex != -1) {
      final resultText = data['resultText'] as String?;
      if (resultText != null && resultText.isNotEmpty) {
        messages[msgIndex].text = resultText;
      }
      messages[msgIndex].status = MessageStatus.complete;
      // hasSessionData yalnızca stream sırasında session verisi (command/audio/renderedStep) geldiyse true olur
      // Burada tekrar true yapmıyoruz — metin cevaplarında yanlışlıkla "Çözümü İzle" butonu çıkmasın
      messages[msgIndex].sessionDuration = data['duration'] as int?;
    }

    notifyListeners();
  }

  void _handleRequestError(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (requestId == null) return;

    _activeRequests.remove(requestId);

    final msgIndex = _findAiMsgIndex(requestId);
    if (msgIndex != -1) {
      final error = data['error'] as String? ?? 'Bilinmeyen hata';
      final userFriendlyError = _getUserFriendlyError(error);
      messages[msgIndex].text = userFriendlyError;
      messages[msgIndex].status = MessageStatus.error;
    }

    notifyListeners();
  }

  String _getUserFriendlyError(String error) {
    final lowerError = error.toLowerCase();
    if (lowerError.contains('timeout') || lowerError.contains('zaman asimi')) {
      return 'İstek zaman aşımına uğradı. Sunucu yanıtlamadı, lütfen tekrar deneyin.';
    }
    if (lowerError.contains('processor') || lowerError.contains('worker')) {
      return 'İşlemci şu anda meşgul veya çevrimdışı. Lütfen birkaç dakika sonra tekrar deneyin.';
    }
    if (lowerError.contains('image') || lowerError.contains('gorsel')) {
      return 'Görsel işleme sırasında hata oluştu. Lütfen farklı bir görsel deneyin.';
    }
    if (lowerError.contains('rate') || lowerError.contains('limit')) {
      return 'Çok fazla istek gönderdiniz. Lütfen biraz bekleyip tekrar deneyin.';
    }
    return 'Bir hata oluştu: $error. Lütfen tekrar deneyin.';
  }

  String _getRateLimitMessage(RateLimitException e) {
    if (e.type == 'guest') {
      return 'Günlük misafir kullanım hakkınız doldu (${e.used}/${e.limit}). '
          'Kayıt olarak daha fazla soru sorabilirsiniz.';
    }
    if (e.type == 'organization') {
      return 'Günlük kurum kullanım limitinize ulaştınız (${e.used}/${e.limit} istek). '
          'Limitiniz gece 00:00\'da sıfırlanacak.';
    }
    return 'Günlük kullanım limitinize ulaştınız (${e.used}/${e.limit} istek). '
        'Limitiniz gece 00:00\'da sıfırlanacak. '
        'Bir kuruma bağlı hesaplar daha yüksek limite sahiptir.';
  }

  // ─── WebSocket Reconnect (App Lifecycle) ───

  void reconnectIfNeeded() {
    if (!_vdsService.isConnected && _userId != null) {
      _vdsService.disconnectWebSocket();
      _vdsService.connectWebSocket();
    }
  }

  // ─── Sunucu Bağlantısı ───

  Future<bool> checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      _hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      _hasInternet = false;
    } on TimeoutException catch (_) {
      _hasInternet = false;
    } catch (_) {
      _hasInternet = false;
    }
    notifyListeners();
    return _hasInternet;
  }

  Future<void> checkServerConnection() async {
    final hasNet = await checkInternetConnection();
    if (!hasNet) {
      _serverReachable = false;
      notifyListeners();
      return;
    }
    final status = await _vdsService.checkStatus();
    _serverReachable = status != null;
    notifyListeners();
  }

  // ─── Mesaj Gönderme (çoklu request destekli) ───

  Future<SendMessageResult?> sendMessage({
    File? imageFile,
    String? prompt,
    String? classLevel,
  }) async {
    // Coklu request: bloklama yok

    // Check internet first
    final hasNet = await checkInternetConnection();
    if (!hasNet) {
      _serverReachable = false;
      _addErrorMessage(
          'İnternet bağlantısı bulunamadı. Lütfen Wi-Fi veya mobil veri bağlantınızı kontrol edip tekrar deneyin.',
          imageFile: imageFile, prompt: prompt, classLevel: classLevel);
      notifyListeners();
      return null;
    }

    final status = await _vdsService.checkStatus();
    if (status == null) {
      _serverReachable = false;
      _addErrorMessage(
          'Sunucuya ulaşılamıyor. Sunucu bakım altında olabilir, lütfen birkaç dakika sonra tekrar deneyin.',
          imageFile: imageFile, prompt: prompt, classLevel: classLevel);
      notifyListeners();
      return null;
    }
    _serverReachable = true;

    notifyListeners();

    String? imageBase64ForDisplay;
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      imageBase64ForDisplay = base64Encode(bytes);
    }

    // VDS'ye mesaj gönder (guest veya normal)
    SendMessageResult? result;
    try {
      if (_isGuest && _deviceId != null) {
        result = await _vdsService.sendGuestMessage(
          deviceId: _deviceId,
          imageFile: imageFile,
          text: prompt,
          conversationId: _currentConversationId,
          detailLevel: _detailLevel,
          classLevel: classLevel,
          studentName: _displayName,
          drawOnImage: _drawOnImage,
          enableThinking: _enableThinking,
        );
      } else {
        result = await _vdsService.sendMessage(
          imageFile: imageFile,
          text: prompt,
          conversationId: _currentConversationId,
          detailLevel: _detailLevel,
          classLevel: classLevel,
          studentName: _displayName,
          drawOnImage: _drawOnImage,
          enableThinking: _enableThinking,
        );
      }
    } on RateLimitException catch (e) {
      _addErrorMessage(_getRateLimitMessage(e),
          imageFile: imageFile, prompt: prompt, classLevel: classLevel);
      notifyListeners();
      return null;
    }

    if (result == null) {
      _addErrorMessage(
          'Mesaj gönderilemedi. Bağlantınızı kontrol edip tekrar deneyin.',
          imageFile: imageFile, prompt: prompt, classLevel: classLevel);
      notifyListeners();
      return null;
    }

    _currentConversationId = result.conversationId;
    _activeRequests.add(result.requestId);

    messages.add(ChatMessage(
      id: result.userMessageId,
      type: MessageType.user,
      text: prompt ?? '',
      imageBase64: imageBase64ForDisplay,
      status: MessageStatus.complete,
      requestId: result.requestId,
      conversationId: result.conversationId,
    ));

    messages.add(ChatMessage(
      id: result.aiMessageId,
      type: MessageType.ai,
      text: '',
      status: MessageStatus.streaming,
      requestId: result.requestId,
      conversationId: result.conversationId,
      isDirectChat: !_drawOnImage,
    ));

    if (!result.processorNotified) {
      final msgIndex = _findAiMsgIndex(result.requestId);
      if (msgIndex != -1) {
        messages[msgIndex].text = 'İşlemci bekliyor... İstek kuyruğa eklendi.';
      }
    }

    notifyListeners();
    return result;
  }

  void _addErrorMessage(String error, {File? imageFile, String? prompt, String? classLevel}) {
    final errorId = DateTime.now().millisecondsSinceEpoch.toString();
    messages.add(ChatMessage(
      id: errorId,
      type: MessageType.ai,
      text: 'Hata: $error',
      status: MessageStatus.error,
    ));
    if (imageFile != null || prompt != null) {
      _retryData[errorId] = _RetryData(
        imageFile: imageFile,
        prompt: prompt,
        classLevel: classLevel,
      );
    }
  }

  /// Hatalı mesajı tekrar gönderir
  bool canRetry(String messageId) => _retryData.containsKey(messageId);

  Future<SendMessageResult?> retryMessage(String errorMessageId) async {
    final data = _retryData.remove(errorMessageId);
    if (data == null) return null;

    // Hatalı mesajı listeden kaldır
    messages.removeWhere((m) => m.id == errorMessageId);
    notifyListeners();

    return sendMessage(
      imageFile: data.imageFile,
      prompt: data.prompt,
      classLevel: data.classLevel,
    );
  }

  // ─── Adım Navigasyonu ───

  void navigateToStep(String messageId, int step) {
    final msgIndex = messages.indexWhere((m) => m.id == messageId);
    if (msgIndex == -1) return;

    final msg = messages[msgIndex];
    if (step < 0 || step >= msg.stepImages.length) return;

    msg.currentStep = step;
    msg.imageBase64 =
        _showStepData ? msg.stepOnlyImages[step] : msg.stepImages[step];

    notifyListeners();
  }

  // ─── Sohbet Geçmişi ───

  Future<({List<ConversationSummary> conversations, int total})> getConversations({int limit = 0, int offset = 0}) async {
    return await _vdsService.getConversations(limit: limit, offset: offset);
  }

  Future<void> loadConversation(String conversationId) async {
    final vdsMessages = await _vdsService.getConversationMessages(conversationId);
    if (vdsMessages.isEmpty) return;

    clearChat();
    _currentConversationId = conversationId;

    for (final vdsMsg in vdsMessages) {
      final type = vdsMsg.type == 'user' ? MessageType.user : MessageType.ai;

      String? imageUrl;
      if (vdsMsg.imagePath != null && vdsMsg.imagePath!.isNotEmpty) {
        imageUrl = _vdsService.getImageUrl(vdsMsg.imagePath!);
      }

      // hasSessionData: true if session commands, audio commands, or rendered steps exist
      final hasSession = (vdsMsg.sessionCommands != null &&
              (vdsMsg.sessionCommands as List).isNotEmpty) ||
          (vdsMsg.sessionAudioCommands != null &&
              (vdsMsg.sessionAudioCommands as List).isNotEmpty) ||
          (vdsMsg.sessionRenderedSteps != null &&
              (vdsMsg.sessionRenderedSteps as List).isNotEmpty);

      // drawOnImage: null = eski kayıt (bilinmiyor), false = sözel, true = çizimli
      // Eski kayıtlar (drawOnImage null): hasSession varsa çizimli say, yoksa sözel say
      final isDirectChat = vdsMsg.drawOnImage == false ||
          (vdsMsg.drawOnImage == null && !hasSession && type == MessageType.ai &&
              (vdsMsg.text ?? '').isNotEmpty);

      messages.add(ChatMessage(
        id: vdsMsg.id,
        type: type,
        text: vdsMsg.text ?? '',
        imageUrl: imageUrl,
        status: MessageStatus.complete,
        requestId: vdsMsg.requestId,
        conversationId: conversationId,
        hasSessionData: hasSession && vdsMsg.requestId != null,
        sessionCommands: vdsMsg.sessionCommands,
        sessionAudioCommands: vdsMsg.sessionAudioCommands,
        sessionDuration: vdsMsg.sessionDuration,
        isDirectChat: isDirectChat,
        thinkingDone: true,
      ));
    }

    notifyListeners();
  }

  Future<bool> deleteConversation(String conversationId) async {
    final success = await _vdsService.deleteConversation(conversationId);
    if (success && _currentConversationId == conversationId) {
      clearChat();
    }
    return success;
  }

  // ─── Replay (Tekrar İzleme) ───

  Future<SessionData?> getSessionData(String requestId) async {
    return await _vdsService.getSessionData(requestId);
  }

  /// PlayerScreen'den donunce cagirilir.
  /// request_complete WS mesaji kacirildiysa, sunucudan kontrol eder.
  Future<void> ensureRequestFinalized(String requestId) async {
    final msgIndex = messages.indexWhere(
      (m) => m.requestId == requestId && m.type == MessageType.ai,
    );
    if (msgIndex == -1) return;

    // Zaten tamamlandiysa bir sey yapma
    if (messages[msgIndex].status == MessageStatus.complete &&
        messages[msgIndex].hasSessionData) {
      return;
    }

    // Sunucudan session verisini kontrol et
    final session = await _vdsService.getSessionData(requestId);
    if (session != null && session.status == 'complete') {
      messages[msgIndex].status = MessageStatus.complete;
      messages[msgIndex].hasSessionData = session.hasVisualData;
      messages[msgIndex].sessionDuration = session.duration;
      _activeRequests.remove(requestId);
      notifyListeners();
    }
  }

  // ─── Temizleme ───

  void clearChat() {
    messages.clear();
    _activeRequests.clear();
    _retryData.clear();
    _currentConversationId = null;
    notifyListeners();
  }

  void startNewChat() {
    clearChat();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _vdsService.dispose();
    super.dispose();
  }
}

class _RetryData {
  final File? imageFile;
  final String? prompt;
  final String? classLevel;

  _RetryData({this.imageFile, this.prompt, this.classLevel});
}
