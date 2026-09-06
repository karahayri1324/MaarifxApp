import 'package:flutter/material.dart';
import '../../config/theme.dart';

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
