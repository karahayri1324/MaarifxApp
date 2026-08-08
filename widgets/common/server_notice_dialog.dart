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
      if (a.value.startsWith('/') && context.mounted) {
        Navigator.of(context).pushNamed(a.value);
      }
      break;
    case NoticeActionKind.dismiss:
      break;
  }
}

class _ServerNoticeDialog extends StatelessWidget {
  final ServerNotice notice;
  const _ServerNoticeDialog({required this.notice});

  ({Color renk, IconData ikon}) get _gorunum {
    switch (notice.severity) {
      case NoticeSeverity.warning:
        return (renk: const Color(0xFFE0A02C), ikon: Icons.warning_amber_rounded);
      case NoticeSeverity.error:
        return (renk: const Color(0xFFD9534F), ikon: Icons.error_outline_rounded);
      case NoticeSeverity.blocked:
        return (renk: const Color(0xFFD9534F), ikon: Icons.lock_outline_rounded);
      case NoticeSeverity.info:
        return (renk: AppTheme.primary, ikon: Icons.info_outline_rounded);
    }
  }

  Future<void> _calistir(BuildContext context, NoticeAction a) async {
    Navigator.of(context).pop();
    await runNoticeAction(context, a);
  }

  @override
  Widget build(BuildContext context) {
    final g = _gorunum;
    // Sunucu buton vermediyse tek bir "Tamam". Engelleyici bildirimde bile bir
    // çıkış olmalı — kullanıcı ekranda kilitli kalmasın.
    final butonlar = notice.actions.isNotEmpty
        ? notice.actions
        : const [NoticeAction(label: 'Tamam', kind: NoticeActionKind.dismiss)];

    return PopScope(
      canPop: notice.dismissible,
      child: AlertDialog(
        backgroundColor: context.bgPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        title: Row(
          children: [
            Icon(g.ikon, color: g.renk, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                notice.title,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ),
          ],
        ),
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
                style: FilledButton.styleFrom(backgroundColor: g.renk),
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
