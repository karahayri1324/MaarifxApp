import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/chat_message.dart';
import '../../models/quiz_block.dart';

class UserMessageWidget extends StatelessWidget {
  final ChatMessage message;

  const UserMessageWidget({
    super.key,
    required this.message,
  });

  /// Görsel çizilemediğinde (bozuk base64 / indirilemeyen URL) yer tutucu.
  Widget _gorselHatasi(BuildContext context) {
    return Container(
      height: 80,
      alignment: Alignment.center,
      color: Colors.black.withOpacity(0.15),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 18, color: Colors.white70),
          SizedBox(width: 8),
          Text('Görsel yüklenemedi',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSending = message.status == MessageStatus.sending;
    // Çözülmüş baytlar mesajda önbellekli — bkz. ChatMessage.imageBytes.
    // Bozuk base64'te null döner; o durumda varsa imageUrl'e düşülür.
    final gorselBaytlari = message.imageBytes;

    // Quiz cevabı: ham ```maarifx-quiz-answer {JSON}``` yerine okunur kart.
    final quizAnswer = parseQuizAnswer(message.text);
    if (quizAnswer != null) {
      return _quizAnswerBubble(context, quizAnswer, isSending);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.84,
            ),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.userBubbleBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Image (base64 veya URL)
                if (gorselBaytlari != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.memory(
                          gorselBaytlari,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          // Yeniden çözüm sırasında eski kareyi TUT: yoksa
                          // fotoğraf her yeniden kurulumda bir kare boşalıp
                          // göz kırpıyor.
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => _gorselHatasi(context),
                        ),
                        // Yükleme sürerken hafif karartma + spinner
                        if (isSending) ...[
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.3),
                            ),
                          ),
                          const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (message.text.isNotEmpty) const SizedBox(height: 8),
                ] else if (message.imageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: Image.network(
                      message.imageUrl!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      // errorBuilder yoktu: geçmişteki görsel yüklenemeyince
                      // konsola exception düşüyor, kullanıcı boş kutu görüyordu.
                      errorBuilder: (_, __, ___) => _gorselHatasi(context),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          height: 80,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        );
                      },
                    ),
                  ),
                  if (message.text.isNotEmpty) const SizedBox(height: 8),
                ],

                // Text
                if (message.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: context.textPrimary,
                      ),
                    ),
                  ),

                // Sunucuya yükleme etiketi
                if (isSending) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Yükleniyor...',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: context.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Quiz cevabı balonu — fence yerine "Cevabın: …" kartı.
  Widget _quizAnswerBubble(
      BuildContext context, QuizAnswerPayload p, bool isSending) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: context.userBubbleBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.attempt != null && p.attempt! > 1
                      ? 'Cevabın · ${p.attempt}. deneme'
                      : 'Cevabın',
                  style: context.mono(fontSize: 11, color: context.textSecondary),
                ),
                const SizedBox(height: 5),
                Text(
                  p.pretty.isEmpty ? '—' : p.pretty,
                  style: TextStyle(
                      fontSize: 14.5, height: 1.45, color: context.textPrimary),
                ),
                if (isSending) ...[
                  const SizedBox(height: 5),
                  Text('Gönderiliyor...',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: context.textMuted)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
