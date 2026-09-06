import 'dart:convert';
import 'dart:typed_data';

import 'server_notice.dart';

enum MessageType { user, ai }

enum MessageStatus { sending, streaming, complete, error }

class ChatMessage {
  final String id;
  final MessageType type;
  String text;
  String? imageBase64;
  String? imageUrl;
  bool hasSteps;
  int currentStep;
  int totalSteps;
  List<String> stepImages;
  List<String> stepOnlyImages;
  MessageStatus status;
  final DateTime timestamp;

  // VDS entegrasyonu
  String? requestId;
  String? conversationId;
  bool hasSessionData;
  List<dynamic>? sessionCommands;
  List<dynamic>? sessionAudioCommands;
  int? sessionDuration;

  /// Çizilmiş çözümün son karesi (sunucu üretir; yoksa null → kart fotoğrafsız).
  String? thumbnailUrl;

  // Direct chat modu (drawOnImage kapalı)
  bool isDirectChat;

  /// Düşünme sürecinde SAYILAN kelime adedi.
  ///
  /// Sürecin METNİ bilerek saklanmıyor: öğrenciye gösterilmiyor, tek göstergesi
  /// artan bu sayaç. Metni tutmamanın iki somut faydası var — modelin
  /// `</think>` kapatmadan on binlerce token döndüğü bozuk turlarda ne bellek
  /// şişiyor ne de her token'da string birleştirme (O(n²)) maliyeti oluşuyor.
  int thinkingWords;

  /// Sayaç akış hâlinde ilerlediği için kelime sınırı tek tek karakterlerden
  /// bulunuyor; bir token'ın son karakteri boşluk muydu bilgisi burada taşınır.
  bool thinkingPrevBosluk;

  bool thinkingDone;

  /// Düşünme akışından gelen bir parçayı sayaca işler (metni SAKLAMAZ).
  ///
  /// Kelime sınırı "boşluktan boşluk-olmayana geçiş"tir. Sınır bir token'ın
  /// ortasına denk gelebildiği için önceki parçanın son karakteri hatırlanır;
  /// aksi halde ikiye bölünen bir kelime iki kez sayılırdı.
  void thinkingTokenEkle(String token) {
    if (token.isEmpty) return;
    var bosluktu = thinkingPrevBosluk;
    var sayac = thinkingWords;
    for (var i = 0; i < token.length; i++) {
      final bosluk = token.codeUnitAt(i) <= 0x20;
      if (bosluktu && !bosluk) sayac++;
      bosluktu = bosluk;
    }
    thinkingWords = sayac;
    thinkingPrevBosluk = bosluktu;
  }

  /// Sunucu bildirimi (kota/ban/duyuru). Doluysa balon AI cevabı yerine
  /// bildirim olarak çizilir — ChatGPT'nin limit mesajı gibi sohbetin içinde.
  final ServerNotice? notice;

  ChatMessage({
    required this.id,
    required this.type,
    this.text = '',
    this.imageBase64,
    this.imageUrl,
    this.hasSteps = false,
    this.currentStep = 0,
    this.totalSteps = 0,
    List<String>? stepImages,
    List<String>? stepOnlyImages,
    this.status = MessageStatus.complete,
    DateTime? timestamp,
    this.requestId,
    this.conversationId,
    this.hasSessionData = false,
    this.sessionCommands,
    this.sessionAudioCommands,
    this.sessionDuration,
    this.thumbnailUrl,
    this.isDirectChat = false,
    this.thinkingWords = 0,
    this.thinkingPrevBosluk = true,
    this.thinkingDone = false,
    this.notice,
  })  : stepImages = stepImages ?? [],
        stepOnlyImages = stepOnlyImages ?? [],
        timestamp = timestamp ?? DateTime.now();

  String? _cozulenB64;
  Uint8List? _cozulenBayt;

  /// [imageBase64]'ün ÇÖZÜLMÜŞ hâli — aynı base64 için YALNIZ BİR KEZ hesaplanır.
  ///
  /// Eskiden `base64Decode` doğrudan `build` içinde çağrılıyordu. Her yeniden
  /// kurulum yeni bir `Uint8List` üretir; `MemoryImage` eşitliği bayt listesinin
  /// KİMLİĞİNE baktığı için görsel önbelleğinde her seferinde yeni bir anahtar
  /// oluşuyor ve JPEG baştan çözülüyordu (akış sırasında saniyede onlarca kez),
  /// üstelik çözüm bitene kadar kare boş kaldığı için fotoğraf göz kırpıyordu.
  ///
  /// Bozuk/eksik base64'te `build` patlamasın diye null döner (çağıran taraf
  /// görseli hiç çizmez).
  Uint8List? get imageBytes {
    final b64 = imageBase64;
    if (b64 == null) {
      _cozulenB64 = null;
      _cozulenBayt = null;
      return null;
    }
    if (!identical(_cozulenB64, b64)) {
      _cozulenB64 = b64;
      try {
        _cozulenBayt = base64Decode(b64);
      } catch (_) {
        _cozulenBayt = null;
      }
    }
    return _cozulenBayt;
  }

  /// Balonun ÇİZİMİNİ etkileyen alanların özeti.
  ///
  /// Sohbet ekranı bu imza değişmediyse balonu YENİDEN KURMAZ, önbellekteki
  /// aynı Widget örneğini döndürür (bkz. chat_screen.dart `_balon`). Akış
  /// sırasında sağlayıcı her token'da bildirim yaydığı için bu, ekrandaki eski
  /// çözümlerin markdown+LaTeX gövdelerinin saniyede onlarca kez baştan
  /// kurulmasını engeller.
  ///
  /// DİKKAT: balonda GÖRÜNEN yeni bir alan eklersen BURAYA DA EKLE; yoksa alan
  /// değişse bile balon ekranda güncellenmez.
  String uiImzasi() {
    final b = StringBuffer()
      ..write(type.index)
      ..write('|')
      ..write(text.hashCode)
      ..write('|')
      ..write(text.length)
      ..write('|')
      ..write(status.index)
      ..write('|')
      ..write(hasSteps ? 1 : 0)
      ..write('|')
      ..write(currentStep)
      ..write('|')
      ..write(totalSteps)
      ..write('|')
      ..write(stepImages.length)
      ..write('|')
      ..write(stepOnlyImages.length)
      ..write('|')
      ..write(imageUrl ?? '')
      ..write('|')
      ..write(imageBase64?.length ?? -1)
      ..write('|')
      ..write(imageBase64?.hashCode ?? 0)
      ..write('|')
      ..write(requestId ?? '')
      ..write('|')
      ..write(hasSessionData ? 1 : 0)
      ..write('|')
      ..write(thumbnailUrl ?? '')
      ..write('|')
      ..write(sessionDuration ?? -1)
      ..write('|')
      ..write(isDirectChat ? 1 : 0)
      ..write('|')
      ..write(thinkingWords)
      ..write('|')
      ..write(thinkingDone ? 1 : 0)
      ..write('|')
      ..write(notice == null ? 0 : identityHashCode(notice));
    return b.toString();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'text': text,
      'hasImage': imageBase64 != null || imageUrl != null,
      'imageUrl': imageUrl,
      'hasSteps': hasSteps,
      'totalSteps': totalSteps,
      'timestamp': timestamp.toIso8601String(),
      'requestId': requestId,
      'conversationId': conversationId,
      'hasSessionData': hasSessionData,
      'isDirectChat': isDirectChat,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      type: MessageType.values.byName(map['type'] as String),
      text: map['text'] as String? ?? '',
      imageUrl: map['imageUrl'] as String?,
      hasSteps: map['hasSteps'] as bool? ?? false,
      totalSteps: map['totalSteps'] as int? ?? 0,
      timestamp: DateTime.parse(map['timestamp'] as String),
      requestId: map['requestId'] as String?,
      conversationId: map['conversationId'] as String?,
      hasSessionData: map['hasSessionData'] as bool? ?? false,
      isDirectChat: map['isDirectChat'] as bool? ?? false,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? text,
    String? imageBase64,
    String? imageUrl,
    bool? hasSteps,
    int? currentStep,
    int? totalSteps,
    List<String>? stepImages,
    List<String>? stepOnlyImages,
    MessageStatus? status,
    String? requestId,
    String? conversationId,
    bool? hasSessionData,
    List<dynamic>? sessionCommands,
    List<dynamic>? sessionAudioCommands,
    int? sessionDuration,
    String? thumbnailUrl,
    bool? isDirectChat,
    int? thinkingWords,
    bool? thinkingDone,
    ServerNotice? notice,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      type: type,
      text: text ?? this.text,
      imageBase64: imageBase64 ?? this.imageBase64,
      imageUrl: imageUrl ?? this.imageUrl,
      hasSteps: hasSteps ?? this.hasSteps,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      stepImages: stepImages ?? List.from(this.stepImages),
      stepOnlyImages: stepOnlyImages ?? List.from(this.stepOnlyImages),
      status: status ?? this.status,
      timestamp: timestamp,
      requestId: requestId ?? this.requestId,
      conversationId: conversationId ?? this.conversationId,
      hasSessionData: hasSessionData ?? this.hasSessionData,
      sessionCommands: sessionCommands ?? this.sessionCommands,
      sessionAudioCommands: sessionAudioCommands ?? this.sessionAudioCommands,
      sessionDuration: sessionDuration ?? this.sessionDuration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      isDirectChat: isDirectChat ?? this.isDirectChat,
      thinkingWords: thinkingWords ?? this.thinkingWords,
      thinkingPrevBosluk: thinkingPrevBosluk,
      thinkingDone: thinkingDone ?? this.thinkingDone,
      // notice eskiden kopyalanmıyordu: bir bildirim balonu copyWith'ten
      // geçerse sessizce boş AI balonuna dönüşürdü.
      notice: notice ?? this.notice,
    );
  }
}
