import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
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
  bool _isPreparingImage = false;
  bool _drawOnImage = true; // build'de ChatProvider'dan senkronlanır

  // Çizim modu AÇIK → görsel zorunlu; KAPALI → görsel veya metin yeterli.
  bool get _canSend {
    if (!widget.enabled || _isPreparingImage) return false;
    if (_drawOnImage) return _selectedImage != null;
    return _selectedImage != null || _textController.text.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalImage != null &&
        widget.externalImage != oldWidget.externalImage) {
      _processAndSetImage(widget.externalImage!);
      // didUpdateWidget build fazında çalışır; parent'ta hemen setState
      // çağırmak "setState() called during build" hatası üretir — ertele.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExternalImageConsumed?.call();
      });
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
    if (mounted) setState(() => _isPreparingImage = true);
    try {
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
    } finally {
      if (mounted) setState(() => _isPreparingImage = false);
    }
  }

  /// Uygulanması gereken saat yönü (CW) rotasyonunu (0 / 90 / 270) döndürür.
  ///
  /// Mantık: EXIF "90° döndür" diyorsa bile, kayıtlı buffer ZATEN dikeyse
  /// (h > w) tag bayattır (multi-cam telefon pikseli donanımda döndürmüş ama
  /// tag'ı silmemiş) → döndürme. Buffer hâlâ yataysa (w > h) rotasyon
  /// gerçekten gereklidir → uygula. Bu en/boy oranı guard'ı, normal ve
  /// multi-cam telefonların ürettiği "aynı görünen ama farklı" dosyaları
  /// ayırt eden tek güvenilir sinyaldir.
  ///
  /// EXIF orientation SAYISAL (1..8) okunur; paketin İngilizce "Rotated 90 CW"
  /// metnine bağlı kalmaz (string sadece yedek yol). Sadece 90'lık aile
  /// (5/6/7/8) en/boy guard'ına girer:
  ///   6,7 → 90° CW   |   5,8 → 270° CW (= 90° CCW)
  ///
  /// 180° ve saf ayna (EXIF 2/3/4) en/boy oranını DEĞİŞTİRMEZ, dolayısıyla
  /// "bayat mı geçerli mi" ayırt edilemez; bilinen arıza modu multi-cam'in
  /// bayat 180 tag'ı yazıp fotoyu baş aşağı çevirmesiydi, o yüzden güvenli
  /// tarafta kalıp 0 (no-op) dönüyoruz. (5/7'deki ayna bileşeni de
  /// FlutterImageCompress.rotate ile yapılamadığı için yok sayılır — çok nadir.)
  Future<int> _resolveRotation(File file) async {
    int rotation = 0;
    String reason = 'default';
    try {
      final bytes = await file.readAsBytes();

      // 1) EXIF orientation → sayısal değer (1..8). Yoksa 1 (normal).
      final exifData = await readExifFromBytes(bytes);
      final orientation = _exifOrientation(exifData);

      if (orientation < 5) {
        // 1 normal / 2 ayna / 3 180° / 4 dikey ayna → döndürme yok.
        reason = 'exif=$orientation (90-dışı, güvenli no-op)';
      } else {
        // 2) Ham (stored) buffer en/boy oranı — EXIF UYGULANMADAN.
        //    ui.ImageDescriptor her iki platformda da Skia ile çözer, yani
        //    iOS/Android'de tutarlı ham boyut verir. Kaynaklar try/finally
        //    ile her durumda serbest bırakılır.
        bool? isLandscape;
        ui.ImmutableBuffer? buffer;
        ui.ImageDescriptor? descriptor;
        try {
          buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          isLandscape = descriptor.width > descriptor.height;
        } catch (_) {
          isLandscape = null; // decode edilemedi (bozuk/desteklenmeyen)
        } finally {
          descriptor?.dispose();
          buffer?.dispose();
        }

        if (isLandscape == null) {
          reason = 'exif=$orientation, buffer decode edilemedi → no-op';
        } else if (!isLandscape) {
          // Buffer zaten dik → tag bayat (multi-cam) → döndürme.
          reason = 'exif=$orientation, buffer portrait → bayat tag, no-op';
        } else {
          // Yatay buffer + 90'lık tag → rotasyon gerçekten gerekli.
          rotation = (orientation == 6 || orientation == 7) ? 90 : 270;
          reason = 'exif=$orientation, buffer landscape';
        }
      }
    } catch (e) {
      // EXIF/IO hatasında döndürme yapma (en kötü ihtimalle no-op).
      rotation = 0;
      reason = 'hata: $e';
    }

    if (kDebugMode) {
      debugPrint('[orient] $reason → rotate $rotation');
    }
    return rotation;
  }

  /// EXIF orientation'ı SAYISAL (1..8) döndürür; tag yoksa 1 (normal).
  ///
  /// Birincil yol ham sayısal değerdir (`.values`) — exif paketinin
  /// İngilizce metin sözlüğüne bağlı değildir, sürüm/lokalizasyon değişse
  /// bile kırılmaz. Sayısal okuma başarısız olursa `.printable` metni çözülür
  /// (yedek). Değer 1..8 aralığında değilse 1 kabul edilir.
  int _exifOrientation(Map<String, IfdTag> exifData) {
    final tag = exifData['Image Orientation'];
    if (tag == null) return 1;

    // Birincil: ham sayısal değer.
    try {
      final raw = tag.values.toList();
      if (raw.isNotEmpty && raw.first is int) {
        final v = raw.first as int;
        if (v >= 1 && v <= 8) return v;
      }
    } catch (_) {
      // sayısal okuma başarısız → string yedeğe düş.
    }

    // Yedek: printable metni (exif paketinin sözlüğü).
    final p = tag.printable;
    if (p.contains('180')) return 3;
    if (p.contains('90 CCW')) return p.contains('Mirrored') ? 5 : 8;
    if (p.contains('90 CW')) return p.contains('Mirrored') ? 7 : 6;
    if (p.contains('Mirrored horizontal')) return 2;
    if (p.contains('Mirrored vertical')) return 4;
    return 1;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Gönderim kuralları drawOnImage'a bağlı — provider'ı izle, state'i taşı
    _drawOnImage = context.watch<ChatProvider>().drawOnImage;

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
          // Image Preview (hazırlanırken placeholder gösterilir)
          if (_selectedImage != null || _isPreparingImage) _buildImagePreview(),

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
                      hintText: _drawOnImage
                          ? 'Fotoğraf ekle, istersen not yaz...'
                          : 'Mesajını yaz...',
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

                // Model çipi ('3.0 ⌄' / '3.0 MAX ⌄') — gönder butonunun solunda
                _ModelChip(onTap: _showModelSheet),
                const SizedBox(width: 4),

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
          if (_isPreparingImage) ...[
            const _PreparingImagePlaceholder(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Görsel hazırlanıyor...',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.textSecondary,
                ),
              ),
            ),
          ] else ...[
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

  /// Composer çipinden açılan model seçici — chat_screen'deki _showModelSheet
  /// kalıbıyla birebir aynı sheet (drag handle + ModelSelector).
  void _showModelSheet() {
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
            const SizedBox(height: 8),
            const ModelSelector(),
            const SizedBox(height: 16),
          ],
        ),
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
    if (!_canSend) {
      // Buton zaten disabled; klavyeden Enter ile gelen denemeyi bilgilendir
      if (widget.enabled &&
          !_isPreparingImage &&
          _drawOnImage &&
          _selectedImage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Soru Üzerine Çizim açık — fotoğraf eklemek zorunlu'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

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

/// Görsel sıkıştırılırken önizleme alanında gösterilen pulse placeholder
class _PreparingImagePlaceholder extends StatefulWidget {
  const _PreparingImagePlaceholder();

  @override
  State<_PreparingImagePlaceholder> createState() =>
      _PreparingImagePlaceholderState();
}

class _PreparingImagePlaceholderState extends State<_PreparingImagePlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: const Icon(
          Icons.image_outlined,
          color: AppTheme.primary,
          size: 26,
        ),
      ),
    );
  }
}

/// Composer sağ-altındaki kompakt model çipi: '3.0 ⌄', MAX seçiliyken
/// '3.0 MAX ⌄' (AppBar'daki MAX rozetiyle aynı gradient vurgu).
/// select: yalnız model değişince rebuild (watch her token'da yeniden çizerdi)
class _ModelChip extends StatelessWidget {
  final VoidCallback onTap;

  const _ModelChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final model = context.select<ChatProvider, String>((p) => p.model);
    final isMax = model == '3.0-max';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: isMax
              ? const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isMax ? '3.0 MAX' : '3.0',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isMax ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: isMax ? 0.5 : 0,
                color: isMax ? Colors.white : context.textMuted,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: isMax ? Colors.white : context.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Model secici (3.0 / 3.0 MAX) — bottom sheet ve AppBar'dan ortak kullanılır
class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final model = chatProvider.model;
    final drawOn = chatProvider.drawOnImage;
    final isGuest = chatProvider.isGuestUser;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 18, color: context.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Model',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                model == '3.0-max' ? '3.0 MAX' : '3.0',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ModelOption(
            title: '3.0',
            subtitle: 'Standart — hızlı ve dengeli çözüm',
            selected: model == '3.0',
            enabled: true,
            onTap: () => chatProvider.setModel('3.0'),
          ),
          const SizedBox(height: 8),
          _ModelOption(
            title: '3.0',
            subtitle: isGuest
                ? 'Giriş yapınca kullanılabilir'
                : (drawOn
                    ? 'Derin çözümleme — daha yavaş, daha isabetli'
                    : 'Soru Üzerine Çizim açıkken kullanılabilir'),
            selected: model == '3.0-max',
            enabled: drawOn && !isGuest,
            isMax: true,
            onTap: () => chatProvider.setModel('3.0-max'),
          ),
        ],
      ),
    );
  }
}

class _ModelOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final bool isMax;
  final VoidCallback onTap;

  const _ModelOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    this.isMax = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primary : context.borderColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                        if (isMax) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.primary,
                                  AppTheme.primaryDark,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'MAX',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!enabled)
                Icon(Icons.lock_outline_rounded,
                    size: 16, color: context.textMuted)
              else if (selected)
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: AppTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
