/// AÇIK UÇLU SUNUCU BİLDİRİMİ.
///
/// Uygulama hiçbir sebebi TANIMAZ. Backend ne gönderirse onu basar:
/// kota bitti, okul kapatıldı, MAX hakkı doldu, bakım, duyuru… Yeni bir sebep
/// eklemek için app güncellemesi GEREKMEZ — sunucudaki notices.json yeter.
///
/// İki kanaldan gelir:
///   • HTTP yanıt gövdesi  → { "error": "...", "notice": { ... } }
///   • WebSocket           → { "type": "notice", "notice": { ... } }
library;

enum NoticeSeverity { info, warning, error, blocked }

/// Bildirim NEREDE gösterilsin — kararı SUNUCU verir.
///   chat   : sohbete, AI cevabı gibi bir balon olarak (VARSAYILAN)
///   dialog : ekranı kesen modal (yalnız gerçekten kesmesi gerekenler için)
enum NoticeDisplay { chat, dialog }

NoticeSeverity _severityFrom(String? s) {
  switch (s) {
    case 'warning':
      return NoticeSeverity.warning;
    case 'error':
      return NoticeSeverity.error;
    case 'blocked':
      return NoticeSeverity.blocked;
    default:
      return NoticeSeverity.info;
  }
}

/// Bildirim butonu. `kind` istemcinin bildiği TEK sınırlı küme; tanımadığı bir
/// kind gelirse buton yine çizilir ama sadece kapatır (ileri uyumluluk).
enum NoticeActionKind { dismiss, url, route }

class NoticeAction {
  final String label;
  final NoticeActionKind kind;
  final String value;

  const NoticeAction({required this.label, required this.kind, this.value = ''});

  static NoticeAction? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final label = (raw['label'] ?? '').toString().trim();
    if (label.isEmpty) return null;
    final k = (raw['kind'] ?? 'dismiss').toString();
    return NoticeAction(
      label: label,
      kind: k == 'url'
          ? NoticeActionKind.url
          : (k == 'route' ? NoticeActionKind.route : NoticeActionKind.dismiss),
      value: (raw['value'] ?? '').toString(),
    );
  }
}

class ServerNotice {
  /// Sunucudaki anahtar (ör. 'user_rate_limit'). Yalnız loglama/tekrar bastırma
  /// için; davranış BUNA GÖRE dallanmaz — açık uçluluğun bozulmaması şart.
  final String code;
  final String title;
  final String message;
  final NoticeSeverity severity;
  final bool dismissible;
  final List<NoticeAction> actions;
  final Map<String, dynamic> extra;
  final NoticeDisplay display;

  const ServerNotice({
    this.code = '',
    required this.title,
    required this.message,
    this.severity = NoticeSeverity.info,
    this.dismissible = true,
    this.actions = const [],
    this.extra = const {},
    this.display = NoticeDisplay.chat,
  });

  bool get isBlocking => severity == NoticeSeverity.blocked || !dismissible;

  /// Herhangi bir JSON gövdesinden bildirimi çıkarır.
  /// `notice` alanı yoksa null döner → çağıran eski davranışına devam eder.
  static ServerNotice? fromBody(dynamic body) {
    if (body is! Map) return null;
    final n = body['notice'];
    if (n is! Map) return null;

    final title = (n['title'] ?? '').toString().trim();
    final message = (n['message'] ?? '').toString().trim();
    // İkisi de boşsa gösterilecek bir şey yok — eski `error` metnine düşülsün.
    if (title.isEmpty && message.isEmpty) return null;

    final acts = <NoticeAction>[];
    if (n['actions'] is List) {
      for (final a in (n['actions'] as List)) {
        final parsed = NoticeAction.fromJson(a);
        if (parsed != null) acts.add(parsed);
      }
    }

    return ServerNotice(
      code: (n['code'] ?? '').toString(),
      title: title.isEmpty ? 'Bilgi' : title,
      message: message,
      severity: _severityFrom(n['severity']?.toString()),
      dismissible: n['dismissible'] != false,
      actions: acts,
      extra: (n['extra'] is Map) ? Map<String, dynamic>.from(n['extra'] as Map) : const {},
      display: n['display'] == 'dialog' ? NoticeDisplay.dialog : NoticeDisplay.chat,
    );
  }
}

/// Sunucu isteği bir bildirimle reddettiğinde fırlatılır.
class ServerNoticeException implements Exception {
  final ServerNotice notice;
  final int statusCode;

  ServerNoticeException(this.notice, {this.statusCode = 0});

  @override
  String toString() => notice.message.isNotEmpty ? notice.message : notice.title;
}
