import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Gizlilik Politikası (KVKK) — 2026-11-08: TEK KAYNAK web sitesi.
///
/// Uygulama içinde ayrı bir metin TUTULMAZ (eskiden uygulamadaki kopya sitedekinden
/// eskiydi: Firebase maddesi, KVKK 11. madde harfleri ç/ğ, iletişim bölümü eksikti).
/// Her giriş noktası sayfayı telefonun tarayıcısında açar.
///
/// ⚠ Adres büyük/küçük harfe duyarlı: /Gizlilik 200, /gizlilik 404 (2026-11-08 ölçüldü).
const String kGizlilikPolitikasiUrl = 'https://maarifx.com/Gizlilik';

/// Tarayıcı açılamazsa (tarayıcı yok / engelli) kullanıcı çıkmaza düşmesin:
/// adresi gösterir ve kopyalama sunar.
Future<void> gizlilikPolitikasiniAc(BuildContext context) async {
  var acildi = false;
  try {
    acildi = await launchUrl(Uri.parse(kGizlilikPolitikasiUrl), mode: LaunchMode.externalApplication);
  } catch (_) {
    acildi = false;
  }
  if (acildi || !context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: const Text('Tarayıcı açılamadı: maarifx.com/Gizlilik'),
      action: SnackBarAction(
        label: 'Kopyala',
        onPressed: () => Clipboard.setData(const ClipboardData(text: kGizlilikPolitikasiUrl)),
      ),
    ),
  );
}
