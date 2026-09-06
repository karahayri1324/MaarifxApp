import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// Yazı-logo — VARLIK BULUNAMAZSA BİLE bir şey çizer.
///
/// Neden: uygulama kaynağı (lib/) `assets/` olmadan da derlenebiliyor
/// (ör. yalnız kaynak dosyaların taşındığı depolardan). O durumda
/// `Image.asset` sessizce boş bir kutu bırakıyor ve logo "yok" oluyordu.
/// Sıra: temaya uygun PNG → diğer PNG (temaya göre renklendirilmiş silüet)
/// → yazıyla kurulmuş logo. Hiçbir hâlde boşluk kalmaz.
class MaarifxYazi extends StatelessWidget {
  final double height;
  final double? width;
  const MaarifxYazi({super.key, this.height = 24, this.width});

  @override
  Widget build(BuildContext context) {
    final koyu = context.isDarkMode;
    final asil = koyu
        ? 'assets/images/MaarifxyaziKoyu.png'
        : 'assets/images/Maarifxyazi.png';
    final yedek = koyu
        ? 'assets/images/Maarifxyazi.png'
        : 'assets/images/MaarifxyaziKoyu.png';

    return Image.asset(
      asil,
      height: width == null ? height : null,
      width: width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'MaariFx',
      // 1. yedek: diğer temanın dosyası — okunur kalsın diye tek renge boyanır.
      errorBuilder: (context, _, __) => Image.asset(
        yedek,
        height: width == null ? height : null,
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'MaariFx',
        color: context.textPrimary,
        colorBlendMode: BlendMode.srcIn,
        // 2. yedek: hiç varlık yok → yazıyla kur.
        errorBuilder: (context, _, __) => _YaziIleLogo(height: height),
      ),
    );
  }
}

class _YaziIleLogo extends StatelessWidget {
  final double height;
  const _YaziIleLogo({required this.height});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'Maari',
          style: TextStyle(
            fontFamily: AppTheme.fontSans,
            fontSize: height * 0.78,
            fontWeight: FontWeight.w600,
            height: 1,
            letterSpacing: -0.5,
            color: context.textPrimary,
          ),
        ),
        FxIsareti(size: height * 0.78),
      ],
    );
  }
}

/// Yazı-logonun mavi parçası: AI cevabının başındaki küçük işaret.
class FxIsareti extends StatelessWidget {
  final double size;
  const FxIsareti({super.key, this.size = 15});

  @override
  Widget build(BuildContext context) {
    return Text(
      'f(x)',
      style: TextStyle(
        fontFamily: AppTheme.fontSerif,
        fontStyle: FontStyle.italic,
        fontSize: size,
        height: 1,
        color: context.blue,
      ),
    );
  }
}

/// Küçük metin eylemi (buton kutusu yok): ikon + etiket, mavi.
class MetinEylem extends StatelessWidget {
  final String etiket;
  final IconData? ikon;
  final bool ikonSonda;
  final VoidCallback onTap;
  final Color? renk;
  const MetinEylem({
    super.key,
    required this.etiket,
    required this.onTap,
    this.ikon,
    this.ikonSonda = false,
    this.renk,
  });

  @override
  Widget build(BuildContext context) {
    final c = renk ?? context.blue;
    final ikonW = ikon == null ? null : Icon(ikon, size: 15, color: c);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ikonW != null && !ikonSonda) ...[ikonW, const SizedBox(width: 5)],
            Text(etiket,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c)),
            if (ikonW != null && ikonSonda) ...[const SizedBox(width: 3), ikonW],
          ],
        ),
      ),
    );
  }
}

/// Sol çizgili satır: bildirim (sarı), hata (kırmızı), bilgi (mavi).
class SolCizgiSatiri extends StatelessWidget {
  final Color renk;
  final Widget child;
  const SolCizgiSatiri({super.key, required this.renk, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: renk, width: 2))),
      padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
      child: child,
    );
  }
}

/// Baş harf dairesi: tint zemin, mavi harf. Gradyan yok.
class BasHarfDairesi extends StatelessWidget {
  final String harfler;
  final double size;
  const BasHarfDairesi({super.key, required this.harfler, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: context.tint, shape: BoxShape.circle),
      child: Text(
        harfler,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w500,
          height: 1,
          color: context.blue,
        ),
      ),
    );
  }
}

/// Alt sayfaların üstündeki tutamaç (tüm sheet'lerde aynı ölçü).
class SheetTutamac extends StatelessWidget {
  const SheetTutamac({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: context.borderColor,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
