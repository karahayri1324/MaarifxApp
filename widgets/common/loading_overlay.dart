import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'ui_bits.dart';

class LoadingOverlay extends StatefulWidget {
  final VoidCallback? onCancel;

  const LoadingOverlay({
    super.key,
    this.onCancel,
  });

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
          decoration: BoxDecoration(
            color: context.bgPrimary,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: Tween<double>(begin: 0.55, end: 1.0).animate(_controller),
                child: const MaarifxYazi(width: 120),
              ),
              const SizedBox(height: 18),
              Text(
                'Hazırlıyorum',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Birazdan hazır olur',
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
              if (widget.onCancel != null) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Vazgeç'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ServerErrorDialog extends StatelessWidget {
  const ServerErrorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sunucuya ulaşılamıyor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Olası sebepler:',
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
          const SizedBox(height: 6),
          _bulletPoint(context, 'İnternet bağlantın kesilmiş olabilir'),
          _bulletPoint(context, 'Sunucu bakım altında olabilir'),
          _bulletPoint(context, 'Ağ sorunu yaşanıyor olabilir'),
          const SizedBox(height: 10),
          Text(
            'Bağlantını kontrol edip tekrar dene.',
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
    );
  }

  static Widget _bulletPoint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: context.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ServerErrorDialog(),
    );
  }
}
