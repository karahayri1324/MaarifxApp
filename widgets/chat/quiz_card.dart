import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/quiz_block.dart';
import 'markdown_math.dart';

/// ```maarifx-quiz``` bloğunu etkileşimli soru kartına çevirir.
///
/// Cevap gönderilince `onSubmit` ile QUIZ_ANSWER.md fence'i üretilir ve
/// normal bir user mesajı olarak modele gider. Doğru/yanlış BURADA
/// hesaplanmaz — değerlendirme modeldedir (answer alanı UI'a hiç gelmez).
class QuizCard extends StatefulWidget {
  final QuizBlock quiz;

  /// fence metnini alır (```maarifx-quiz-answer …```), sohbete gönderir.
  /// Cevabı gönderir. Dönen `true` = gerçekten gönderildi.
  /// `false` dönerse kart kilitlenmez, kullanıcı yeniden deneyebilir.
  final Future<bool> Function(String fence)? onSubmit;

  const QuizCard({super.key, required this.quiz, this.onSubmit});

  @override
  State<QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<QuizCard> {
  final _store = QuizAnswerStore.instance;

  // tip başına yerel seçim durumu
  final TextEditingController _text = TextEditingController();
  String? _single;                       // mcq
  bool? _bool;                           // true_false
  final Set<String> _multi = {};         // multi / checklist
  final Map<String, String> _match = {}; // match: solId → sağId
  List<QuizOption> _order = [];          // order
  final Map<String, TextEditingController> _blanks = {}; // fill
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _order = List.of(widget.quiz.items);
    for (final b in widget.quiz.blanks) {
      _blanks[b.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    for (final c in _blanks.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _answered => _store.isAnswered(widget.quiz.id);

  // ─── gönderim ───────────────────────────────────────────────────────
  Object? _collect() {
    final q = widget.quiz;
    switch (q.type) {
      case QuizType.open:
      case QuizType.short:
        final v = _text.text.trim();
        return v.isEmpty ? null : v;
      case QuizType.mcq:
        return _single;
      case QuizType.trueFalse:
        return _bool;
      case QuizType.multi:
      case QuizType.checklist:
        return _multi.isEmpty ? null : _multi.toList();
      case QuizType.match:
        if (_match.length < q.left.length) return null;
        return Map<String, String>.from(_match);
      case QuizType.order:
        return _order.map((e) => e.id).toList();
      case QuizType.fill:
        final m = <String, String>{};
        for (final e in _blanks.entries) {
          final v = e.value.text.trim();
          if (v.isEmpty) return null;
          m[e.key] = v;
        }
        return m;
      case QuizType.unknown:
        return null;
    }
  }

  Future<void> _submit() async {
    final ans = _collect();
    if (ans == null || _sending) return;
    setState(() => _sending = true);
    final fence = formatQuizAnswerMessage(
      quizId: widget.quiz.id,
      type: widget.quiz.rawType,
      userAnswer: ans,
      attempt: _store.attemptOf(widget.quiz.id) + 1,
    );
    try {
      // KİLİT BURADA KURULMAZ. Eskiden `_store.record` await'ten ÖNCEYDİ:
      // internet yokken cevap hiç gitmediği hâlde kart "cevaplandı" diye
      // kilitleniyordu. Kaydı sonrasına almak da yetmiyor — hata balonundaki
      // "Tekrar Dene" yolu bu karttan geçmediği için orada kilit hiç kurulmaz,
      // aynı cevap ikinci kez gönderilebilirdi. Kayıt artık gönderimin TEK
      // ortak noktasında: ChatProvider.sendMessage başarı yolunda.
      await widget.onSubmit?.call(fence);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ─── görünüm ────────────────────────────────────────────────────────
  static const Map<QuizType, String> _etiket = {
    QuizType.open: 'Açık uçlu',
    QuizType.short: 'Kısa cevap',
    QuizType.mcq: 'Çoktan seçmeli',
    QuizType.multi: 'Birden fazla doğru',
    QuizType.trueFalse: 'Doğru / Yanlış',
    QuizType.match: 'Eşleştirme',
    QuizType.order: 'Sıralama',
    QuizType.checklist: 'Kontrol listesi',
    QuizType.fill: 'Boşluk doldurma',
  };

  @override
  Widget build(BuildContext context) {
    final q = widget.quiz;
    final answered = _answered;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: context.bgPrimary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, q, answered),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // MdLabel: markdown + LaTeX. Eskiden düz Text'ti → matematik/fen
                // sorularında "$v=\\frac{x}{t}$" ham TeX olarak görünüyordu.
                if (q.heading.isNotEmpty)
                  MdLabel(
                    q.heading,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: context.textPrimary,
                    ),
                  ),
                if (q.heading.isNotEmpty) const SizedBox(height: 12),
                _body(context, q, answered),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, QuizBlock q, bool answered) {
    final parcalar = <String>[
      answered ? 'Cevabın gönderildi' : 'Soru',
      _etiket[q.type] ?? 'Soru',
      if (q.difficulty.isNotEmpty && !answered) q.difficulty,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Text(trBuyuk(parcalar.join(' · ')), style: context.eyebrow),
    );
  }

  Widget _body(BuildContext context, QuizBlock q, bool answered) {
    if (answered) return _cevaplandi(context, q);
    switch (q.type) {
      case QuizType.open:
        return _yaziAlani(context, q, satir: 4);
      case QuizType.short:
        return _yaziAlani(context, q, satir: 1);
      case QuizType.trueFalse:
        return _dogruYanlis(context);
      case QuizType.mcq:
        return _tekSecim(context, q);
      case QuizType.multi:
        return _cokSecim(context, q, q.options, 'Cevabı gönder');
      case QuizType.checklist:
        return _cokSecim(context, q, q.items, 'İşaretlediklerimi gönder');
      case QuizType.match:
        return _eslestir(context, q);
      case QuizType.order:
        return _sirala(context, q);
      case QuizType.fill:
        return _bosluk(context, q);
      case QuizType.unknown:
        return const SizedBox.shrink();
    }
  }

  // ─── cevaplanmış görünüm ────────────────────────────────────────────
  Widget _cevaplandi(BuildContext context, QuizBlock q) {
    final a = _store.answerOf(q.id);
    String metin;
    if (a is bool) {
      metin = a ? 'Doğru' : 'Yanlış';
    } else if (a is List) {
      metin = a.map((e) => _etiketBul(q, e.toString())).join(' · ');
    } else if (a is Map) {
      metin = a.entries
          .map((e) => '${_etiketBul(q, e.key.toString())} → '
              '${_etiketBul(q, e.value.toString())}')
          .join('\n');
    } else {
      // Düz metin cevap: mcq/short'ta şık id'si olabilir → etiketi varsa onu göster
      metin = a == null ? '' : _etiketBul(q, a.toString());
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.bgSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: context.borderColor),
      ),
      child: MdLabel(
        metin.isEmpty ? '—' : metin,
        style: TextStyle(fontSize: 13.5, height: 1.45, color: context.textSecondary),
      ),
    );
  }

  /// id → label (mcq/multi/match/order/checklist); bulunamazsa id'nin kendisi.
  String _etiketBul(QuizBlock q, String id) {
    for (final l in [q.options, q.left, q.right, q.items]) {
      for (final o in l) {
        if (o.id == id) return o.label;
      }
    }
    return id;
  }

  // ─── tip görünümleri ────────────────────────────────────────────────
  Widget _gonderButonu(String etiket, {bool aktif = true}) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: (aktif && !_sending) ? _submit : null,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(38)),
        child: _sending
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(etiket),
      ),
    );
  }

  Widget _yaziAlani(BuildContext context, QuizBlock q, {required int satir}) {
    return Column(
      children: [
        TextField(
          controller: _text,
          maxLines: satir,
          minLines: satir,
          textInputAction:
              satir > 1 ? TextInputAction.newline : TextInputAction.done,
          onSubmitted: satir == 1 ? (_) => _submit() : null,
          onChanged: (_) => setState(() {}),
          style: TextStyle(fontSize: 14, color: context.textPrimary),
          decoration: InputDecoration(
            hintText: q.placeholder.isNotEmpty ? q.placeholder : 'Cevabını yaz…',
            hintStyle: TextStyle(fontSize: 14, color: context.textMuted),
            fillColor: context.bgSecondary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        if (q.minChars > 0 && _text.text.trim().length < q.minChars)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('En az ${q.minChars} karakter',
                  style: TextStyle(fontSize: 11.5, color: context.textMuted)),
            ),
          ),
        const SizedBox(height: 10),
        _gonderButonu('Gönder',
            aktif: _text.text.trim().length >= q.minChars &&
                _text.text.trim().isNotEmpty),
      ],
    );
  }

  Widget _dogruYanlis(BuildContext context) {
    Widget btn(String etiket, bool deger) {
      final secili = _bool == deger;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: () => setState(() => _bool = deger),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: secili ? context.tint : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: secili ? context.blue : context.borderColor),
            ),
            child: Text(etiket,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: secili ? FontWeight.w500 : FontWeight.w400,
                  color: secili ? context.textPrimary : context.textSecondary,
                )),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [
          btn('Doğru', true),
          const SizedBox(width: 8),
          btn('Yanlış', false),
        ]),
        const SizedBox(height: 10),
        _gonderButonu('Gönder', aktif: _bool != null),
      ],
    );
  }

  Widget _tekSecim(BuildContext context, QuizBlock q) {
    return Column(
      children: [
        for (final o in q.options) ...[
          _secenekSatiri(
            context,
            secili: _single == o.id,
            cokluMu: false,
            rozet: o.id,
            etiket: o.label,
            onTap: () => setState(() => _single = o.id),
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 6),
        _gonderButonu('Gönder', aktif: _single != null),
      ],
    );
  }

  Widget _cokSecim(
      BuildContext context, QuizBlock q, List<QuizOption> liste, String btnEtiket) {
    return Column(
      children: [
        for (final o in liste) ...[
          _secenekSatiri(
            context,
            secili: _multi.contains(o.id),
            cokluMu: true,
            rozet: o.id,
            etiket: o.label,
            onTap: () => setState(() {
              if (!_multi.remove(o.id)) _multi.add(o.id);
            }),
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 6),
        _gonderButonu(btnEtiket, aktif: _multi.isNotEmpty),
      ],
    );
  }

  Widget _secenekSatiri(
    BuildContext context, {
    required bool secili,
    required bool cokluMu,
    required String rozet,
    required String etiket,
    required VoidCallback onTap,
  }) {
    // Harf yalnız TEK harfli şık id'lerinde anlamlı (A/B/C/D).
    final rozetGoster = rozet.length == 1;
    final isaret = cokluMu
        ? Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: secili ? context.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: secili ? context.blue : context.textMuted, width: 1.5),
            ),
            child: secili ? Icon(Icons.check_rounded, size: 12, color: context.onBlue) : null,
          )
        : Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: secili ? context.blue : context.textMuted,
                width: secili ? 5 : 1.5,
              ),
            ),
          );
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: secili ? context.tint : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: isaret),
            const SizedBox(width: 10),
            if (rozetGoster) ...[
              SizedBox(
                width: 14,
                child: Text(rozet, style: context.mono(fontSize: 12)),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: MdLabel(
                etiket,
                style: TextStyle(
                  fontSize: 13.8,
                  height: 1.4,
                  color: context.textPrimary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eslestir(BuildContext context, QuizBlock q) {
    return Column(
      children: [
        for (final l in q.left) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            margin: const EdgeInsets.only(bottom: 9),
            decoration: BoxDecoration(
              color: context.bgSecondary,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: _match.containsKey(l.id) ? context.blue : context.borderColor,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MdLabel(l.label,
                    style: TextStyle(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w500,
                        color: context.textPrimary)),
                const SizedBox(height: 7),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _match[l.id],
                    hint: Text('Eşleşeni seç…',
                        style: TextStyle(fontSize: 13, color: context.textMuted)),
                    icon: Icon(Icons.expand_more_rounded, color: context.textSecondary),
                    dropdownColor: context.bgPrimary,
                    style: TextStyle(fontSize: 13, color: context.textPrimary),
                    items: [
                      for (final r in q.right)
                        DropdownMenuItem(
                          value: r.id,
                          child: Text(r.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      if (v != null) _match[l.id] = v;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
        _gonderButonu('Gönder', aktif: _match.length == q.left.length),
      ],
    );
  }

  Widget _sirala(BuildContext context, QuizBlock q) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Sürükleyerek sırala',
                style: TextStyle(fontSize: 11.5, color: context.textMuted)),
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: (eski, yeni) => setState(() {
            if (yeni > eski) yeni -= 1;
            _order.insert(yeni, _order.removeAt(eski));
          }),
          children: [
            for (var i = 0; i < _order.length; i++)
              Container(
                key: ValueKey(_order[i].id),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: context.bgSecondary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text('${i + 1}', style: context.mono(fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MdLabel(_order[i].label,
                          style: TextStyle(
                              fontSize: 13.8, height: 1.4, color: context.textPrimary)),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: Icon(Icons.drag_handle_rounded,
                          size: 20, color: context.textMuted),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        _gonderButonu('Gönder'),
      ],
    );
  }

  Widget _bosluk(BuildContext context, QuizBlock q) {
    // template içindeki ___ sırası blanks sırasıyla eşleşir (INTERACTIVE_BLOCKS.md).
    final parcalar = q.template.split('___');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: context.bgSecondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: context.borderColor),
          ),
          // Boşluk numaraları markdown **kalın**a çevrilir → şablonun geri kalanı
          // MdLabel'dan geçtiği için LaTeX/markdown da doğru basılır.
          child: MdLabel(
            [
              for (var i = 0; i < parcalar.length; i++)
                parcalar[i] + (i < parcalar.length - 1 ? ' **(${i + 1})** ' : ''),
            ].join(),
            style: TextStyle(fontSize: 14, height: 1.6, color: context.textPrimary),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < q.blanks.length; i++) ...[
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('${i + 1}', style: context.mono(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _blanks[q.blanks[i].id],
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 13.8, color: context.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '${i + 1}. boşluk',
                    hintStyle: TextStyle(fontSize: 13, color: context.textMuted),
                    fillColor: context.bgSecondary,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 2),
        _gonderButonu('Gönder',
            aktif: _blanks.values.every((c) => c.text.trim().isNotEmpty)),
      ],
    );
  }
}
