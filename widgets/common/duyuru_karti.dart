import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../services/uzak_ayarlar.dart';
import 'ui_bits.dart';

/// DUYURU ("yeni bir şey yayınladık") — 2026-11-08. Admin panelinden yazılır;
/// uygulama açılışında görülmemiş en yeni duyuru BİR KEZ gösterilir.
///
/// Görsel dil uygulamanın kendisi: alt sayfa (diğer sheet'lerle aynı tutamaç),
/// mono üst etiket + f(x) işareti (AI cevabının başlığı gibi), rozet/gradyan yok.
/// Buton varsa altında NEREYE gideceği yazar ("maarifx.com · tarayıcıda açılır").
Future<void> showDuyuru(BuildContext context, Duyuru d) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DuyuruKarti(duyuru: d),
  );
}

class DuyuruKarti extends StatelessWidget {
  final Duyuru duyuru;
  const DuyuruKarti({super.key, required this.duyuru});

  static const _aylar = ['OCAK', 'ŞUBAT', 'MART', 'NİSAN', 'MAYIS', 'HAZİRAN', 'TEMMUZ', 'AĞUSTOS', 'EYLÜL', 'EKİM', 'KASIM', 'ARALIK'];

  String get _etiket {
    final t = duyuru.tarih;
    if (t == null) return 'DUYURU';
    return 'DUYURU · ${t.day} ${_aylar[t.month - 1]}';
  }

  Uri? get _hedef {
    final u = Uri.tryParse(duyuru.butonUrl ?? '');
    return (u != null && u.scheme == 'https' && u.host.isNotEmpty) ? u : null;
  }

  Future<void> _ac(BuildContext context) async {
    final u = _hedef;
    Navigator.of(context).pop();
    if (u == null) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hedef = _hedef;
    final eylemVar = hedef != null && duyuru.butonEtiket != null;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: SheetTutamac()),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const FxIsareti(size: 14),
                      const SizedBox(width: 8),
                      Text(_etiket, style: context.eyebrow),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    duyuru.baslik,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                      color: context.textPrimary,
                    ),
                  ),
                  if (duyuru.gorselUrl != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          duyuru.gorselUrl!,
                          fit: BoxFit.cover,
                          // İnmezse görsel alanı sessizce kaybolmaz ama göze batmaz.
                          errorBuilder: (_, __, ___) => Container(color: context.bgTertiary),
                          loadingBuilder: (c, child, p) => p == null ? child : Container(color: context.bgTertiary),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    duyuru.metin,
                    style: TextStyle(fontSize: 15, height: 1.55, color: context.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: eylemVar
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        key: const ValueKey('duyuru_eylem'),
                        onPressed: () => _ac(context),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(child: Text(duyuru.butonEtiket!, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 6),
                            const Icon(Icons.north_east_rounded, size: 16),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${hedef.host.replaceFirst(RegExp(r'^www\.'), '')} · tarayıcıda açılır',
                        textAlign: TextAlign.center,
                        style: context.mono(fontSize: 11.5),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        key: const ValueKey('duyuru_tamam'),
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(foregroundColor: context.textSecondary),
                        child: const Text('Kapat'),
                      ),
                    ],
                  )
                : ElevatedButton(
                    key: const ValueKey('duyuru_tamam'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Tamam'),
                  ),
          ),
        ],
      ),
    );
  }
}
