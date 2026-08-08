import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/server_notice.dart';
import 'server_notice_dialog.dart' show runNoticeAction;

/// Sunucu bildiriminin SOHBET İÇİ gövdesi (AI balonunun içine girer).
///
/// Modal yerine buranın tercih edilmesinin sebebi: kullanıcı yazdığı mesajı ve
/// sohbet bağlamını kaybetmiyor, bildirim geçmişte kalıyor ve "AI cevap verdi"
/// akışı bozulmuyor — büyük AI ürünlerinin kota mesajlarıyla aynı davranış.
///
/// İçeriği YORUMLAMAZ: başlık/metin/butonlar sunucudan ne geldiyse odur.
class ServerNoticeBody extends StatelessWidget {
  final ServerNotice notice;
  const ServerNoticeBody({super.key, required this.notice});

  ({Color renk, IconData ikon}) get _gorunum {
    switch (notice.severity) {
      case NoticeSeverity.warning:
        return (renk: const Color(0xFFE0A02C), ikon: Icons.warning_amber_rounded);
      case NoticeSeverity.error:
        return (renk: AppTheme.danger, ikon: Icons.error_outline_rounded);
      case NoticeSeverity.blocked:
        return (renk: AppTheme.danger, ikon: Icons.lock_outline_rounded);
      case NoticeSeverity.info:
        return (renk: AppTheme.primary, ikon: Icons.info_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _gorunum;
    final baslikVar = notice.title.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(g.ikon, size: 18, color: g.renk),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (baslikVar)
                    Text(
                      notice.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  if (baslikVar && notice.message.isNotEmpty)
                    const SizedBox(height: 5),
                  if (notice.message.isNotEmpty)
                    Text(
                      notice.message,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: context.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),

        // Sunucunun verdiği butonlar. 'dismiss' sohbet içinde anlamsız
        // (kapatılacak bir şey yok) → yalnız url/route olanlar çizilir.
        if (notice.actions.any((a) => a.kind != NoticeActionKind.dismiss)) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in notice.actions)
                if (a.kind != NoticeActionKind.dismiss)
                  OutlinedButton(
                    onPressed: () => runNoticeAction(context, a),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: g.renk,
                      side: BorderSide(color: g.renk.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                    ),
                    child: Text(a.label, style: const TextStyle(fontSize: 13)),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}
