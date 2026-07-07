import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/chat_message.dart';

class UserMessageWidget extends StatelessWidget {
  final ChatMessage message;

  const UserMessageWidget({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isSending = message.status == MessageStatus.sending;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.userBubbleBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMd),
                topRight: Radius.circular(AppTheme.radiusMd),
                bottomLeft: Radius.circular(AppTheme.radiusMd),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Image (base64 veya URL)
                if (message.imageBase64 != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.memory(
                          base64Decode(message.imageBase64!),
                          fit: BoxFit.contain,
                          width: double.infinity,
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
                  Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: context.textPrimary,
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
}
