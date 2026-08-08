import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

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
//
// Bu dosya ai_message.dart'tan ÇIKARILDI: quiz kartları da aynı markdown+LaTeX
// motorunu kullanabilsin diye (eskiden kart içi düz Text'ti → "$v=\frac{x}{t}$"
// gibi bir şık ham TeX olarak görünüyordu).

md.ExtensionSet latexExtensionSet() {
  return md.ExtensionSet(
    md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    [
      _LatexInlineSyntax(),
      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    ],
  );
}

Map<String, MarkdownElementBuilder> latexBuilders() => {
      'latex_inline': _LatexBuilder(display: false),
      'latex_block': _LatexBuilder(display: true),
    };

/// Markdown bağlantısına dokununca tarayıcıda açar.
/// ÖNCEDEN: onTapLink hiç bağlanmamıştı → linkler mavi görünüp hiçbir şey yapmıyordu.
/// Şema BEYAZ LİSTE (http/https/mailto) — model uydurma bir şema üretse bile açılmaz.
Future<void> openMarkdownLink(String? href) async {
  if (href == null || href.isEmpty) return;
  final uri = Uri.tryParse(href);
  if (uri == null) return;
  if (!const {'http', 'https', 'mailto'}.contains(uri.scheme)) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

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

/// Quiz kartı gibi KISA etiketler için markdown + LaTeX.
///
/// Blok öğeleri (liste/başlık/tablo) bir şık etiketinin içinde anlamsız ve
/// düzeni bozar; satır sonları boşluğa indirgenir. Metin boşsa hiç widget
/// üretmez, böylece Column'da boşluk açmaz.
class MdLabel extends StatelessWidget {
  final String data;
  final TextStyle style;
  final TextAlign? textAlign;

  const MdLabel(this.data, {super.key, required this.style, this.textAlign});

  @override
  Widget build(BuildContext context) {
    final tek = data.replaceAll(RegExp(r'\r?\n+'), ' ').trim();
    if (tek.isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: tek,
      selectable: false,
      fitContent: true,
      styleSheet: MarkdownStyleSheet(
        p: style,
        strong: style.copyWith(fontWeight: FontWeight.w700),
        em: style.copyWith(fontStyle: FontStyle.italic),
        code: style.copyWith(fontFamily: 'monospace', fontSize: (style.fontSize ?? 14) - 1),
        // Etiket içinde blok boşluğu istemiyoruz
        blockSpacing: 0,
        pPadding: EdgeInsets.zero,
        textAlign: _wrapAlign(textAlign),
      ),
      extensionSet: latexExtensionSet(),
      builders: latexBuilders(),
      onTapLink: (t, href, title) => openMarkdownLink(href),
    );
  }

  static WrapAlignment _wrapAlign(TextAlign? a) {
    switch (a) {
      case TextAlign.center:
        return WrapAlignment.center;
      case TextAlign.right:
      case TextAlign.end:
        return WrapAlignment.end;
      default:
        return WrapAlignment.start;
    }
  }
}
