import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:exif/exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/chat_provider.dart';

class ChatInput extends StatefulWidget {
  final Function(File? image, String? text) onSend;
  final bool enabled;
  final File? externalImage;
  final VoidCallback? onExternalImageConsumed;

  const ChatInput({
    super.key,
    required this.onSend,
    this.enabled = true,
    this.externalImage,
    this.onExternalImageConsumed,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _textController = TextEditingController();
  final _imagePicker = ImagePicker();
  File? _selectedImage;

  bool get _canSend => widget.enabled && _selectedImage != null;

  @override
  void didUpdateWidget(covariant ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalImage != null &&
        widget.externalImage != oldWidget.externalImage) {
      _processAndSetImage(widget.externalImage!);
      widget.onExternalImageConsumed?.call();
    }
  }

  /// Sıkıştırma pipeline'ı.
  ///
  /// Orientation'ı `image_picker`'a veya `autoCorrectionAngle`'a bırakmıyoruz;
  /// ikisi de EXIF tag'ına körü körüne güvenir ve multi-cam Android
  /// telefonlarda (piksel zaten döndürülmüş + bayat tag) çift rotasyona /
  /// 90° kaymaya yol açar. Bunun yerine [_resolveRotation] EXIF tag'ı ile
  /// gerçek piksel oranını karşılaştırıp uygulanacak açıyı kendimiz
  /// hesaplar, FlutterImageCompress'e sabit `rotate` olarak veririz.
  Future<void> _processAndSetImage(File imageFile) async {
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final compressedPath = '${tempDir.path}/maarifx_$ts.jpg';

    final rotation = await _resolveRotation(imageFile);

    final result = await FlutterImageCompress.compressAndGetFile(
      imageFile.path,
      compressedPath,
      quality: 85,
      minWidth: 1920,
      minHeight: 1920,
      rotate: rotation,
      autoCorrectionAngle: false,
      keepExif: false,
    );

    if (mounted) {
      setState(() {
        _selectedImage = result != null ? File(result.path) : imageFile;
      });
    }
  }

  /// Uygulanması gereken saat yönü (CW) rotasyonunu döndürür.
  ///
  /// Mantık: EXIF "90° döndür" diyorsa bile, kayıtlı buffer ZATEN dikeyse
  /// (h > w) tag bayattır (multi-cam telefon pikseli donanımda döndürmüş ama
  /// tag'ı silmemiş) → döndürme. Buffer hâlâ yataysa (w > h) rotasyon
  /// gerçekten gereklidir → uygula. Bu en/boy oranı guard'ı, normal ve
  /// multi-cam telefonların ürettiği "aynı görünen ama farklı" dosyaları
  /// ayırt eden tek güvenilir sinyaldir.
  ///
  /// 180° ve flip'ler en/boy oranını değiştirmediği için ayırt edilemez;
  /// bilinen arıza modu multi-cam'in bayat 180 tag'ı yazıp fotoyu baş aşağı
  /// çevirmesiydi, o yüzden güvenli tarafta kalıp 0 döndürüyoruz.
  Future<int> _resolveRotation(File file) async {
    try {
      final bytes = await file.readAsBytes();

      // 1) EXIF orientation tag'ı (sadece okuma, döndürme yok).
      final exifData = await readExifFromBytes(bytes);
      final orientation = exifData['Image Orientation']?.printable ?? '';
      if (orientation.isEmpty) return 0;

      // 2) Gerçek (stored) buffer boyutu. ui.ImageDescriptor EXIF'i
      //    UYGULAMADAN ham piksel boyutunu verir — guard için tam da bu lazım.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final isLandscapeBuffer = descriptor.width > descriptor.height;
      descriptor.dispose();
      buffer.dispose();

      // CCW'yi önce kontrol et (string eşleşme çakışmasını önlemek için).
      if (orientation.contains('90 CCW')) {
        return isLandscapeBuffer ? 270 : 0;
      }
      if (orientation.contains('90 CW')) {
        return isLandscapeBuffer ? 90 : 0;
      }
      return 0;
    } catch (_) {
      // EXIF/decoder hatasında döndürme yapma (en kötü ihtimalle no-op).
      return 0;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: context.bgPrimary,
        border: Border(
          top: BorderSide(color: context.borderColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image Preview
          if (_selectedImage != null) _buildImagePreview(),

          // Input Row
          Container(
            decoration: BoxDecoration(
              color: context.bgSecondary,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: context.borderColor, width: 2),
            ),
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                // Upload Button
                _buildIconButton(
                  icon: Icons.add,
                  onPressed: _showImagePicker,
                  color: context.textSecondary,
                ),

                // Text Input
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Mesajınızı yazın...',
                      hintStyle: TextStyle(color: context.textMuted),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      filled: false,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: context.textPrimary,
                    ),
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),

                // Send Button
                _buildSendButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgTertiary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: Image.file(
              _selectedImage!,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => setState(() => _selectedImage = null),
            icon: const Icon(Icons.close),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: color,
      ),
    );
  }

  Widget _buildSendButton() {
    return IconButton(
      onPressed: _canSend ? _sendMessage : null,
      icon: const Icon(Icons.send),
      style: IconButton.styleFrom(
        backgroundColor: _canSend ? AppTheme.primary : context.bgTertiary,
        foregroundColor: _canSend ? Colors.white : context.textMuted,
      ),
    );
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Detay seviyesi secici
            _DetailLevelSelector(),
            const Divider(height: 1),

            // Soru uzerine cizme toggle
            _DrawOnImageToggle(),
            const Divider(height: 1),

            // Dusunme sureci (model reasoning) toggle
            _EnableThinkingToggle(),
            const Divider(height: 1),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, color: AppTheme.primary),
              ),
              title: const Text('Kamera'),
              subtitle: const Text('Fotoğraf çek'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library, color: AppTheme.primary),
              ),
              title: const Text('Galeri'),
              subtitle: const Text('Galeriden sec'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    // maxWidth/maxHeight/imageQuality VERMİYORUZ: bunlar image_picker'ın
    // dosyayı yeniden encode edip EXIF'i (telefona göre tutarsızca) işlemesine
    // yol açar ve guard'ımızın okuyacağı ham tag'ı bozar. Ham dosyayı alıp
    // orientation'ı _processAndSetImage içinde kendimiz normalize ediyoruz;
    // boyut küçültme zaten FlutterImageCompress'te (minWidth/minHeight 1920).
    final pickedFile = await _imagePicker.pickImage(source: source);

    if (pickedFile != null) {
      await _processAndSetImage(File(pickedFile.path));
    }
  }

  void _sendMessage() {
    if (!_canSend) return;

    widget.onSend(_selectedImage, _textController.text.trim());

    setState(() {
      _selectedImage = null;
      _textController.clear();
    });
  }
}

/// Soru uzerine cizme toggle
class _DrawOnImageToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final enabled = chatProvider.drawOnImage;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.draw_rounded, size: 18, color: context.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Soru Üzerine Çizme',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  enabled ? 'Görsel çözüm (çizimli)' : 'Düz metin yanıt',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => chatProvider.setDrawOnImage(!enabled),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: enabled ? AppTheme.primary : context.bgTertiary,
                border: Border.all(
                  color: enabled
                      ? AppTheme.primary
                      : context.borderColor,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment:
                    enabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled ? Colors.white : context.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dusunme sureci (model reasoning) toggle
class _EnableThinkingToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final enabled = chatProvider.enableThinking;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.psychology_rounded,
              size: 18, color: context.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Düşünme Süreci',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  enabled
                      ? 'Model adım adım düşünür (daha doğru)'
                      : 'Hızlı yanıt (düşünme atlanır)',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => chatProvider.setEnableThinking(!enabled),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: enabled ? AppTheme.primary : context.bgTertiary,
                border: Border.all(
                  color:
                      enabled ? AppTheme.primary : context.borderColor,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment:
                    enabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled ? Colors.white : context.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Detay seviyesi secici (1-5)
class _DetailLevelSelector extends StatelessWidget {
  static const _labels = ['Kısa', 'Özet', 'Standart', 'Detaylı', 'Tam'];

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final level = chatProvider.detailLevel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: context.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Detay Seviyesi',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                _labels[level - 1],
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(5, (i) {
              final lvl = i + 1;
              final selected = lvl == level;
              return Expanded(
                child: GestureDetector(
                  onTap: () => chatProvider.setDetailLevel(lvl),
                  child: Container(
                    margin: EdgeInsets.only(right: i < 4 ? 6 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.primary.withOpacity(0.2),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$lvl',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppTheme.primary,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
