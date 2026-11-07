import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../services/uzak_ayarlar.dart';
import 'ui_bits.dart';

/// GÜNCELLEME KAPISI (2026-11-08): MaterialApp.builder'da TÜM ekranların üstünde.
///
///  * Zorunlu güncelleme (build < admin'in "minimum build"u): uygulama kilitlenir,
///    tek çıkış "Güncelle" (mağaza). Navigator'ın üstünde olduğu için hiçbir
///    ekran/diyalog bunu aşamaz.
///  * İsteğe bağlı (build < "son build"): altta kapatılabilir kart; "Sonra" o
///    sürüm için bir daha göstermez.
///
/// Uygulama öne gelince ayarlar yeniden çekilir (en sık 10 dk'da bir), yani
/// admin minimum sürümü yükselttiğinde açık uygulamalar da kilitlenir.
/// Ağ yoksa / sunucu yanıt vermezse KİLİTLEMEZ.
class GuncellemeKapisi extends StatefulWidget {
  final Widget child;
  const GuncellemeKapisi({super.key, required this.child});

  @override
  State<GuncellemeKapisi> createState() => _GuncellemeKapisiState();
}

class _GuncellemeKapisiState extends State<GuncellemeKapisi> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<UzakAyarlar?>()?.yukle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uzak = context.watch<UzakAyarlar?>();
    if (uzak == null) return widget.child;
    final g = uzak.guncelleme;
    return Stack(
      children: [
        widget.child,
        if (g != null && !g.zorunlu && uzak.istegeBagliGoster)
          // ÜSTTE: alttaki yazma alanını (ana eylem) kapatmasın.
          Positioned(
            left: 12,
            right: 12,
            top: 8 + MediaQuery.of(context).padding.top,
            child: _IstegeBagliKart(bilgi: g, onSonra: uzak.istegeBagliErtele),
          ),
        if (g != null && g.zorunlu) Positioned.fill(child: GuncellemeEkrani(bilgi: g, surum: uzak.surumAdi, buildNo: uzak.build)),
      ],
    );
  }
}

Future<void> _magazayiAc(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Tam ekran, kapatılamaz güncelleme ekranı.
class GuncellemeEkrani extends StatelessWidget {
  final GuncellemeBilgisi bilgi;
  final String surum;
  final int? buildNo;
  const GuncellemeEkrani({super.key, required this.bilgi, this.surum = '', this.buildNo});

  @override
  Widget build(BuildContext context) {
    final mesaj = bilgi.mesaj.isNotEmpty
        ? bilgi.mesaj
        : 'Uygulamanın yeni bir sürümü yayınlandı. Devam etmek için güncellemen gerekiyor.';
    return Material(
      color: context.bgSecondary,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: MaarifxYazi(height: 28)),
                  const SizedBox(height: 40),
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: context.tint, shape: BoxShape.circle),
                      child: Icon(Icons.system_update_rounded, size: 36, color: context.blue),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Güncelleme gerekli',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    mesaj,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14.5, height: 1.5, color: context.textSecondary),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    key: const ValueKey('guncelle_buton'),
                    onPressed: bilgi.magazaUrl.isEmpty ? null : () => _magazayiAc(bilgi.magazaUrl),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text('Güncelle'),
                  ),
                  if (surum.isNotEmpty || buildNo != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      surum.isEmpty ? 'Yüklü sürüm: $buildNo' : 'Yüklü sürüm: $surum${buildNo != null ? ' ($buildNo)' : ''}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: context.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IstegeBagliKart extends StatelessWidget {
  final GuncellemeBilgisi bilgi;
  final VoidCallback onSonra;
  const _IstegeBagliKart({required this.bilgi, required this.onSonra});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('istege_bagli_guncelleme'),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
        decoration: BoxDecoration(
          color: context.bgPrimary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderColor),
          boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.system_update_rounded, color: context.blue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yeni sürüm var',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: context.textPrimary)),
                      const SizedBox(height: 3),
                      Text(
                        bilgi.mesaj.isNotEmpty ? bilgi.mesaj : 'Uygulamanın yeni bir sürümü var.',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, height: 1.4, color: context.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onSonra,
                  style: TextButton.styleFrom(foregroundColor: context.textSecondary),
                  child: const Text('Sonra'),
                ),
                if (bilgi.magazaUrl.isNotEmpty)
                  TextButton(
                    onPressed: () => _magazayiAc(bilgi.magazaUrl),
                    style: TextButton.styleFrom(foregroundColor: context.blue),
                    child: const Text('Güncelle', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
