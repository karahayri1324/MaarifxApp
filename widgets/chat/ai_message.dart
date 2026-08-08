import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../config/theme.dart';
import '../../models/chat_message.dart';
import '../../models/quiz_block.dart';
import '../../models/server_notice.dart';
import '../common/server_notice_body.dart';
import 'markdown_math.dart';
import 'quiz_card.dart';

class AIMessageWidget extends StatelessWidget {
  final ChatMessage message;
  final Function(int)? onStepChange;
  final Function(String)? onReplay;
  final VoidCallback? onRetry;

  /// ```maarifx-quiz``` kartından cevap gönderilince çağrılır (fence metniyle).
  final Future<void> Function(String fence)? onQuizAnswer;

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: context.bgPrimary,
            boxShadow: AppTheme.shadowSm,
          ),
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/images/karahayri.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Message Content
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.aiBubbleBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMd),
                topRight: Radius.circular(AppTheme.radiusMd),
                bottomRight: Radius.circular(AppTheme.radiusMd),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: context.borderColor),
              boxShadow: AppTheme.shadowSm,
            ),
            child: _buildContent(context),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    // SUNUCU BİLDİRİMİ: kota/ban/duyuru. Modal yerine sohbetin içinde, AI
    // cevabı gibi görünür (ChatGPT'nin limit mesajı gibi) — kullanıcı yazdığı
    // mesajı ve bağlamı kaybetmez, geçmişte de kalır.
    if (message.notice != null) {
      return ServerNoticeBody(notice: message.notice!);
    }

    // Direct chat modu: canli metin streaming
    if (message.isDirectChat) {
      return _buildDirectChatContent(context);
    }

    // Streaming: spinner ile "Çözüm hazırlanıyor..."
    if (message.status == MessageStatus.streaming) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Çözüm hazırlanıyor...',
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    // Error
    if (message.status == MessageStatus.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 18, color: AppTheme.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.text,
                  style: const TextStyle(fontSize: 14, color: AppTheme.danger),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Tekrar Dene'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: BorderSide(color: AppTheme.primary.withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    // Complete: "Çözümü İzle" butonu — sadece session verisi (çizim/ses/adım) varsa göster
    if (message.requestId != null && message.hasSessionData) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => onReplay?.call(message.requestId!),
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: const Text('Çözümü İzle'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            side: BorderSide(color: AppTheme.primary.withOpacity(0.3)),
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
          ),
        ),
      );
    }

    // Fallback: metin goster (markdown + maarifx-quiz kartları)
    if (message.text.isNotEmpty) {
      return _richBody(context, message.text);
    }

    return const SizedBox.shrink();
  }

  /// Mesaj gövdesi: markdown parçaları + ```maarifx-quiz``` kartları.
  /// Quiz yoksa tek MarkdownBody döner — eski davranışla birebir aynı.
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
      styleSheet: _mdStyle(context),
      extensionSet: latexExtensionSet(),
      builders: latexBuilders(),
      onTapLink: (t, href, title) => openMarkdownLink(href),
    );
  }

  MarkdownStyleSheet _mdStyle(BuildContext context) {
    return MarkdownStyleSheet(
      p: TextStyle(fontSize: 14, color: context.textPrimary, height: 1.5),
      strong: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary),
      em: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: context.textPrimary),
      code: TextStyle(
        fontSize: 13,
        color: AppTheme.primary,
        backgroundColor: AppTheme.primary.withOpacity(0.08),
      ),
      codeblockDecoration: BoxDecoration(
        color: context.bgTertiary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      h1: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: context.textPrimary),
      h2: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.textPrimary),
      h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.textPrimary),
      h4: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary),
      h5: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary),
      h6: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textSecondary),
      a: TextStyle(color: AppTheme.primary, decoration: TextDecoration.underline),
      listBullet: TextStyle(fontSize: 14, color: context.textPrimary),
      blockquote: TextStyle(fontSize: 14, height: 1.5, color: context.textSecondary),
      blockquoteDecoration: BoxDecoration(
        color: context.bgTertiary,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      tableBorder: TableBorder.all(color: context.borderColor, width: 1),
      tableHead: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary),
      tableBody: TextStyle(fontSize: 13, color: context.textPrimary),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.borderColor, width: 1)),
      ),
      blockSpacing: 8,
    );
  }

  /// Direct chat modu: thinking + content streaming (ChatGPT tarzı)
  Widget _buildDirectChatContent(BuildContext context) {
    if (message.notice != null) {
      return ServerNoticeBody(notice: message.notice!);
    }

    final isStreaming = message.status == MessageStatus.streaming;
    final hasThinking = message.thinkingText.isNotEmpty;
    final hasContent = message.text.isNotEmpty;

    // Henuz hicbir sey gelmedi
    if (!hasThinking && !hasContent && isStreaming) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Düşünüyor...',
            style: TextStyle(
              fontSize: 14,
              color: context.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    // Error
    if (message.status == MessageStatus.error) {
      return Text(
        message.text,
        style: const TextStyle(fontSize: 14, color: AppTheme.danger),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thinking bölümü (açılır/kapanır)
        if (hasThinking) _ThinkingSection(message: message),

        // Content bölümü (markdown + maarifx-quiz kartları)
        if (hasContent) ...[
          if (hasThinking) const SizedBox(height: 10),
          _richBody(context, message.text),
        ],

        // Streaming göstergesi (content gelmeye basladiysa)
        if (isStreaming && hasContent)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                    context.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}

/// Thinking bölümü — düşünme sürecini açılır/kapanır şekilde gösterir
class _ThinkingSection extends StatefulWidget {
  final ChatMessage message;
  const _ThinkingSection({required this.message});

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isStillThinking = !widget.message.thinkingDone &&
        widget.message.status == MessageStatus.streaming;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: tıklanabilir açılır/kapanır
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isStillThinking)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  )
                else
                  const Icon(Icons.psychology_rounded,
                      size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  isStillThinking ? 'Düşünüyor...' : 'Düşünce süreci',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: AppTheme.primary,
                ),
              ],
            ),
          ),
        ),

        // Expanded thinking content
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.bgTertiary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.borderColor),
            ),
            child: SelectableText(
              widget.message.thinkingText,
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondary,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
