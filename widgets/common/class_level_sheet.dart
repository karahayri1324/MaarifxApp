import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../screens/settings/privacy_policy_screen.dart';

/// Sınıf seviyesi seçeneği (tek kaynak).
class SinifSeviyesi {
  final String deger;      // sunucuya giden değer (classLevel)
  final String etiket;     // kullanıcıya görünen ad
  final String? aciklama;  // gerekliyse tek satır açıklama

  const SinifSeviyesi(this.deger, this.etiket, [this.aciklama]);
}

/// ⚠ DEĞERLER kayıt ekranı (register_screen.dart) ve ayarlar dropdown'ı
/// (settings_screen._classDropdown) ile BİREBİR aynı olmalı; sunucu whitelist'i
/// server.js'te ['8','9','10','TYT','AYT','TYT/AYT'].
/// TYT ve AYT AYRI DEĞİL — tek 'TYT/AYT' seçeneği. Listeyi değiştirirsen
/// üç yeri birlikte değiştir, yoksa sunucu 400 döner.
const List<SinifSeviyesi> kSinifSeviyeleri = [
  SinifSeviyesi('8', '8. Sınıf'),
  SinifSeviyesi('9', '9. Sınıf'),
  SinifSeviyesi('10', '10. Sınıf'),
  SinifSeviyesi('TYT/AYT', 'TYT/AYT', '11, 12 ve mezun'),
];

/// Eski/kaldırılmış değerleri listedeki karşılığına çevirir; karşılığı yoksa null
/// (böylece "seçilmemiş" sayılır ve sorulur). 'TYT'/'AYT' → 'TYT/AYT'.
String? normalizeSinifSeviyesi(String? deger) {
  if (deger == null) return null;
  if (deger == 'TYT' || deger == 'AYT') return 'TYT/AYT';
  return kSinifSeviyeleri.any((s) => s.deger == deger) ? deger : null;
}

/// Sınıf seviyesi sorar. Seçim yapıldıysa değeri, vazgeçildiyse null döner.
///
/// `mevcut` verilirse "değiştirme" kipi (başlık + buton metni değişir, gizlilik
/// notu gösterilmez). Barrier'a dokunma ve aşağı sürükleme ile KAPANMAZ:
/// chat_input gönderim çağrısından hemen sonra composer'ı temizlediği için
/// yanlışlıkla kapanma kullanıcının seçtiği fotoğrafı boşa harcar. Vazgeçme
/// yolu açıktır: 'Vazgeç' butonu ve geri tuşu null döndürür.
Future<String?> showSinifSeviyesiSheet(BuildContext context, {String? mevcut}) {
  return showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (_) => _SinifSeviyesiSheet(mevcut: normalizeSinifSeviyesi(mevcut)),
  );
}

class _SinifSeviyesiSheet extends StatefulWidget {
  final String? mevcut;

  const _SinifSeviyesiSheet({this.mevcut});

  @override
  State<_SinifSeviyesiSheet> createState() => _SinifSeviyesiSheetState();
}

class _SinifSeviyesiSheetState extends State<_SinifSeviyesiSheet> {
  String? _secili;
  late final TapGestureRecognizer _politikaTap;

  bool get _degistirme => widget.mevcut != null;

  @override
  void initState() {
    super.initState();
    _secili = widget.mevcut;
    _politikaTap = TapGestureRecognizer()
      ..onTap = () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
        );
      };
  }

  @override
  void dispose() {
    _politikaTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Başlık ve butonlar SABİT, yalnız seçenek listesi kaydırılır: alçak
    // ekranda (ör. 360x600) tek bir kaydırılabilir kolon kullanılırsa 'Devam'
    // ekranın dışında kalıyordu (ölçüldü).
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Diğer sheet'lerdeki drag handle ile aynı ölçü/renk
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.school_outlined,
                              color: AppTheme.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _degistirme ? 'Sınıf seviyen' : 'Kaçıncı sınıftasın?',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _degistirme
                          ? 'Çözümleri bu seviyeye göre anlatıyorum. İstediğin zaman '
                              'değiştirebilirsin.'
                          : 'Çözümü sana uygun anlatabilmem için sınıfını seç. '
                              'Bir kez soruyorum — sonraki sorularında bu seviyeyi '
                              'kullanacağım.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: context.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            // KAYDIRILAN tek bölüm: seçenek listesi
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in kSinifSeviyeleri) ...[
                      _SeviyeSatiri(
                        seviye: s,
                        secili: _secili == s.deger,
                        onTap: () => setState(() => _secili = s.deger),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            // SABİT alt bölüm: not + butonlar (her ekran boyunda görünür)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    if (!_degistirme) ...[
                      // Text.rich (RichText DEĞİL): DefaultTextStyle'ı miras alır,
                      // yani uygulamanın yazı tipiyle aynı görünür.
                      Text.rich(
                        textAlign: TextAlign.center,
                        TextSpan(
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: context.textMuted,
                          ),
                          children: [
                            const TextSpan(text: 'Devam ederek '),
                            TextSpan(
                              text: 'Gizlilik Politikası',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: _politikaTap,
                            ),
                            const TextSpan(
                                text: '\'nı kabul etmiş olursun. Sorularını '
                                    'yalnızca çözmek için kullanırım.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    ElevatedButton(
                      onPressed: _secili == null
                          ? null
                          : () => Navigator.of(context).pop(_secili),
                      child: Text(_degistirme ? 'Kaydet' : 'Devam'),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }
}

/// Seçenek satırı — ModelSelector'daki seçenek kartıyla aynı görsel dil
/// (kenarlık, seçilince primary tint + check_circle).
class _SeviyeSatiri extends StatelessWidget {
  final SinifSeviyesi seviye;
  final bool secili;
  final VoidCallback onTap;

  const _SeviyeSatiri({
    required this.seviye,
    required this.secili,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: secili ? AppTheme.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: secili ? AppTheme.primary : context.borderColor,
            width: secili ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    seviye.etiket,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  if (seviye.aciklama != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      seviye.aciklama!,
                      style: TextStyle(fontSize: 12, color: context.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (secili)
              const Icon(Icons.check_circle_rounded,
                  size: 20, color: AppTheme.primary)
            else
              Icon(Icons.circle_outlined,
                  size: 20, color: context.textMuted.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}
