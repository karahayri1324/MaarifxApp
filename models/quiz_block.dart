import 'dart:convert';

/// ```maarifx-quiz``` blokları — AI mesajı içindeki etkileşimli soru kartları.
///
/// Sözleşme: KonuAnlatimi/ai/INTERACTIVE_BLOCKS.md + QUIZ_ANSWER.md
///   AI  →  ```maarifx-quiz\n{JSON}\n```           (soru; answer/explanation GİZLİ)
///   UI  →  ```maarifx-quiz-answer\n{JSON}\n```    (cevap; user mesajı olarak gider)
/// Değerlendirmeyi MODEL yapar — burada doğru/yanlış hesaplanmaz, cevap gösterilmez.

enum QuizType { open, short, mcq, multi, trueFalse, match, order, checklist, fill, unknown }

QuizType _quizTypeFrom(String? s) {
  switch (s) {
    case 'open':
      return QuizType.open;
    case 'short':
      return QuizType.short;
    case 'mcq':
      return QuizType.mcq;
    case 'multi':
      return QuizType.multi;
    case 'true_false':
      return QuizType.trueFalse;
    case 'match':
      return QuizType.match;
    case 'order':
      return QuizType.order;
    case 'checklist':
      return QuizType.checklist;
    case 'fill':
      return QuizType.fill;
    default:
      return QuizType.unknown;
  }
}

/// {id, label} çiftleri (options / left / right / items)
class QuizOption {
  final String id;
  final String label;
  const QuizOption(this.id, this.label);

  static List<QuizOption> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <QuizOption>[];
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      if (e is Map) {
        final id = (e['id'] ?? e['key'] ?? '$i').toString();
        final label = (e['label'] ?? e['text'] ?? e['ad'] ?? '').toString();
        if (label.isNotEmpty) out.add(QuizOption(id, label));
      } else if (e is String) {
        out.add(QuizOption('$i', e));
      }
    }
    return out;
  }
}

/// fill tipi boşluk tanımı
class QuizBlank {
  final String id;
  const QuizBlank(this.id);

  static List<QuizBlank> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <QuizBlank>[];
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      final id = (e is Map ? (e['id'] ?? 'b${i + 1}') : 'b${i + 1}').toString();
      out.add(QuizBlank(id));
    }
    return out;
  }
}

class QuizBlock {
  final String id;
  final QuizType type;
  final String rawType;
  final String prompt;
  final String title;
  final String placeholder;
  final String difficulty;
  final int minChars;
  final List<QuizOption> options;
  final List<QuizOption> left;
  final List<QuizOption> right;
  final List<QuizOption> items;
  final List<QuizBlank> blanks;
  final String template;

  const QuizBlock({
    required this.id,
    required this.type,
    required this.rawType,
    this.prompt = '',
    this.title = '',
    this.placeholder = '',
    this.difficulty = '',
    this.minChars = 0,
    this.options = const [],
    this.left = const [],
    this.right = const [],
    this.items = const [],
    this.blanks = const [],
    this.template = '',
  });

  /// Öğrenciye gösterilecek soru kökü (checklist'te title).
  String get heading => prompt.isNotEmpty ? prompt : title;

  /// Cevap gerektirmeyen tip (öz-değerlendirme).
  bool get isSelfCheck => type == QuizType.checklist;

  static QuizBlock? fromJsonString(String s) {
    try {
      final d = jsonDecode(s);
      if (d is! Map) return null;
      final t = _quizTypeFrom(d['type']?.toString());
      if (t == QuizType.unknown) return null;
      final id = (d['id'] ?? '').toString();
      if (id.isEmpty) return null;
      return QuizBlock(
        id: id,
        type: t,
        rawType: d['type'].toString(),
        prompt: (d['prompt'] ?? '').toString(),
        title: (d['title'] ?? '').toString(),
        placeholder: (d['placeholder'] ?? '').toString(),
        difficulty: (d['difficulty'] ?? '').toString(),
        minChars: (d['min_chars'] is num) ? (d['min_chars'] as num).toInt() : 0,
        options: QuizOption.listFrom(d['options']),
        left: QuizOption.listFrom(d['left']),
        right: QuizOption.listFrom(d['right']),
        items: QuizOption.listFrom(d['items']),
        blanks: QuizBlank.listFrom(d['blanks']),
        template: (d['template'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Gövdesi eksik/tutarsız bloklar kart olarak basılmaz (düz metne düşer).
  bool get isRenderable {
    if (heading.isEmpty && type != QuizType.fill) return false;
    switch (type) {
      case QuizType.mcq:
      case QuizType.multi:
        return options.length >= 2;
      case QuizType.match:
        return left.isNotEmpty && right.isNotEmpty;
      case QuizType.order:
        return items.length >= 2;
      case QuizType.checklist:
        return items.isNotEmpty;
      case QuizType.fill:
        return template.isNotEmpty && blanks.isNotEmpty;
      default:
        return true;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Mesaj → parça ayrıştırma
// ═══════════════════════════════════════════════════════════════════════

enum SegmentKind { text, quiz }

class MessageSegment {
  final SegmentKind kind;
  final String text;
  final QuizBlock? quiz;
  const MessageSegment.text(this.text)
      : kind = SegmentKind.text,
        quiz = null;
  const MessageSegment.quiz(this.quiz, this.text) : kind = SegmentKind.quiz;
}

/// ```maarifx-quiz``` fence'i. Akış sırasında blok YARIM gelebilir; kapanış
/// ``` görülmeden kart basılmaz (yarım JSON parse edilemez, ekran titremesin).
final RegExp _quizFence = RegExp(r'```maarifx-quiz[ \t]*\r?\n([\s\S]*?)\r?\n?```');

/// Açılmış ama HENÜZ kapanmamış fence — streaming sırasında ham JSON'u gizlemek için.
final RegExp _quizFenceOpen = RegExp(r'```maarifx-quiz[ \t]*\r?\n[\s\S]*$');

/// AI mesaj metnini metin/quiz parçalarına böler.
/// Kapanmamış fence "…soru hazırlanıyor" olarak kırpılır — öğrenci ham JSON görmez.
List<MessageSegment> parseMessageSegments(String raw) {
  final out = <MessageSegment>[];
  if (raw.isEmpty) return out;

  var text = raw;
  var last = 0;
  for (final m in _quizFence.allMatches(text)) {
    final before = text.substring(last, m.start);
    if (before.trim().isNotEmpty) out.add(MessageSegment.text(before));
    final q = QuizBlock.fromJsonString(m.group(1)!.trim());
    if (q != null && q.isRenderable) {
      out.add(MessageSegment.quiz(q, m.group(0)!));
    } else {
      // Bozuk JSON → ham blok gösterme, sadece bilgi ver (model bir sonraki turda düzeltir)
      out.add(const MessageSegment.text('_(soru kartı okunamadı)_'));
    }
    last = m.end;
  }
  var tail = text.substring(last);
  final open = _quizFenceOpen.firstMatch(tail);
  if (open != null) {
    final head = tail.substring(0, open.start);
    if (head.trim().isNotEmpty) out.add(MessageSegment.text(head));
    out.add(const MessageSegment.text('_Soru hazırlanıyor…_'));
  } else if (tail.trim().isNotEmpty) {
    out.add(MessageSegment.text(tail));
  }
  return out;
}

/// Metinde en az bir (kapanmış veya açılmış) quiz bloğu var mı?
bool hasQuizBlock(String raw) =>
    raw.contains('```maarifx-quiz');

// ═══════════════════════════════════════════════════════════════════════
// Cevap paketi (UI → model)
// ═══════════════════════════════════════════════════════════════════════

/// QUIZ_ANSWER.md kanonik formatı. Backend not vermez; model puanlar.
String formatQuizAnswerMessage({
  required String quizId,
  required String type,
  required Object userAnswer,
  int? attempt,
}) {
  final m = <String, dynamic>{
    'quiz_id': quizId,
    'type': type,
    'user_answer': userAnswer,
  };
  if (attempt != null) m['attempt'] = attempt;
  return '```maarifx-quiz-answer\n${jsonEncode(m)}\n```';
}

final RegExp _answerFence =
    RegExp(r'```maarifx-quiz-answer[ \t]*\r?\n([\s\S]*?)\r?\n?```');

class QuizAnswerPayload {
  final String quizId;
  final String type;
  final dynamic userAnswer;
  final int? attempt;
  const QuizAnswerPayload(this.quizId, this.type, this.userAnswer, this.attempt);

  /// Kullanıcı balonunda gösterilecek okunur özet (ham JSON gösterilmez).
  String get pretty {
    final a = userAnswer;
    if (a is bool) return a ? 'Doğru' : 'Yanlış';
    if (a is List) return a.join(', ');
    if (a is Map) {
      return a.entries.map((e) => '${e.key} → ${e.value}').join(' · ');
    }
    return a?.toString() ?? '';
  }
}

/// Kullanıcı mesajı bir quiz cevabı mı? Değilse null.
QuizAnswerPayload? parseQuizAnswer(String raw) {
  final m = _answerFence.firstMatch(raw);
  if (m == null) return null;
  try {
    final d = jsonDecode(m.group(1)!.trim());
    if (d is! Map) return null;
    return QuizAnswerPayload(
      (d['quiz_id'] ?? '').toString(),
      (d['type'] ?? '').toString(),
      d['user_answer'],
      d['attempt'] is num ? (d['attempt'] as num).toInt() : null,
    );
  } catch (_) {
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Oturum içi cevap deposu
// ═══════════════════════════════════════════════════════════════════════

/// Gönderilen cevapları quiz id ile tutar. ListView.builder kartları yok edip
/// yeniden kurduğunda (scroll/rebuild) "cevaplandı" durumu KAYBOLMASIN diye
/// widget state'i yerine burada saklanır. Sohbet değişince temizlenir.
class QuizAnswerStore {
  QuizAnswerStore._();
  static final QuizAnswerStore instance = QuizAnswerStore._();

  final Map<String, dynamic> _answers = {};
  final Map<String, int> _attempts = {};

  bool isAnswered(String quizId) => _answers.containsKey(quizId);
  dynamic answerOf(String quizId) => _answers[quizId];
  int attemptOf(String quizId) => _attempts[quizId] ?? 0;

  void record(String quizId, dynamic answer) {
    _answers[quizId] = answer;
    _attempts[quizId] = (_attempts[quizId] ?? 0) + 1;
  }

  void clear() {
    _answers.clear();
    _attempts.clear();
  }
}
