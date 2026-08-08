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
    this.isDirectChat = false,
    this.thinkingWords = 0,
    this.thinkingPrevBosluk = true,
    this.thinkingDone = false,
    this.notice,
  })  : stepImages = stepImages ?? [],
        stepOnlyImages = stepOnlyImages ?? [],
        timestamp = timestamp ?? DateTime.now();

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
