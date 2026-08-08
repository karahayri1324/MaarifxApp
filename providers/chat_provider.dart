import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/quiz_block.dart';
import '../services/vds_service.dart';
import '../models/server_notice.dart';

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
  int _samimiyet = 2;          // 1=resmî … 4=çok samimi (USER_TEMPLATE <SamimiyetSeviyesi>)
  String _studentIntro = '';   // öğrencinin kendini tanıtması (USER_TEMPLATE tanitim)
  String _model = '3.0';       // '3.0' | '3.0-max' (MAX yalnızca drawOnImage açıkken)

  // Conversation
  String? _currentConversationId;
  // SOHBET MODU KİLİDİ: sohbet ilk istekte çizimli/çizimsiz olarak kilitlenir.
  // null = kilitsiz (yeni sohbet ya da legacy kayıt). Kilitliyken efektif mod
  // sohbetinkidir; kullanıcının global tercihi (_drawOnImage/SharedPreferences)
  // DEĞİŞMEZ, yeni sohbette geri gelir.
  bool? _conversationMode;

  // AÇIK UÇLU SUNUCU BİLDİRİMİ: UI'ın bir kez gösterip tüketeceği kuyruk.
  // Provider içeriğe BAKMAZ; taşımaktan başka bir şey yapmaz.
  // ── UZAKTAN ÖZELLİK BAYRAKLARI (/api/app-config) ────────────────────
  // Sunucu okul/kullanıcı bazında kapatabilir. Okunamazsa AÇIK kalır: bir ağ
  // hatası yüzünden kullanıcının mevcut ayarını elinden almak, kapalı olması
  // gerekeni bir tur açık bırakmaktan daha kötü (sunucu zaten reddediyor).
  bool _samimiyet4Enabled = true;
  bool get samimiyet4Enabled => _samimiyet4Enabled;

  ServerNotice? _pendingNotice;
  ServerNotice? get pendingNotice => _pendingNotice;
  ServerNotice? consumeNotice() {
    final n = _pendingNotice;
    _pendingNotice = null;
    return n;
  }

  /// Bildirimi SOHBETE, AI cevabı gibi bir balon olarak ekler.
  /// Modal yerine bunun tercih edilmesi bilinçli: kullanıcı yazdığı mesajı ve
  /// bağlamı kaybetmez, bildirim geçmişte kalır (büyük AI ürünlerinin kota
  /// mesajlarıyla aynı davranış).
  void _addNoticeMessage(ServerNotice n) {
    messages.add(ChatMessage(
      id: 'notice_${DateTime.now().microsecondsSinceEpoch}',
      type: MessageType.ai,
      notice: n,
      status: MessageStatus.complete,
    ));
  }

  /// Bildirimi sunucunun istediği yere yönlendirir (varsayılan: sohbet).
  void pushNotice(ServerNotice n) {
    if (n.display == NoticeDisplay.dialog) {
      _pendingNotice = n;      // ekranı kesen modal — sunucu açıkça istediyse
    } else {
      _addNoticeMessage(n);
    }
    notifyListeners();
  }

  String? _userId;
  String? _displayName;
  bool _isGuest = false;
  String? _deviceId;

  // Retry data: errorMessageId -> {imageFile, prompt, classLevel}
  final Map<String, _RetryData> _retryData = {};

  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;

  // Eşzamanlı gönderimlerde temp-id çakışmasın (aynı ms'de iki send)
  static int _tempSeq = 0;

  int get detailLevel => _detailLevel;
  bool get showStepData => _showStepData;
  bool get drawOnImage => _drawOnImage;
  bool get enableThinking => _enableThinking;
  int get samimiyet => _samimiyet;
  String get studentIntro => _studentIntro;
  String get model => _model;
  bool get isGuestUser => _isGuest;
  bool get serverReachable => _serverReachable;
  bool get hasInternet => _hasInternet;
  String? get currentConversationId => _currentConversationId;
  bool? get conversationMode => _conversationMode;
  bool get isModeLocked => _conversationMode != null;
  /// İsteklerin ve UI'ın okuması gereken mod: sohbet kilitliyse SOHBETİNKİ.
  bool get effectiveDrawOnImage => _conversationMode ?? _drawOnImage;
  VdsService get vdsService => _vdsService;

  ChatProvider({
    VdsService? vdsService,
  }) : _vdsService = vdsService ?? VdsService() {
    _loadSettings();
  }

  void setAuth(String? userId, String? token, {bool isGuest = false, String? deviceId, String? displayName}) {
    // Kullanıcı değiştiyse (guest→login, hesap değişimi) eski kullanıcının
    // mesajları ve conversationId'si taşınmasın — yanlış hesaba mesaj
    // eklenmesini / sunucunun yabancı conversationId reddetmesini önler.
    if (_userId != null && _userId != userId) {
      clearChat();
    }
    _userId = userId;
    _isGuest = isGuest;
    _deviceId = deviceId;
    _displayName = displayName;

    if (userId != null && token != null) {
      _vdsService.setAuth(token, userId);
      _connectWebSocket();
    }
  }

  /// Kullanıcı adı ayarlardan değişince çağrılır. Bu kopya isteğe `studentName`
  /// olarak gidiyor; güncellenmezse model, uygulama yeniden başlatılana kadar
  /// öğrenciye ESKİ adıyla hitap etmeye devam eder.
  void setDisplayName(String? ad) {
    _displayName = (ad ?? '').trim().isEmpty ? null : ad!.trim();
    notifyListeners();
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
    // clamp: eski sürümden kalan aralık-dışı değer UI'da RangeError yapmasın
    _detailLevel = (prefs.getInt('detailLevel') ?? 3).clamp(1, 5);
    _showStepData = prefs.getBool('showStepData') ?? false;
    _drawOnImage = prefs.getBool('drawOnImage') ?? true;
    _enableThinking = prefs.getBool('enableThinking') ?? true;
    _samimiyet = (prefs.getInt('samimiyet') ?? 2).clamp(1, 4);
    _studentIntro = prefs.getString('studentIntro') ?? '';
    _model = prefs.getString('modelVersion') ?? '3.0';
    // MAX yalnızca çizim modu açıkken geçerli — kapalıysa normalize et
    if (_model == '3.0-max' && !_drawOnImage) {
      _model = '3.0';
      await prefs.setString('modelVersion', _model);
    }
    notifyListeners();
  }

  Future<void> setModel(String m) async {
    final normalized = m == '3.0-max' ? '3.0-max' : '3.0';
    // MAX: çizim modu açık + giriş yapılmış olmalı (sunucu misafirde MAX'ı zaten reddeder)
    if (normalized == '3.0-max' && (!_drawOnImage || _isGuest)) return;
    _model = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('modelVersion', _model);
    notifyListeners();
  }

  Future<void> setSamimiyet(int level) async {
    _samimiyet = level.clamp(1, 4);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('samimiyet', _samimiyet);
    notifyListeners();
  }

  /// Tanıtım metni. Yerel önbellek + SUNUCU (tek doğruluk kaynağı): cihaz
  /// değiştiren öğrenci ayarlar ekranını boş bulmasın.
  Future<void> setStudentIntro(String value, {bool sunucuyaYaz = true}) async {
    _studentIntro = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('studentIntro', _studentIntro);
    notifyListeners();
    if (sunucuyaYaz && !_isGuest) {
      await _vdsService.updateProfile(studentIntro: _studentIntro);
    }
  }

  /// Sunucudan profil + bayrakları çek (ayarlar ekranı açılışında).
  ///
  /// Tanıtım metninde sunucu kaynaktır AMA yalnız DOLU olduğunda. Sebep: bu
  /// sürümden önce tanıtım YALNIZCA cihazda (SharedPreferences) tutuluyordu;
  /// sunucudaki alanı hiçbir kod yazmıyordu. Koşulsuz "uzak ezer" deseydik,
  /// güncellemeden sonra ayarları ilk açan her öğrencinin kendi yazdığı metin
  /// boş bir sunucu değeriyle SİLİNİRDİ. Uzak boş + yerel dolu ise bu tek
  /// seferlik göç sayılır ve yerel metin yukarı taşınır.
  Future<void> refreshRemoteSettings() async {
    if (_isGuest) return;
    final cfg = await _vdsService.getAppConfig();
    if (cfg != null && cfg['samimiyet4Enabled'] is bool) {
      _samimiyet4Enabled = cfg['samimiyet4Enabled'] as bool;
      // Bayrak kapandıysa seçili değer geçersiz kaldı → aşağı çek, kaydet.
      if (!_samimiyet4Enabled && _samimiyet >= 4) {
        await setSamimiyet(3);
      }
    }
    final prof = await _vdsService.getProfile();
    if (prof != null && prof['studentIntro'] is String) {
      final uzak = (prof['studentIntro'] as String).trim();
      if (uzak.isNotEmpty) {
        if (uzak != _studentIntro) {
          await setStudentIntro(uzak, sunucuyaYaz: false);
        }
      } else if (_studentIntro.isNotEmpty) {
        // Göç: cihazdaki metni sunucuya taşı (silme YOK).
        await _vdsService.updateProfile(studentIntro: _studentIntro);
      }
    }
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
    // Çizim kapatılınca MAX seçilemez — otomatik '3.0'a dön
    if (!value && _model == '3.0-max') {
      _model = '3.0';
      await prefs.setString('modelVersion', _model);
    }
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
      case VdsMessageType.notice:
        // Anlık, isteğe bağlı OLMAYAN bildirim (ör. okul erişimi kapatıldı).
        // İçerik yorumlanmaz; olduğu gibi UI'a taşınır.
        final n = ServerNotice.fromBody(msg.data);
        if (n != null) pushNotice(n);
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
    if (token.isEmpty) return;

    // Düşünme METNİ saklanmıyor — öğrenciye gösterilmiyor, tek gösterge sayaç.
    messages[msgIndex].thinkingTokenEkle(token);
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
    if (msgIndex != -1 && !messages[msgIndex].hasSessionData) {
      messages[msgIndex].hasSessionData = true;
      notifyListeners();
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
      // Burada tekrar true yapmıyoruz — metin cevaplarında yanlışlıkla "Çözümü İzle" butonu çıkmasın.
      // ÇİZİMLİ cevapta buton, backend'in request_complete'ten HEMEN ÖNCE yolladığı stream_data+
      // renderedStep 'session-signal'i ile set edilir (server.js sendCompleteToUser) → Flutter'a
      // dokunmadan garanti. Backend hasDrawing bayrağını da payload'a koyar (ileride kullanılabilir).
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
    List<int>? markedRegion,   // işaretli bölge [x1,y1,x2,y2] 0-1000 (takip turu)
    String? hintRef,           // Hint yanıtı ref (takip turu)
    String? studentQuestion,   // işaretli bölge takip notu → <ogrenci_sorusu>
    bool? forceDirectChat,     // quiz cevabı: çizim açık olsa bile METİN turu (sohbette kal)
  }) async {
    // MOD KİLİDİ: sohbet başladıysa efektif mod SOHBETİNKİdir (global toggle değil).
    // quiz cevabı (forceDirectChat) istisna: backend bunu muaf tutuyor.
    final bool startingNew = _currentConversationId == null;
    // GÖRSELSİZ YENİ SOHBET: çizim toggle'ı açık ama fotoğraf yoksa istek otomatik
    // ÇİZİMSİZ gider. Çizim, soru görselinin ÜZERİNE yapılır — görsel yokken çizim
    // modu zaten imkânsız. Eskiden gönder butonu kilitleniyordu; artık gönderilebilir
    // ve mod sessizce metne düşer (sohbet de o modda kilitlenir, tutarlı kalır).
    final bool gorselsizDusus =
        startingNew && forceDirectChat != true && effectiveDrawOnImage && imageFile == null;
    final effDraw = (forceDirectChat == true || gorselsizDusus) ? false : effectiveDrawOnImage;
    // Coklu request: bloklama yok. Bu yüzden ilk gönderim uçuştayken ikincisi de
    // AYNI modu kullansın diye modu şimdiden kilitliyoruz; başarısızlıkta geri alınır.
    if (startingNew && _conversationMode == null && forceDirectChat != true) {
      _conversationMode = effDraw;
    }
    // Sohbet hiç açılmadıysa iyimser kilidi geri al (hata yollarından çağrılır).
    void revertOptimisticLock() {
      if (startingNew && _currentConversationId == null && _activeRequests.isEmpty) {
        _conversationMode = null;
      }
    }

    String? imageBase64ForDisplay;
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      imageBase64ForDisplay = base64Encode(bytes);
    }

    // Optimistik user mesajı: yükleme sürerken 'sending' olarak görünür,
    // başarıda gerçek id/requestId ile güncellenir, hata yollarında kaldırılır.
    // Temp id yalnızca user mesajında kullanılır (_findAiMsgIndex etkilenmez).
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}_${_tempSeq++}';
    messages.add(ChatMessage(
      id: tempId,
      type: MessageType.user,
      text: (prompt != null && prompt.isNotEmpty) ? prompt : (studentQuestion ?? ''),
      imageBase64: imageBase64ForDisplay,
      status: MessageStatus.sending,
    ));
    notifyListeners();

    void removeTempMessage() => messages.removeWhere((m) => m.id == tempId);

    // Check internet first
    final hasNet = await checkInternetConnection();
    if (!hasNet) {
      _serverReachable = false;
      revertOptimisticLock();
      removeTempMessage();
      _addErrorMessage(
          'İnternet bağlantısı bulunamadı. Lütfen Wi-Fi veya mobil veri bağlantınızı kontrol edip tekrar deneyin.',
          imageFile: imageFile, prompt: prompt, classLevel: classLevel,
          forceDirectChat: forceDirectChat == true);
      notifyListeners();
      return null;
    }

    final status = await _vdsService.checkStatus();
    if (status == null) {
      _serverReachable = false;
      revertOptimisticLock();
      removeTempMessage();
      _addErrorMessage(
          'Sunucuya ulaşılamıyor. Sunucu bakım altında olabilir, lütfen birkaç dakika sonra tekrar deneyin.',
          imageFile: imageFile, prompt: prompt, classLevel: classLevel,
          forceDirectChat: forceDirectChat == true);
      notifyListeners();
      return null;
    }
    _serverReachable = true;

    notifyListeners();

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
          drawOnImage: effDraw,
          enableThinking: _enableThinking,
          samimiyet: _samimiyet,
          studentIntro: _studentIntro.isNotEmpty ? _studentIntro : null,
          markedRegion: markedRegion,
          hintRef: hintRef,
          studentQuestion: studentQuestion,
          model: _model,
        );
      } else {
        result = await _vdsService.sendMessage(
          imageFile: imageFile,
          text: prompt,
          conversationId: _currentConversationId,
          detailLevel: _detailLevel,
          classLevel: classLevel,
          studentName: _displayName,
          drawOnImage: effDraw,
          enableThinking: _enableThinking,
          samimiyet: _samimiyet,
          studentIntro: _studentIntro.isNotEmpty ? _studentIntro : null,
          markedRegion: markedRegion,
          hintRef: hintRef,
          studentQuestion: studentQuestion,
          model: _model,
        );
      }
    } on ServerNoticeException catch (e) {
      // AÇIK UÇLU BİLDİRİM: sebep burada TANINMAZ. Sunucunun yazdığı metin
      // olduğu gibi UI'a verilir → yeni senaryolar app güncellemesi istemez.
      // Kullanıcının yazdığı mesaj SİLİNMEZ; altına bildirim balonu düşer —
      // "AI cevap verdi" akışı korunur, kullanıcı metnini kaybetmez.
      revertOptimisticLock();
      // Kullanıcının balonu KALIR ama 'gönderiliyor' spinner'ında donmasın.
      for (final m in messages) {
        if (m.id == tempId) m.status = MessageStatus.complete;
      }
      pushNotice(e.notice);
      return null;
    } on RateLimitException catch (e) {
      revertOptimisticLock();
      removeTempMessage();
      _addErrorMessage(_getRateLimitMessage(e),
          imageFile: imageFile, prompt: prompt, classLevel: classLevel,
          forceDirectChat: forceDirectChat == true);
      notifyListeners();
      return null;
    } on ConversationModeLockedException catch (e) {
      // Sunucunun gerçeği kazanır → yerel modu düzelt (self-heal). Retry verisi
      // bilerek saklanıyor: düzeltilmiş modla tekrar denemek başarılı olur.
      _conversationMode = e.conversationMode;
      removeTempMessage();
      _addErrorMessage(e.message,
          imageFile: imageFile, prompt: prompt, classLevel: classLevel,
          forceDirectChat: forceDirectChat == true);
      notifyListeners();
      return null;
    }

    if (result == null) {
      revertOptimisticLock();
      removeTempMessage();
      _addErrorMessage(
          'Mesaj gönderilemedi. Bağlantınızı kontrol edip tekrar deneyin.',
          imageFile: imageFile, prompt: prompt, classLevel: classLevel,
          forceDirectChat: forceDirectChat == true);
      notifyListeners();
      return null;
    }

    _currentConversationId = result.conversationId;
    // Sohbetin modu kilitlendi (quiz turu mod belirlemez — o zaten muaf).
    if (forceDirectChat != true) _conversationMode ??= effDraw;
    _activeRequests.add(result.requestId);

    // Optimistik mesajı gerçek değerlerle güncelle — yeni user mesajı EKLENMEZ
    final tempIndex = messages.indexWhere((m) => m.id == tempId);
    if (tempIndex != -1) {
      messages[tempIndex] = messages[tempIndex].copyWith(
        id: result.userMessageId,
        status: MessageStatus.complete,
        requestId: result.requestId,
        conversationId: result.conversationId,
      );
    } else {
      // Temp mesaj bu arada silindiyse (örn. clearChat) eski davranışa dön
      messages.add(ChatMessage(
        id: result.userMessageId,
        type: MessageType.user,
        text: (prompt != null && prompt.isNotEmpty) ? prompt : (studentQuestion ?? ''),
        imageBase64: imageBase64ForDisplay,
        status: MessageStatus.complete,
        requestId: result.requestId,
        conversationId: result.conversationId,
      ));
    }

    messages.add(ChatMessage(
      id: result.aiMessageId,
      type: MessageType.ai,
      text: '',
      status: MessageStatus.streaming,
      requestId: result.requestId,
      conversationId: result.conversationId,
      isDirectChat: !effDraw,
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

  void _addErrorMessage(String error, {File? imageFile, String? prompt, String? classLevel,
      bool forceDirectChat = false}) {
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
        forceDirectChat: forceDirectChat,
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
      forceDirectChat: data.forceDirectChat ? true : null,
    );
  }

  // ─── Adım Navigasyonu ───

  void navigateToStep(String messageId, int step) {
    final msgIndex = messages.indexWhere((m) => m.id == messageId);
    if (msgIndex == -1) return;

    final msg = messages[msgIndex];
    if (step < 0 || step >= msg.stepImages.length) return;

    msg.currentStep = step;
    // stepOnlyImages her akışta doldurulmaz — indeks yoksa stepImages'a düş
    final stepOnly = (_showStepData && step < msg.stepOnlyImages.length)
        ? msg.stepOnlyImages[step]
        : null;
    msg.imageBase64 =
        (stepOnly != null && stepOnly.isNotEmpty) ? stepOnly : msg.stepImages[step];

    notifyListeners();
  }

  // ─── Sohbet Geçmişi ───

  Future<({List<ConversationSummary> conversations, int total})> getConversations({int limit = 0, int offset = 0}) async {
    return await _vdsService.getConversations(limit: limit, offset: offset);
  }

  Future<void> loadConversation(String conversationId) async {
    final res = await _vdsService.getConversationMessages(conversationId);
    final vdsMessages = res.messages;
    if (vdsMessages.isEmpty) return;

    clearChat();
    _currentConversationId = conversationId;
    // Sohbetin gerçek modu sunucudan → toggle bunu gösterip kilitlenir.
    // (Aşağıdaki per-mesaj isDirectChat türetmesi AYRI bir mesele: o balon
    //  render'ı için, legacy sezgiselleri dahil — aynen korunuyor.)
    _conversationMode = res.mode;

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

      // Quiz kartı "cevaplandı" durumu sohbet geçmişinden geri kurulur —
      // uygulama yeniden açılınca öğrenci aynı soruyu boş kart olarak görmesin.
      if (type == MessageType.user && (vdsMsg.text ?? '').isNotEmpty) {
        final qa = parseQuizAnswer(vdsMsg.text!);
        if (qa != null && qa.quizId.isNotEmpty) {
          QuizAnswerStore.instance.record(qa.quizId, qa.userAnswer);
        }
      }
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
    _conversationMode = null;           // mod kilidi kalkar, global tercih geri gelir
    QuizAnswerStore.instance.clear();   // quiz "cevaplandı" durumu sohbete bağlı
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
  /// Quiz cevabı turu muydu? Korunmazsa çizimli bir sohbette retry, metin turu
  /// olması gereken quiz cevabını çizim turuna çevirirdi.
  final bool forceDirectChat;

  _RetryData({this.imageFile, this.prompt, this.classLevel,
      this.forceDirectChat = false});
}
