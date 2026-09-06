import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'class_level_sheet.dart';
import 'ui_bits.dart';

/// Giriş/kayıt iskeleti: üstte yazı-logo, başlık, alanlar; en altta bağlantı.
/// Klavye açılınca kaydırılır; alt bağlantı ekranın dibinde kalır.
class AuthIskelet extends StatelessWidget {
  final String baslik;
  final List<Widget> children;
  final Widget alt;
  const AuthIskelet({
    super.key,
    required this.baslik,
    required this.children,
    required this.alt,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight - 24),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: MaarifxYazi(height: 26)),
                const SizedBox(height: 26),
                Text(
                  baslik,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                ...children,
                const Spacer(),
                const SizedBox(height: 18),
                alt,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Alanın ÜSTÜNDEKİ etiket (içeride kayan etiket yok).
class AlanEtiketi extends StatelessWidget {
  final String metin;
  const AlanEtiketi(this.metin, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(metin, style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
    );
  }
}

/// "Hesabın yok mu?  Kayıt ol" satırı.
class AltBaglanti extends StatelessWidget {
  final String soru;
  final String eylem;
  final VoidCallback onTap;
  const AltBaglanti({super.key, required this.soru, required this.eylem, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(soru, style: TextStyle(fontSize: 13, color: context.textSecondary)),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: context.textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontFamily: AppTheme.fontSans, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          child: Text(eylem),
        ),
      ],
    );
  }
}

/// Form hatası: sol kırmızı çizgi + metin + kapat.
class FormHata extends StatelessWidget {
  final String metin;
  final VoidCallback? onKapat;
  const FormHata({super.key, required this.metin, this.onKapat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SolCizgiSatiri(
        renk: context.pen,
        child: Row(
          children: [
            Expanded(
              child: Text(metin,
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: context.textSecondary)),
            ),
            if (onKapat != null)
              IconButton(
                onPressed: onKapat,
                icon: const Icon(Icons.close_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                color: context.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

/// Göz ikonu: şifre göster/gizle.
class GozDugmesi extends StatelessWidget {
  final bool gizli;
  final VoidCallback onTap;
  const GozDugmesi({super.key, required this.gizli, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(gizli ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
      color: context.textMuted,
      onPressed: onTap,
      tooltip: gizli ? 'Şifreyi göster' : 'Şifreyi gizle',
    );
  }
}

/// Sınıf seçimi: dört seçenekli şerit (8 · 9 · 10 · TYT/AYT).
/// Değerler [kSinifSeviyeleri] ile aynı; sunucu whitelist'i değişmez.
class SinifSeridi extends StatelessWidget {
  final String? secili;
  final ValueChanged<String> onChanged;
  const SinifSeridi({super.key, required this.secili, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.bgPrimary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          for (var i = 0; i < kSinifSeviyeleri.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: secili == kSinifSeviyeleri[i].deger,
                child: InkWell(
                  onTap: () => onChanged(kSinifSeviyeleri[i].deger),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: secili == kSinifSeviyeleri[i].deger ? context.tint : null,
                      border: i == 0
                          ? null
                          : Border(left: BorderSide(color: context.borderColor)),
                    ),
                    child: Text(
                      kSinifSeviyeleri[i].deger == 'TYT/AYT'
                          ? 'TYT/AYT'
                          : kSinifSeviyeleri[i].deger,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: secili == kSinifSeviyeleri[i].deger
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: secili == kSinifSeviyeleri[i].deger
                            ? context.textPrimary
                            : context.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
