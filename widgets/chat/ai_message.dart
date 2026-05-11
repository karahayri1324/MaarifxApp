import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import '../../config/theme.dart';
import '../../models/chat_message.dart';

class AIMessageWidget extends StatelessWidget {
  final ChatMessage message;
  final Function(int)? onStepChange;
  final Function(String)? onReplay;
  final VoidCallback? onRetry;

  const AIMessageWidget({
    super.key,
    required this.message,
    this.onStepChange,
    this.onReplay,
    this.onRetry,
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

    // Fallback: metin goster (markdown destekli)
    if (message.text.isNotEmpty) {
      return MarkdownBody(
        data: message.text,
        selectable: true,
        styleSheet: _mdStyle(context),
        extensionSet: _latexExtensionSet(),
        builders: _latexBuilders(),
      );
    }

    return const SizedBox.shrink();
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
      h2: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.textPrimary),
      h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.textPrimary),
      h4: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary),
      blockSpacing: 8,
    );
  }

  /// Direct chat modu: thinking + content streaming (ChatGPT tarzı)
  Widget _buildDirectChatContent(BuildContext context) {
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

        // Content bölümü (markdown destekli)
        if (hasContent) ...[
          if (hasThinking) const SizedBox(height: 10),
          MarkdownBody(
            data: message.text,
            selectable: true,
            styleSheet: _mdStyle(context),
            extensionSet: _latexExtensionSet(),
            builders: _latexBuilders(),
          ),
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

// ═══════════════════════════════════════════════════════════
// LaTeX desteği — flutter_markdown için custom inline syntax
// ═══════════════════════════════════════════════════════════
// Desteklenen formatlar:
//   • $...$         inline math
//   • $$...$$       block math
//   • \(...\)       inline math
//   • \[...\]       block math
//   • \frac{a}{b}   bare (delimiter'sız) — AI prompt'larda böyle yazıyor
//   • \dfrac, \tfrac, \sqrt da aynı şekilde
// Bare komutlar tek seviye iç içe parantezleri destekler ({a^{2}} OK).

md.ExtensionSet _latexExtensionSet() {
  return md.ExtensionSet(
    md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    [
      _LatexInlineSyntax(),
      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    ],
  );
}

Map<String, MarkdownElementBuilder> _latexBuilders() => {
      'latex_inline': _LatexBuilder(display: false),
      'latex_block': _LatexBuilder(display: true),
    };

class _LatexInlineSyntax extends md.InlineSyntax {
  _LatexInlineSyntax()
      : super(
          r'\$\$([\s\S]+?)\$\$'
          r'|\\\[([\s\S]+?)\\\]'
          r'|\$([^\$\n]+?)\$'
          r'|\\\(([\s\S]+?)\\\)'
          r'|(\\(?:d|t)?frac\{(?:[^{}]|\{[^{}]*\})*\}\{(?:[^{}]|\{[^{}]*\})*\})'
          r'|(\\sqrt(?:\[[^\]]*\])?\{(?:[^{}]|\{[^{}]*\})*\})',
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    String body;
    bool block;

    if (match.group(1) != null) {
      body = match.group(1)!;
      block = true;
    } else if (match.group(2) != null) {
      body = match.group(2)!;
      block = true;
    } else if (match.group(3) != null) {
      body = match.group(3)!;
      block = false;
    } else if (match.group(4) != null) {
      body = match.group(4)!;
      block = false;
    } else if (match.group(5) != null) {
      body = match.group(5)!;
      block = false;
    } else if (match.group(6) != null) {
      body = match.group(6)!;
      block = false;
    } else {
      return false;
    }

    final tag = block ? 'latex_block' : 'latex_inline';
    parser.addNode(md.Element.text(tag, body));
    return true;
  }
}

class _LatexBuilder extends MarkdownElementBuilder {
  final bool display;
  _LatexBuilder({required this.display});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = element.textContent;
    return Math.tex(
      tex,
      textStyle: preferredStyle,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      onErrorFallback: (err) => Text(
        tex,
        style: (preferredStyle ?? const TextStyle()).copyWith(
          color: Colors.redAccent,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
