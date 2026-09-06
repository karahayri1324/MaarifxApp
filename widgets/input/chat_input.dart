import 'dart:async';
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
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../common/class_level_sheet.dart';
import '../common/ui_bits.dart';
import '../../config/log.dart';

class ChatInput extends StatefulWidget {
  final Function(File? image, String? text) onSend;
  final bool enabled;
  final File? externalImage;
  final VoidCallback? onExternalImageConsumed;

  /// Sunucu bakımda (system_closed): alan kapalı, "Bakım bitince tekrar dene".
  final bool bakimda;

  const ChatInput({
    super.key,
    required this.onSend,
    this.enabled = true,
    this.bakimda = false,
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
  bool _drawOnImage = true; // build'de ChatProvider'dan senkronlanır (EFEKTİF mod)
  bool _inExistingConversation = false; // build'de senkronlanır

  // Çizim modu AÇIK → YENİ soruda görsel zorunlu; KAPALI → görsel veya metin yeterli.
  // Mevcut sohbette takip mesajı görselsiz de serbest (backend'in desteklediği
  // görselsiz takip turu; web de aynısını yapıyor). Mod kilidi eski bir çizimli
  // sohbeti açtığında kullanıcıyı düz metin yazamaz hale getirmesin.
  // Çizim açıkken görsel ZORUNLU DEĞİL: fotoğrafsız gönderim otomatik olarak
  // çizimsiz (metin) turuna düşer — provider'daki `gorselsizDusus`. Buton artık
  // yalnız "hiçbir içerik yok" durumunda kapalı.
  bool get _canSend {
    if (!widget.enabled || _isPreparingImage) return false;
    return _selectedImage != null || _textController.text.trim().isNotEmpty;
  }

  /// Çizim açık + görsel yok → istek ÇİZİMSİZ gidecek.
  ///
  /// Koşul, provider'daki `gorselsizDusus` ile BİREBİR aynı olmak zorunda
  /// (chat_provider.dart:555). Eskiden burada fazladan `!_inExistingConversation`
  /// vardı: mevcut çizimli sohbette fotoğrafsız yazılan takip de sessizce
  /// çizimsize düşüyordu ama kullanıcıya HİÇBİR ŞEY söylenmiyordu — "çizim
  /// bekliyordum, uygulama bozuldu" algısının kaynağı buydu.
  bool get _cizimsizeDusecek => _drawOnImage && _selectedImage == null;

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
  /// Sıkıştırılmış geçici JPEG'lerin ön eki. Temizlik bu ön eke bakar —
  /// başkasının dosyasına dokunmayalım.
  static const String _geciciOnEk = 'maarifx_';

  /// Bir GÜNDEN eski geçici JPEG'leri siler.
  ///
  /// Her fotoğraf seçimi cache dizinine bir dosya bırakıyordu ve hiçbiri
  /// silinmiyordu. Eşik bilerek geniş: seçili fotoğraf ve "Tekrar Dene"
  /// verisindeki `File` referansı hep taze olur, onlara dokunulmaz.
  static Future<void> _eskiGecicileriSil(Directory tempDir) async {
    try {
      final simdi = DateTime.now();
      await for (final e in tempDir.list(followLinks: false)) {
        if (e is! File) continue;
        final ad = e.uri.pathSegments.last;
        if (!ad.startsWith(_geciciOnEk) || !ad.endsWith('.jpg')) continue;
        try {
          final yas = simdi.difference(await e.lastModified());
          if (yas > const Duration(days: 1)) await e.delete();
        } catch (_) {
          // tek dosyanın silinememesi temizliği durdurmaz
        }
      }
    } catch (_) {
      // temizlik en iyi çaba — fotoğraf akışını asla bozmaz
    }
  }

  Future<void> _processAndSetImage(File imageFile) async {
    if (mounted) setState(() => _isPreparingImage = true);
    try {
      final tempDir = await getTemporaryDirectory();
      unawaited(_eskiGecicileriSil(tempDir));
      final ts = DateTime.now().millisecondsSinceEpoch;
      final compressedPath = '${tempDir.path}/$_geciciOnEk$ts.jpg';

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
      logD('[orient] $reason → rotate $rotation');
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
    // Gönderim kuralları drawOnImage'a bağlı — provider'ı izle, state'i taşı.
    // EFEKTİF mod: sohbet kilitliyse sohbetinki, değilse kullanıcı tercihi.
    final cp = context.watch<ChatProvider>();
    _drawOnImage = cp.effectiveDrawOnImage;
    // MOD KİLİDİ `_conversationMode`'da tutuluyor ve gönderimin EN BAŞINDA
    // iyimser olarak kuruluyor; `currentConversationId` ise ancak sunucu
    // cevabı dönünce atanıyor. İlk istek uçuşta olduğu sürece ikisi ayrışır ve
    // uyarı metni yanlış dalı gösterirdi — kilidin kendi getter'ını okuyoruz.
    _inExistingConversation = cp.isModeLocked;

    return Container(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 8,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
      ),
      color: context.bgSecondary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Görsel önizleme (hazırlanırken yer tutucu)
          if (_selectedImage != null || _isPreparingImage) _buildImagePreview(),

          // İki satır: üstte metin, altta araç satırı (artı · model · gönder)
          Container(
            decoration: BoxDecoration(
              color: widget.bakimda ? context.bgSecondary : context.bgPrimary,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: context.borderColor),
            ),
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _textController,
                  enabled: !widget.bakimda,
                  decoration: InputDecoration(
                    hintText: widget.bakimda
                        ? 'Bakım bitince tekrar dene'
                        : 'MaariFx\'e sor',
                    hintStyle: TextStyle(color: context.textMuted, fontSize: 14.5),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    filled: false,
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: context.textPrimary,
                  ),
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _sendMessage(),
                ),
                Row(
                  children: [
                    _buildIconButton(
                      icon: Icons.add,
                      onPressed: widget.bakimda ? null : _showImagePicker,
                      color: context.textSecondary,
                    ),
                    const Spacer(),
                    _ModelChip(onTap: _showModelSheet),
                    const SizedBox(width: 6),
                    _buildSendButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.bgPrimary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Fotoğrafı kaldır',
              style: IconButton.styleFrom(
                backgroundColor: context.bgTertiary,
                foregroundColor: context.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      style: IconButton.styleFrom(
        foregroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Gönder: 32 px kare, köşe 10; içerik varken mavi, yoksa sönük.
  Widget _buildSendButton() {
    final on = _canSend;
    return Semantics(
      button: true,
      label: 'Gönder',
      child: InkWell(
        key: const ValueKey('composer_gonder'),
        onTap: on ? () => _sendMessage() : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: on ? context.blue : context.borderColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 18,
            color: on ? context.onBlue : context.textMuted,
          ),
        ),
      ),
    );
  }

  /// Composer çipinden açılan model seçici — chat_screen'deki _showModelSheet
  /// kalıbıyla birebir aynı sheet (drag handle + ModelSelector).
  void _showModelSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => const SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTutamac(),
            ModelSelector(),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      // KAYDIRILABİLİR: sheet varsayılan olarak ekranın 9/16'sıyla sınırlıdır;
      // içerik (detay + 2 toggle + sınıf satırı + kamera/galeri) alçak ekranlarda
      // bu sınırı aşıp "Galeri" satırını kesiyordu (ölçüldü: 600 yükseklikte
      // 118 px taşma). Kaydırma taşmayı da, kesilmeyi de bitirir.
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetTutamac(),
            const SizedBox(height: 8),

            // Detay seviyesi secici
            _DetailLevelSelector(),
            const Divider(height: 1),

            // Soru uzerine cizme toggle
            _DrawOnImageToggle(),
            const Divider(height: 1),

            // Dusunme sureci (model reasoning) toggle
            _EnableThinkingToggle(),
            const Divider(height: 1),

            // MISAFIR sinif seviyesi: yanlis secimi duzeltebilsin (kayitlida bu
            // Ayarlar > Sinif Seviyesi'nde; misafirde menu/ayarlar ekrani yok).
            // Kayitli kullanicida bu blok HIC cizilmez (ayirici dahil).
            _MisafirSinifSatiri(
              onTap: () => _misafirSinifDegistir(sheetContext),
            ),

            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: context.textSecondary),
              title: const Text('Fotoğraf çek'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: context.textSecondary),
              title: const Text('Galeriden seç'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 16),
          ],
          ),
        ),
      ),
    );
  }

  /// Misafirin sınıf seviyesini değiştirmesi. Önce seçenek sheet'i kapatılır
  /// (üst üste iki modal açık kalmasın), sonra seviye sheet'i açılır.
  Future<void> _misafirSinifDegistir(BuildContext sheetContext) async {
    final auth = context.read<AuthProvider>();
    final mevcut = auth.user?.classLevel ?? auth.guestClassLevel;
    Navigator.pop(sheetContext);
    if (!mounted) return;
    final secim = await showSinifSeviyesiSheet(context, mevcut: mevcut);
    if (secim == null || secim == mevcut) return;
    await auth.setGuestClassLevel(secim);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sınıf seviyesi güncellendi: '
            '${kSinifSeviyeleri.firstWhere((s) => s.deger == secim).etiket}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
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

  Future<void> _sendMessage() async {
    if (!_canSend) return;

    // ÇİZİMLİ SOHBETTE ÇİZİMSİZ MESAJ SESSİZCE GİTMEZ. Çizim soru görselinin
    // ÜZERİNE yapılır; fotoğraf yoksa istek zorunlu olarak çizimsiz gider
    // (chat_provider.dart `gorselsizDusus`). Bu, kullanıcının çizim beklediği
    // anda düz metin almasına yol açıyordu. Eski SnackBar kaçırılabiliyordu ve
    // mevcut sohbette hiç gösterilmiyordu; yerine GÖRÜLMESİ ZORUNLU, gönderimi
    // durduran bir onay koydu.
    if (_cizimsizeDusecek) {
      final devam = await _cizimsizOnayi();
      if (!mounted || !devam) return;   // vazgeçildi → metin/fotoğraf korunur
      // Diyalog açıkken paylaşım (share intent) yoluyla fotoğraf gelmiş
      // olabilir: `didUpdateWidget` modal'ın altında çalışmaya devam ediyor.
      // O hâlde kullanıcının onayladığı şey ("metin olarak sor") artık geçerli
      // değil — istek çizimli gider ve sohbet çizime kilitlenirdi. Koşulu
      // yeniden doğrulayıp sessizce ters karar vermeyi engelliyoruz.
      if (!_cizimsizeDusecek) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fotoğraf eklendi — çizimli çözüm için tekrar gönder'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    }

    widget.onSend(_selectedImage, _textController.text.trim());

    setState(() {
      _selectedImage = null;
      _textController.clear();
    });
  }

  /// Çizim açıkken fotoğrafsız gönderim onayı.
  ///
  /// İki ayrı durum, iki ayrı sonuç — metin de ona göre:
  ///  • Sohbet HENÜZ başlamadıysa: bu mesaj sohbetin modunu KALICI olarak
  ///    çizimsize kilitler. Kilit sunucuda da tutulduğu için kullanıcı sonradan
  ///    fotoğraf eklese bile o sohbette bir daha çizimli çözüm ALAMAZ; tek çıkış
  ///    yeni sohbet. Bunu önceden söylemek zorundayız.
  ///  • Sohbet zaten çizimli kilitliyse: kilit değişmez, yalnız BU tur çizilmez.
  ///
  /// Dönen: true = kullanıcı bilerek metin olarak sormayı seçti.
  Future<bool> _cizimsizOnayi() async {
    final kilitli = _inExistingConversation;

    final sonuc = await showDialog<String>(
      context: context,
      // Boşluğa dokunarak kapatılamaz. Geri tuşu yine kapatabilir; o durumda
      // sonuç null döner ve gönderim İPTAL edilir — yani kaçırılan bir uyarı
      // asla sessiz bir gönderime dönüşmez.
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.photo_camera_outlined,
            size: 28, color: AppTheme.warning),
        title: Text(kilitli
            ? 'Bu mesaj çizilmeyecek'
            : 'Bu sohbet metin moduna kilitlenecek'),
        content: Text(
          kilitli
              ? 'Bu sohbet çizimli, ama gönderdiğin mesajda fotoğraf yok. '
                'Çizim soru görselinin üzerine yapıldığı için fotoğrafsız '
                'mesaj çizilmez; cevap sohbette düz metin olarak gelir ve '
                'çözüm oynatıcısı açılmaz.\n\n'
                'Çizimli çözüm istiyorsan sorunun fotoğrafını ekle.'
              : 'Fotoğraf eklemeden gönderirsen bu sohbet metin modunda '
                'başlar ve bir daha değiştirilemez — sonradan fotoğraf '
                'eklesen bile bu sohbette soru üzerine çizim yapılamaz.\n\n'
                'Çizimli çözüm için önce sorunun fotoğrafını ekle; düz sohbet '
                'istiyorsan metin olarak devam edebilirsin.',
        ),
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'iptal'),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'metin'),
            child: const Text('Metin olarak sor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'foto'),
            child: const Text('Fotoğraf ekle'),
          ),
        ],
      ),
    );

    if (!mounted) return false;
    if (sonuc == 'foto') {
      _showImagePicker();   // kullanıcı fotoğrafı seçip yeniden gönderir
      return false;
    }
    return sonuc == 'metin';
  }
}

/// Soru uzerine cizme toggle
class _DrawOnImageToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    // MOD KİLİDİ: sohbet başladıysa SOHBETİN modu gösterilir ve değiştirilemez.
    final locked = chatProvider.isModeLocked;
    final enabled = chatProvider.effectiveDrawOnImage;

    return Opacity(
      opacity: locked ? 0.5 : 1.0,
      child: Padding(
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
                    fontWeight: FontWeight.w500,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  locked
                      ? 'Sohbet ${enabled ? "çizimli" : "çizimsiz"} başladı — bu sohbette değiştirilemez'
                      : (enabled ? 'Görsel çözüm (çizimli)' : 'Düz metin yanıt'),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (locked) ...[
            Icon(Icons.lock_outline_rounded, size: 16, color: context.textMuted),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: locked ? null : () => chatProvider.setDrawOnImage(!enabled),
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
      ),
    );
  }
}

/// MİSAFİR sınıf seviyesi satırı (yalnız misafirde görünür; kayıtlı kullanıcıda
/// ayırıcısıyla birlikte HİÇ çizilmez — seviyesi hesabında ve Ayarlar'da).
class _MisafirSinifSatiri extends StatelessWidget {
  final VoidCallback onTap;

  const _MisafirSinifSatiri({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final misafir = auth.isGuest || !auth.isAuthenticated;
    if (!misafir) return const SizedBox.shrink();

    final deger = normalizeSinifSeviyesi(
        auth.user?.classLevel ?? auth.guestClassLevel);
    final etiket = deger == null
        ? 'Seç'
        : kSinifSeviyeleri.firstWhere((s) => s.deger == deger).etiket;

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.school_outlined,
                    size: 18, color: context.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sınıf Seviyesi',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        'Çözümler bu seviyeye göre anlatılır',
                        style: TextStyle(fontSize: 12, color: context.textMuted),
                      ),
                    ],
                  ),
                ),
                Text(
                  etiket,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.blue,
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: context.textMuted),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
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
                    fontWeight: FontWeight.w500,
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
              Text(
                'Detay seviyesi',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                _labels[level - 1],
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.bgPrimary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: List.generate(5, (i) {
                final lvl = i + 1;
                final selected = lvl == level;
                return Expanded(
                  child: InkWell(
                    onTap: () => chatProvider.setDetailLevel(lvl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected ? context.tint : null,
                        border: i == 0
                            ? null
                            : Border(left: BorderSide(color: context.borderColor)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$lvl',
                        style: context.mono(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                          color: selected ? context.textPrimary : context.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
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
/// 'MAX ⌄' (AppBar'daki MAX rozetiyle aynı gradient vurgu).
/// select: yalnız model değişince rebuild (watch her token'da yeniden çizerdi)
class _ModelChip extends StatelessWidget {
  final VoidCallback onTap;

  const _ModelChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final model = context.select<ChatProvider, String>((p) => p.model);
    final isMax = model == '3.0-max';
    final renk = isMax ? context.blue : context.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isMax ? 'MAX' : '3.0',
              style: context.mono(
                fontSize: 12,
                color: renk,
                fontWeight: isMax ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: renk),
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
    // Kilitli-çizimsiz sohbette MAX seçilebilir GÖRÜNMESİN → efektif mod
    final drawOn = chatProvider.effectiveDrawOnImage;
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
                model == '3.0-max' ? 'MAX' : '3.0',
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
                              color: context.tint,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'MAX',
                              style: context.mono(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: context.blue,
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
