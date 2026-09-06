import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/server_notice.dart';
import 'server_notice_dialog.dart' show runNoticeAction;
import 'ui_bits.dart';

/// Sunucu bildiriminin SOHBET İÇİ gövdesi.
///
/// Balon ve ikon yok: sol çizginin rengi türü söyler (uyarı sarı, hata ve
/// engel kırmızı, bilgi mavi). Başlık, metin ve butonlar sunucudan ne
/// geldiyse odur; içeriği YORUMLAMAZ.
class ServerNoticeBody extends StatelessWidget {
  final ServerNotice notice;
  const ServerNoticeBody({super.key, required this.notice});

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

  @override
  Widget build(BuildContext context) {
    final baslikVar = notice.title.trim().isNotEmpty;
    final eylemler =
        notice.actions.where((a) => a.kind != NoticeActionKind.dismiss).toList();

    return SolCizgiSatiri(
      renk: _renk(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (baslikVar)
            Text(
              notice.title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
              ),
            ),
          if (baslikVar && notice.message.isNotEmpty) const SizedBox(height: 4),
          if (notice.message.isNotEmpty)
            Text(
              notice.message,
              style: TextStyle(fontSize: 14, height: 1.5, color: context.textSecondary),
            ),
          if (eylemler.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 2,
              children: [
                for (final a in eylemler)
                  MetinEylem(
                    etiket: a.label,
                    ikon: Icons.chevron_right_rounded,
                    ikonSonda: true,
                    onTap: () => runNoticeAction(context, a),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
