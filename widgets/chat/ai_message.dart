import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../config/theme.dart';
import '../../models/chat_message.dart';
import '../../models/quiz_block.dart';
import '../common/server_notice_body.dart';
import '../common/ui_bits.dart';
import 'markdown_math.dart';
import 'quiz_card.dart';

/// AI mesajı.
///
/// Balon, avatar, kenarlık ve gölge YOK: cevap doğrudan sayfanın metni.
/// Başta küçük bir meta satırı var (f(x) işareti + "Düşündü · N kelime");
/// akışta spinner yerine yanıp sönen imleç. Çizimli çözüm bir kart, hata ve
/// sunucu bildirimi sol çizgili satır.
class AIMessageWidget extends StatelessWidget {
  final ChatMessage message;
  final Function(int)? onStepChange;
  final Function(String)? onReplay;
  final VoidCallback? onRetry;

  /// ```maarifx-quiz``` kartından cevap gönderilince çağrılır (fence metniyle).
  final Future<bool> Function(String fence)? onQuizAnswer;

  const AIMessageWidget({
    super.key,
    required this.message,
    this.onStepChange,
    this.onReplay,
    this.onRetry,
    this.onQuizAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    // SUNUCU BİLDİRİMİ: kota/ban/duyuru. Sohbetin içinde, ayrı bir satır olarak.
    if (message.notice != null) {
      return ServerNoticeBody(notice: message.notice!);
    }

    // Direct chat modu: canlı metin akışı
    if (message.isDirectChat) {
      return _buildDirectChatContent(context);
    }

    // Çizimli çözüm hazırlanıyor
    if (message.status == MessageStatus.streaming) {
      return const _MetaSatiri(
        etiket: 'Çözüm hazırlanıyor',
        imlec: true,
      );
    }

    // Hata
    if (message.status == MessageStatus.error) {
      return _HataSatiri(metin: message.text, onRetry: onRetry);
    }

    // Tamamlandı: çizim/ses/adım verisi varsa çözüm kartı
    if (message.requestId != null && message.hasSessionData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MetaSatiri(etiket: 'Çözüm çizildi'),
          const SizedBox(height: 8),
          _CozumKarti(
            message: message,
            onTap: () => onReplay?.call(message.requestId!),
          ),
        ],
      );
    }

    // Düz metin (markdown + maarifx-quiz kartları)
    if (message.text.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MetaSatiri(),
          const SizedBox(height: 6),
          _richBody(context, message.text),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  /// Mesaj gövdesi: markdown parçaları + ```maarifx-quiz``` kartları.
  /// Quiz yoksa tek MarkdownBody döner.
  Widget _richBody(BuildContext context, String text) {
    if (!hasQuizBlock(text)) return _md(context, text);
    final parcalar = parseMessageSegments(text);
    if (parcalar.isEmpty) return _md(context, text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in parcalar)
          if (p.kind == SegmentKind.quiz && p.quiz != null)
            QuizCard(
              key: ValueKey('quiz_${p.quiz!.id}'),
              quiz: p.quiz!,
              onSubmit: onQuizAnswer,
            )
          else
            _md(context, p.text.trim()),
      ],
    );
  }

  Widget _md(BuildContext context, String data) {
    if (data.isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: aiMarkdownStyle(context),
      extensionSet: latexExtensionSet(),
      builders: latexBuilders(),
      onTapLink: (t, href, title) => openMarkdownLink(href),
    );
  }

  /// Direct chat: düşünme sayacı + içerik akışı.
  Widget _buildDirectChatContent(BuildContext context) {
    final isStreaming = message.status == MessageStatus.streaming;
    final hasThinking = message.thinkingWords > 0;
    final hasContent = message.text.isNotEmpty;

    // Henüz hiçbir şey gelmedi
    if (!hasThinking && !hasContent && isStreaming) {
      return const _MetaSatiri(etiket: 'Düşünüyor', imlec: true);
    }

    if (message.status == MessageStatus.error) {
      return _HataSatiri(metin: message.text, onRetry: onRetry);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ThinkingSection(message: message),
        if (hasContent) ...[
          const SizedBox(height: 6),
          _richBody(context, message.text),
        ],
        // Akış sürüyor ve içerik var: metnin altında imleç
        if (isStreaming && hasContent)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: _Imlec(),
          ),
      ],
    );
  }
}

/// AI gövdesi için markdown stili (quiz kartı ve etiketler de bunu kullanır).
MarkdownStyleSheet aiMarkdownStyle(BuildContext context) {
  final ink = context.textPrimary;
  final ink2 = context.textSecondary;
  final line = context.borderColor;
  const mono = AppTheme.fontMono;
  return MarkdownStyleSheet(
    p: TextStyle(fontSize: 14.5, color: ink, height: 1.55),
    strong: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: ink),
    em: TextStyle(fontSize: 14.5, fontStyle: FontStyle.italic, color: ink),
    code: TextStyle(
      fontFamily: mono,
      fontSize: 13,
      color: ink,
      backgroundColor: context.bgTertiary,
    ),
    codeblockDecoration: BoxDecoration(
      color: context.bgTertiary,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      border: Border.all(color: line),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    h1: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ink, height: 1.3),
    h2: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ink, height: 1.3),
    h3: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: ink, height: 1.35),
    h4: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: ink),
    h5: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
    h6: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink2),
    a: TextStyle(color: context.blue, decoration: TextDecoration.underline),
    listBullet: TextStyle(fontSize: 14.5, color: ink2),
    listIndent: 22,
    blockquote: TextStyle(fontSize: 14.5, height: 1.5, color: ink2),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: context.blue, width: 2)),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
    tableBorder: TableBorder.all(color: line, width: 1),
    tableHead: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
    tableBody: TextStyle(fontSize: 13, color: ink),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: line, width: 1)),
    ),
    blockSpacing: 8,
  );
}

/// Cevabın üstündeki meta satırı: f(x) işareti + isteğe bağlı etiket + imleç.
class _MetaSatiri extends StatelessWidget {
  final String? etiket;
  final bool imlec;
  const _MetaSatiri({this.etiket, this.imlec = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const FxIsareti(),
        if (etiket != null) ...[
          const SizedBox(width: 8),
          Text(etiket!, style: context.mono(fontSize: 11.5)),
        ],
        if (imlec) ...[
          const SizedBox(width: 6),
          const _Imlec(),
        ],
      ],
    );
  }
}

/// Düşünme göstergesi — SÜRECİ GÖSTERMEZ, yalnız kelime sayacı.
///
/// Sayaç akış boyunca artar, bitince sabitlenir. "Düşünüyor"/"Düşündü" ve
/// "$n kelime" bilerek AYRI Text widget'ları (testler ve erişilebilirlik).
class _ThinkingSection extends StatelessWidget {
  final ChatMessage message;
  const _ThinkingSection({required this.message});

  @override
  Widget build(BuildContext context) {
    final hasThinking = message.thinkingWords > 0;
    final isStillThinking =
        !message.thinkingDone && message.status == MessageStatus.streaming;
    final n = message.thinkingWords;

    if (!hasThinking) return const _MetaSatiri();

    final renk = context.textMuted;
    return Row(
      children: [
        const FxIsareti(),
        const SizedBox(width: 8),
        Text(isStillThinking ? 'Düşünüyor' : 'Düşündü',
            style: context.mono(fontSize: 11.5, color: renk)),
        Text(' · ', style: context.mono(fontSize: 11.5, color: renk)),
        // Sayı hızla değiştiği için tabular rakam ŞART; yoksa satır zıplar.
        Text('$n kelime',
            style: context.mono(
                fontSize: 11.5, color: context.textSecondary, fontWeight: FontWeight.w500)),
        if (isStillThinking) ...[
          const SizedBox(width: 6),
          const _Imlec(),
        ],
      ],
    );
  }
}

/// Yanıp sönen 2 px imleç: "yazan kalem". Hareket azaltılmışsa sabit durur.
class _Imlec extends StatefulWidget {
  const _Imlec();

  @override
  State<_Imlec> createState() => _ImlecState();
}

class _ImlecState extends State<_Imlec> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sabit = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: sabit ? 1 : (_c.value < 0.5 ? 1 : 0),
        child: Container(width: 2, height: 15, color: context.blue),
      ),
    );
  }
}

/// Hata: sol kırmızı çizgi, metin, "Tekrar dene".
class _HataSatiri extends StatelessWidget {
  final String metin;
  final VoidCallback? onRetry;
  const _HataSatiri({required this.metin, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SolCizgiSatiri(
      renk: context.pen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(metin,
              style: TextStyle(fontSize: 14, height: 1.5, color: context.textSecondary)),
          if (onRetry != null) ...[
            const SizedBox(height: 6),
            MetinEylem(
              etiket: 'Tekrar dene',
              ikon: Icons.refresh_rounded,
              onTap: onRetry!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Çizimli çözüm kartı: küçük resim + "Çözümü izle" + adım ve süre.
class _CozumKarti extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onTap;
  const _CozumKarti({required this.message, required this.onTap});

  static String? sureMetni(int? v) {
    if (v == null || v <= 0) return null;
    // Sunucu süreyi milisaniye verir; küçük değerler (eski kayıtlar) saniyedir.
    final sn = v > 600 ? (v / 1000).round() : v;
    final d = sn ~/ 60, s = sn % 60;
    return '$d:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final parcalar = <String>[
      if (message.totalSteps > 0) '${message.totalSteps} adım',
      if (sureMetni(message.sessionDuration) != null) sureMetni(message.sessionDuration)!,
    ];
    final thumb = message.thumbnailUrl;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.bgPrimary,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb != null)
                        Image.network(
                          thumb,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => ColoredBox(color: context.tint),
                        )
                      else
                        ColoredBox(color: context.tint),
                      Center(
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: context.textPrimary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.play_arrow_rounded,
                              size: 20, color: context.bgSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Çözümü izle',
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: context.textPrimary)),
                    if (parcalar.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(parcalar.join(' · '),
                          style: context.mono(fontSize: 11.5, color: context.textSecondary)),
                    ],
                    const SizedBox(height: 6),
                    Text('Sesli anlatım, fotoğrafın üstüne çizerek',
                        style: TextStyle(fontSize: 12, color: context.textMuted, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
