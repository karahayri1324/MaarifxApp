import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/server_notice.dart';

/// AÇIK UÇLU sunucu bildirimini basar.
///
/// Bu widget hiçbir SEBEBİ tanımaz — backend ne yolladıysa onu gösterir.
/// Yeni bir durum (okul banı, bakım, kampanya duyurusu…) eklemek için burada
/// kod değişmez; sunucudaki notices.json yeter.
Future<void> showServerNotice(BuildContext context, ServerNotice notice) {
  return showDialog<void>(
    context: context,
    barrierDismissible: notice.dismissible,
    builder: (_) => _ServerNoticeDialog(notice: notice),
  );
}

/// Bildirim butonunu çalıştırır. Şema BEYAZ LİSTE — sunucudan gelse bile
/// keyfi bir URI şeması açılmaz; route yalnız uygulama içi yol olabilir.
Future<void> runNoticeAction(BuildContext context, NoticeAction a) async {
  switch (a.kind) {
    case NoticeActionKind.url:
      final uri = Uri.tryParse(a.value);
      if (uri != null && const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      break;
    case NoticeActionKind.route:
      // Güvenlik ağı: sunucu tanımsız bir rota gönderirse (main.dart'ta kayıtlı
      // değil) pushNamed FIRLATIR. Açık uçlu sistemde sunucu her şeyi
      // gönderebildiği için try/catch şart — buton çalışmasa bile app çökmesin.
      if (a.value.startsWith('/') && context.mounted) {
        try {
          Navigator.of(context).pushNamed(a.value);
        } catch (_) {
          // Bilinmeyen rota — sessizce yok say (kapatmak yeterli).
        }
      }
      break;
    case NoticeActionKind.dismiss:
      break;
  }
}

class _ServerNoticeDialog extends StatelessWidget {
  final ServerNotice notice;
  const _ServerNoticeDialog({required this.notice});

  Color _renk(BuildContext context) {
    switch (notice.severity) {
      case NoticeSeverity.warning:
        return context.warn;
      case NoticeSeverity.error:
      case NoticeSeverity.blocked:
        return context.pen;
      case NoticeSeverity.info:
        return context.blue;
    }
  }

  Future<void> _calistir(BuildContext context, NoticeAction a) async {
    Navigator.of(context).pop();
    await runNoticeAction(context, a);
  }

  @override
  Widget build(BuildContext context) {
    final renk = _renk(context);
    // Sunucu buton vermediyse tek bir "Tamam". Engelleyici bildirimde bile bir
    // çıkış olmalı — kullanıcı ekranda kilitli kalmasın.
    final butonlar = notice.actions.isNotEmpty
        ? notice.actions
        : const [NoticeAction(label: 'Tamam', kind: NoticeActionKind.dismiss)];

    return PopScope(
      canPop: notice.dismissible,
      child: AlertDialog(
        title: Text(notice.title),
        content: notice.message.isEmpty
            ? null
            : SingleChildScrollView(
                child: Text(
                  notice.message,
                  style: TextStyle(fontSize: 14, height: 1.5, color: context.textSecondary),
                ),
              ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          for (var i = 0; i < butonlar.length; i++)
            if (i == 0)
              FilledButton(
                onPressed: () => _calistir(context, butonlar[i]),
                style: FilledButton.styleFrom(
                  backgroundColor: renk,
                  foregroundColor: Colors.white,
                ),
                child: Text(butonlar[i].label),
              )
            else
              TextButton(
                onPressed: () => _calistir(context, butonlar[i]),
                child: Text(butonlar[i].label,
                    style: TextStyle(color: context.textSecondary)),
              ),
        ],
      ),
    );
  }
}
