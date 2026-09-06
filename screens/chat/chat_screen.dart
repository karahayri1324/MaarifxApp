import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../widgets/common/ui_bits.dart';
import '../../models/chat_message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/chat/user_message.dart';
import '../../widgets/chat/ai_message.dart';
import '../../widgets/chat/anchor_growth_sliver.dart';
import '../../widgets/input/chat_input.dart';
import '../../widgets/common/loading_overlay.dart';
import '../../widgets/drawer/nav_drawer.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import '../player/player_screen.dart';
import '../../services/vds_service.dart' show SendMessageResult;
import '../settings/privacy_policy_screen.dart';
import '../../widgets/common/server_notice_dialog.dart';
import '../../widgets/common/class_level_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _guestInitializing = false;
  bool _serverCheckInFlight = false;
  bool _noticeInFlight = false;   // bildirim diyaloğu aynı anda iki kez açılmasın
  StreamSubscription? _shareSubscription;
  File? _sharedImage;

  // Balon widget önbelleği — anahtar mesaj kimliği, değer (imza, widget).
  // Akışta sağlayıcı her token'da bildirim yayar ve Consumer yeniden kurulur;
  // imzası değişmeyen balon için AYNI Widget örneği döndürülünce
  // Element.updateChild alt ağacı hiç dolaşmaz. Bkz. ChatMessage.uiImzasi().
  final Map<String, ({String imza, Widget widget})> _balonOnbellek = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initShareIntent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAuth();
    });
  }

  void _initShareIntent() {
    // Uygulama acikken paylasilan gorseller
    _shareSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> files) {
      if (files.isNotEmpty) {
        setState(() {
          _sharedImage = File(files.first.path);
        });
        ReceiveSharingIntent.instance.reset();
      }
    });

    // Uygulama kapali iken paylasilan gorsel (cold start)
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> files) {
      if (files.isNotEmpty) {
        setState(() {
          _sharedImage = File(files.first.path);
        });
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  Future<void> _initAuth() async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();

    if (authProvider.isAuthenticated && !authProvider.isGuest) {
      // Normal kullanici: WS bagla
      final user = authProvider.user;
      final token = authProvider.token;
      if (user != null && token != null) {
        chatProvider.setAuth(user.uid, token, displayName: user.displayName);
      }
    } else if (!authProvider.isAuthenticated) {
      // Henuz giris yapilmamis: guest token al
      await _initGuestMode();
    } else if (authProvider.isGuest) {
      // Zaten guest modda: WS bagla
      final user = authProvider.user;
      final token = authProvider.token;
      if (user != null && token != null) {
        chatProvider.setAuth(user.uid, token,
            isGuest: true, deviceId: authProvider.deviceId, displayName: user.displayName);
      }
    }
  }

  Future<void> _initGuestMode() async {
    if (_guestInitializing) return;
    setState(() => _guestInitializing = true);

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();

    // Device ID al veya olustur
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('guest_device_id');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('guest_device_id', deviceId);
    }

    final success = await authProvider.continueAsGuest(deviceId);
    if (success && mounted) {
      final user = authProvider.user;
      final token = authProvider.token;
      if (user != null && token != null) {
        chatProvider.setAuth(user.uid, token,
            isGuest: true, deviceId: deviceId, displayName: user.displayName);
      }
    }

    if (mounted) {
      setState(() => _guestInitializing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final chatProvider = context.read<ChatProvider>();
      chatProvider.checkInternetConnection();
      chatProvider.reconnectIfNeeded();
    }
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  // Reverse ListView: viewport'un dibi offset 0.
  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// AI veri kullanim onay dialogu
  Future<bool> _checkAiConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('ai_consent_accepted') ?? false;
    if (accepted) return true;

    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Veri Kullanımı Hakkında'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MaariFx, yüklemiş olduğunuz soru görsellerini ve metinlerini yapay zeka işleme hizmetine gönderir.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'Bu veriler yalnızca sorunuzu çözmek için kullanılır ve üçüncü taraflarla paylaşılmaz.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                );
              },
              child: const Text(
                'Gizlilik Politikasını İncele',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Reddet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kabul Ediyorum'),
          ),
        ],
      ),
    );

    if (result == true) {
      await prefs.setBool('ai_consent_accepted', true);
      return true;
    }
    return false;
  }

  /// Misafir mi? (guest token'i henuz alinmamis kullanici da misafir sayilir)
  bool _misafirMi(AuthProvider auth) => auth.isGuest || !auth.isAuthenticated;

  /// İsteğe gidecek sınıf seviyesi.
  /// Kayıtlı: hesabın seviyesi. Misafir: kullanıcıya işlenmiş seviye, o daha
  /// yazılmadıysa (guest token yarışı) cihazdaki değer.
  String? _sinifSeviyesi(AuthProvider auth) {
    final hesap = auth.user?.classLevel;
    if (hesap != null) return hesap;
    return _misafirMi(auth) ? auth.guestClassLevel : null;
  }

  /// MİSAFİR SINIF SEVİYESİ — ilk istekte bir kez sorulur, cihaza yazılır.
  /// Kullanıcı kararı 2026-08-17: misafirin ilk isteğinde veri-kullanım ONAY
  /// diyaloğu YERİNE bu sorulur (onay metni sheet'in içinde bilgi notu olarak
  /// durur, ayrıca onaylatılmaz). Sonraki isteklerde hiç görünmez.
  /// false → istek gönderilmez.
  Future<bool> _misafirSinifiHazir(AuthProvider authProvider) async {
    if (_sinifSeviyesi(authProvider) != null) return true;
    if (!mounted) return false;

    final secim = await showSinifSeviyesiSheet(context);
    if (secim == null) {
      // Vazgeçildi: composer içeriği chat_input'ta zaten temizlendiği için
      // sessiz kalma "gönderdim ama hiçbir şey olmadı" gibi görünür.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sınıf seviyesi seçilmedi — soru gönderilmedi'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
    await authProvider.setGuestClassLevel(secim);
    return true;
  }

  Future<void> _handleSend(File? image, String? text) async {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();

    if (_misafirMi(authProvider)) {
      // Misafir: onay yok, sınıf seviyesi (bir kez) — bkz. _misafirSinifiHazir
      if (!await _misafirSinifiHazir(authProvider)) return;
    } else {
      // Kayıtlı kullanıcı: mevcut AI veri kullanım onayı korunur
      final consented = await _checkAiConsent();
      if (!consented) return;
    }

    // Check internet first
    final hasNet = await chatProvider.checkInternetConnection();
    if (!hasNet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.'),
                ),
              ],
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Tekrar Dene',
              textColor: Colors.white,
              onPressed: () => chatProvider.checkInternetConnection(),
            ),
          ),
        );
      }
      return;
    }

    // Check server
    if (!mounted) return;   // yukaridaki await'lerden sonra ekran kapanmis olabilir
    if (!chatProvider.serverReachable) {
      ServerErrorDialog.show(context);
      return;
    }

    final result = await chatProvider.sendMessage(
      imageFile: image,
      prompt: text,
      classLevel: _sinifSeviyesi(authProvider),
    );
    _scrollToBottom(force: true);

    if (result == null || !mounted) return;

    await _openPlayerForResult(result);
  }

  /// Çizimli bir istek sonrası oynatıcıyı (canvas.html) açar, dönüşte isteği
  /// finalize eder ve takip turunu bağlar.
  ///
  /// CANLI oynatıcıya YALNIZ buradan geçilir — gönderim yollarının tek giriş
  /// noktası (ilk mesaj, takip turu, "Tekrar Dene"). Daha önce bu blok üç yerde
  /// kopyalanmıştı ve `drawOnImageUsed` koruması retry yolunda unutulduğu için
  /// çizimsize düşen (fotoğrafsız) mesajda da canvas açılıyordu. Yeni bir
  /// gönderim yolu eklenirken kontrol burada, tek yerde durur.
  ///
  /// (Ayrı yol: `onReplay` — tamamlanmış bir çözümün TEKRARI. O `isLive:false`
  /// ile doğrudan push ediyor ve zaten `hasSessionData` ile kapılı, yani
  /// çizimsiz mesajda buton hiç görünmüyor.)
  Future<void> _openPlayerForResult(SendMessageResult result) async {
    // İstek gerçekten çizimli gitmediyse oynatıcı AÇILMAZ; cevap sohbette metin
    // olarak akar. Karar toggle'a değil, GÖNDERİLEN moda bakar: çizim açıkken
    // fotoğrafsız gönderilen mesaj provider'da çizimsize düşürülüyor.
    if (!result.drawOnImageUsed || !mounted) return;

    final chatProvider = context.read<ChatProvider>();
    final token = context.read<AuthProvider>().token ?? '';
    final imageUrl = result.imagePath != null
        ? chatProvider.vdsService.getImageUrl(result.imagePath!)
        : null;

    final annotationResult = await Navigator.of(context).push<AnnotationResult?>(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          requestId: result.requestId,
          token: token,
          isLive: true,
          imageUrl: imageUrl,
          title: 'Çözüm',
        ),
      ),
    );

    // Player'dan donunce mesajin tamamlandigini garantile
    if (!mounted) return;
    await chatProvider.ensureRequestFinalized(result.requestId);

    // Kullanici annotation gonderdi ise takip turuna gec
    if (annotationResult != null && mounted) {
      await _handleAnnotationResult(annotationResult);
    }
  }

  /// ```maarifx-quiz``` kartından gelen cevap: normal bir metin turu olarak
  /// gönderilir (QUIZ_ANSWER.md — cevap tool değil, USER mesajıdır).
  /// Çizimsiz mod olduğu için PlayerScreen'e gidilmez, sohbette kalınır.
  /// Dönen: cevap gerçekten gönderildi mi? Kart yalnız `true` ile kilitlenir —
  /// gönderilemeyen bir cevap öğrenciyi kilitli kartla baş başa bırakmasın.
  Future<bool> _handleQuizAnswer(String fence) async {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();

    if (!await chatProvider.checkInternetConnection()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('İnternet bağlantısı yok. Cevabın gönderilemedi.'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return false;
    }
    if (!mounted) return false;
    if (!chatProvider.serverReachable) {
      ServerErrorDialog.show(context);
      return false;
    }

    final result = await chatProvider.sendMessage(
      prompt: fence,
      classLevel: _sinifSeviyesi(authProvider),
      forceDirectChat: true,   // çizim açık olsa bile oynatıcıya düşme, sohbette kal
    );
    _scrollToBottom(force: true);
    return result != null;
  }

  Future<void> _handleAnnotationResult(AnnotationResult annotation) async {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();

    // Takip turu türüne göre prompt + alanlar:
    // - Hint yanıtı: prompt = yanıt (boşsa "Cevap vermek istemiyorum"), hintRef ile.
    // - İşaretli bölge: prompt = not (boşsa varsayılan), markedRegion ile (görsel GÖNDERİLMEZ — §12).
    // - Legacy ekran-görüntüsü: imageFile + text.
    String? followupPrompt;     // → text → <soru>
    String? studentQuestion;    // → <ogrenci_sorusu> (işaretli bölge takip notu)
    if (annotation.hintRef != null) {
      // Hint yanıtı: prompt = yanıt; processor hintRef+prompt'tan ogrenci_yanitlari kurar.
      followupPrompt = annotation.text.isNotEmpty ? annotation.text : 'Cevap vermek istemiyorum';
    } else if (annotation.markedRegion != null) {
      // İşaretli bölge: not → <ogrenci_sorusu> (web ile simetri). <soru> orijinal soru olarak history'de kalır.
      studentQuestion = annotation.text.isNotEmpty ? annotation.text : 'İşaretlediğim yeri açıklar mısın?';
    } else {
      // Legacy ekran-görüntüsü takip: prompt olarak.
      followupPrompt = annotation.text.isNotEmpty ? annotation.text : 'Bu kısmı anlayamadım, açıklar mısın?';
    }
    final result = await chatProvider.sendMessage(
      imageFile: annotation.imageFile,
      prompt: followupPrompt,
      classLevel: _sinifSeviyesi(authProvider),
      markedRegion: annotation.markedRegion,
      hintRef: annotation.hintRef,
      studentQuestion: studentQuestion,
    );
    _scrollToBottom(force: true);

    // Takip turu da yalnız gerçekten çizimli gittiyse oynatıcıya döner
    // (aynı tek kaynak: gönderilen mod).
    if (result == null || !mounted) return;

    await _openPlayerForResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isGuest = authProvider.isGuest || !authProvider.isAuthenticated;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.bgSecondary,
      appBar: _buildAppBar(context, isGuest),
      drawer: isGuest ? null : const NavDrawer(),
      // Çekmece hissiyatı: varsayılan kenar şeridi ~20 px ve sürükleme parmak
      // KALKINCA başlıyordu; açmak için ekranın en kenarını bulmak gerekiyordu.
      // Şerit genişletildi ve sürükleme parmak DEĞİNCE başlıyor → anında takip.
      drawerEdgeDragWidth: 72,
      drawerDragStartBehavior: DragStartBehavior.down,
      drawerScrimColor: Colors.black.withOpacity(0.32),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          // Show server error dialog if needed
          // In-flight guard: her rebuild yeni bir kontrol yığmasın
          // SUNUCU BİLDİRİMİ — MODAL YOLU. Bildirimler VARSAYILAN olarak sohbete
          // balon düşer (bkz. ServerNoticeBody); buraya yalnız sunucu açıkça
          // display:"dialog" dediğinde bir şey gelir. Ekran içeriği YORUMLAMAZ.
          if (chatProvider.pendingNotice != null && !_noticeInFlight) {
            _noticeInFlight = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              final n = chatProvider.consumeNotice();
              if (n != null && mounted) await showServerNotice(context, n);
              _noticeInFlight = false;
            });
          }

          if (!chatProvider.serverReachable &&
              !chatProvider.isProcessing &&
              !_serverCheckInFlight) {
            _serverCheckInFlight = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await chatProvider.checkServerConnection();
              _serverCheckInFlight = false;
            });
          }

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: Column(
              children: [
                // No Internet Banner
                if (!chatProvider.hasInternet)
                  _buildStatusBanner(
                    icon: Icons.wifi_off_rounded,
                    text: 'İnternet bağlantısı yok',
                    color: AppTheme.danger,
                    actionText: 'Tekrar Dene',
                    onAction: () => chatProvider.checkInternetConnection(),
                  ),

                // Connection Status Banner (WebSocket reconnecting)
                if (chatProvider.hasInternet && !chatProvider.isConnected && !isGuest)
                  _buildStatusBanner(
                    icon: null,
                    text: 'Bağlantı kuruluyor...',
                    color: AppTheme.warning,
                    showSpinner: true,
                  ),

                // Chat Messages
                Expanded(
                  child: chatProvider.messages.isEmpty
                      ? _buildWelcomeMessage(context)
                      : _buildMessageList(chatProvider),
                ),

                // Input
                ChatInput(
                  enabled: !chatProvider.sistemKapali,
                  bakimda: chatProvider.sistemKapali,
                  onSend: _handleSend,
                  externalImage: _sharedImage,
                  onExternalImageConsumed: () {
                    setState(() => _sharedImage = null);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBanner({
    IconData? icon,
    required String text,
    required Color color,
    bool showSpinner = false,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border(
          bottom: BorderSide(color: color.withOpacity(0.3)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showSpinner)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else if (icon != null)
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          if (actionText != null && onAction != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  actionText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isGuest) {
    return AppBar(
      backgroundColor: context.bgSecondary,
      elevation: 0,
      toolbarHeight: 64,
      titleSpacing: 4,
      leading: isGuest
          ? null // Misafirde menü yok
          : IconButton(
              icon: Icon(Icons.menu_rounded, size: 26, color: context.textPrimary),
              iconSize: 26,
              splashRadius: 24,
              tooltip: 'Sohbetler',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
      automaticallyImplyLeading: false,
      // Kutulu logo ve model rozeti yerine yazı-logo. Model composer'dan seçilir.
      title: const MaarifxYazi(height: 27),
      actions: isGuest
          ? [
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text('Giriş yap'),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontFamily: AppTheme.fontSans, fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                  child: const Text('Kayıt ol'),
                ),
              ),
            ]
          : const [],
    );
  }

  /// Boş ekran: yalnız selamlama. Logo, karşılama metni ve öneri çipi yok.
  Widget _buildWelcomeMessage(BuildContext context) {
    final ad = context.select<AuthProvider, String?>((a) {
      final u = a.user;
      if (u == null || a.isGuest) return null;
      final n = (u.displayName ?? '').trim();
      return n.isEmpty ? null : n.split(RegExp(r'\s+')).first;
    });
    final saat = DateTime.now().hour;
    final selam = saat < 5
        ? 'İyi geceler'
        : saat < 11
            ? 'Günaydın'
            : saat < 17
                ? 'İyi günler'
                : saat < 22
                    ? 'İyi akşamlar'
                    : 'İyi geceler';
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ad == null ? '$selam.' : '$selam, $ad.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Hangi soruya bakalım?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: context.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Ters (reverse) sohbet listesi.
  ///
  /// İki sliver: DİPTE en yeni mesaj ("çapa") kendi sliver'ında, üstünde geri
  /// kalan mesajlar tembel bir SliverList'te.
  ///
  /// Çapanın AYRI sliver olması ŞART. Akış sırasında çapanın boyu her token'da
  /// büyür ve üstündeki tüm içeriği kaydırır; bu kayma [AnchorGrowthSliver]
  /// içinde LAYOUT ANINDA telafi ediliyor. Eskiden telafi post-frame
  /// `jumpTo` ile yapılıyordu: bir kare geç kaldığı ve aktif sürüklemeyi iptal
  /// ettiği için yukarı kaydırırken pırpır ediyordu (ayrıntı:
  /// widgets/chat/anchor_growth_sliver.dart).
  Widget _buildMessageList(ChatProvider chatProvider) {
    final messages = chatProvider.messages;
    final anchor = messages.last;
    _onbellekBudama(messages);

    // Yeni mesaj eklenince ters listede TÜM indisler kayar; anahtar + bu geri
    // çağrı olmasaydı görünürdeki her öğe başka bir mesajla yeniden kurulurdu.
    final Map<String, int> idIndis = {
      for (var i = 0; i < messages.length; i++) messages[i].id: i
    };

    return CustomScrollView(
      controller: _scrollController,
      reverse: true,
      slivers: [
        // Dipteki boşluk: eski ListView padding'i (all 16) + balonun kendi alt
        // boşluğu (16) ile aynı görünüm korunur.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: AnchorGrowthSliver(
            anchorId: anchor.id,
            child: _balon(chatProvider, anchor),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _balon(
                  chatProvider, messages[messages.length - 2 - index]),
              childCount: messages.length - 1,
              findChildIndexCallback: (Key key) {
                if (key is! ValueKey<String>) return null;
                final i = idIndis[key.value];
                if (i == null || i >= messages.length - 1) return null;
                return messages.length - 2 - i;
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Listede olmayan mesajların önbellek kayıtlarını atar.
  void _onbellekBudama(List<ChatMessage> messages) {
    if (_balonOnbellek.length <= messages.length) return;
    final ids = {for (final m in messages) m.id};
    _balonOnbellek.removeWhere((id, _) => !ids.contains(id));
  }

  /// Balon widget'ı — mesajın görünen hâli değişmediyse AYNI ÖRNEĞİ döndürür.
  ///
  /// Akışta sağlayıcı her token'da bildirim yayar ve bu Consumer yeniden
  /// kurulur. Aynı Widget örneği döndüğünde `Element.updateChild` alt ağacı hiç
  /// dolaşmaz; yani ekrandaki ESKİ çözümlerin markdown+LaTeX gövdeleri saniyede
  /// onlarca kez baştan kurulmaz. Kaydırma sırasında kare düşmesinin (ve
  /// dolayısıyla takılmanın) ana kaynağı buydu.
  Widget _balon(ChatProvider chatProvider, ChatMessage message) {
    final imza =
        '${message.uiImzasi()}|${chatProvider.canRetry(message.id) ? 1 : 0}';
    final onceki = _balonOnbellek[message.id];
    if (onceki != null && onceki.imza == imza) return onceki.widget;

    final widget = _balonKur(chatProvider, message);
    _balonOnbellek[message.id] = (imza: imza, widget: widget);
    return widget;
  }

  Widget _balonKur(ChatProvider chatProvider, ChatMessage message) {
    return Padding(
      key: ValueKey<String>(message.id),
      padding: const EdgeInsets.only(bottom: 16),
      child: message.type == MessageType.user
          ? UserMessageWidget(message: message)
          : AIMessageWidget(
              message: message,
              onQuizAnswer: _handleQuizAnswer,
              onStepChange: (step) {
                chatProvider.navigateToStep(message.id, step);
              },
              onRetry: chatProvider.canRetry(message.id)
                  ? () async {
                      final result = await chatProvider.retryMessage(message.id);
                      _scrollToBottom(force: true);
                      // Tekrar denenen istek de çizimsize düşmüş olabilir
                      // (fotoğrafsız metin / quiz cevabı) — oynatıcı kararı
                      // _openPlayerForResult içindeki tek koruma verir.
                      if (result != null && mounted) {
                        await _openPlayerForResult(result);
                      }
                    }
                  : null,
              onReplay: (requestId) async {
                final token = context.read<AuthProvider>().token ?? '';
                final annotationResult =
                    await Navigator.of(context).push<AnnotationResult?>(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      requestId: requestId,
                      token: token,
                      title: 'Çözüm Tekrarı',
                    ),
                  ),
                );
                if (annotationResult != null && mounted) {
                  _handleAnnotationResult(annotationResult);
                }
              },
            ),
    );
  }
}
