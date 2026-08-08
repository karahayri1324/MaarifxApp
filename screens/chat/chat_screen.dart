import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../models/chat_message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/chat/user_message.dart';
import '../../widgets/chat/ai_message.dart';
import '../../widgets/input/chat_input.dart';
import '../../widgets/common/loading_overlay.dart';
import '../../widgets/drawer/nav_drawer.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import '../player/player_screen.dart';
import '../settings/privacy_policy_screen.dart';
import '../../widgets/common/server_notice_dialog.dart';

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

  // En yeni mesaj (reverse list'in anchor'ı, index 0) stream sırasında büyür.
  // Kullanıcı offset 0'da değilse (yukarı kaydırmışsa) bu büyüme, altındaki
  // içeriği pixel bazında kaydırıyor gibi görünüyordu ("scroll jump" bugu).
  // Bu key ile anchor item'ın boyunu her frame ölçüp farkı jumpTo ile telafi ediyoruz.
  final GlobalKey _latestItemKey = GlobalKey();
  double? _latestItemHeight;
  String? _latestItemId;

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

  // En yeni mesajın (index 0, reverse-list anchor) yüksekliği stream token'larıyla
  // sürekli değişir. Kullanıcı pixels==0'da (en altta) değilse bu boy değişimi
  // ScrollPosition.pixels'i etkilemeden altındaki görünümü kaydırır — kullanıcı
  // "sürekli zıplıyor" olarak algılar. Her frame sonrası boy farkını ölçüp
  // aynı miktarda jumpTo ile telafi ediyoruz, kullanıcının okuduğu konum sabit kalır.
  void _compensateScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final messages = context.read<ChatProvider>().messages;
    if (messages.isEmpty) return;
    final latestId = messages.last.id;
    final renderObject = _latestItemKey.currentContext?.findRenderObject();
    final newHeight =
        renderObject is RenderBox && renderObject.hasSize ? renderObject.size.height : null;

    if (_latestItemId != latestId) {
      // Yeni bir mesaj eklendi: farklı item'lar arası boy farkı anlamsız, sadece
      // yeni taban yüksekliği kaydedilir, bu frame'de telafi uygulanmaz.
      _latestItemId = latestId;
      _latestItemHeight = newHeight;
      return;
    }

    if (newHeight != null && _latestItemHeight != null) {
      final delta = newHeight - _latestItemHeight!;
      if (delta.abs() > 0.5 && _scrollController.position.pixels > 4) {
        _scrollController.jumpTo(_scrollController.position.pixels + delta);
      }
    }
    _latestItemHeight = newHeight;
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

  Future<void> _handleSend(File? image, String? text) async {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();

    // AI veri kullanim onayi kontrol et
    final consented = await _checkAiConsent();
    if (!consented) return;

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
    if (!chatProvider.serverReachable) {
      ServerErrorDialog.show(context);
      return;
    }

    // EFEKTİF mod: sohbet kilitliyse sohbetinki — oynatıcıya düşme kararı da
    // gerçekte gönderilen modla aynı olmalı (kilitli sohbette global toggle yanıltır).
    final isDirectChat = !chatProvider.effectiveDrawOnImage;

    final result = await chatProvider.sendMessage(
      imageFile: image,
      prompt: text,
      classLevel: authProvider.user?.classLevel,
    );
    _scrollToBottom(force: true);

    if (result == null || !mounted) return;

    // Direct chat modu: PlayerScreen'e gitme, chat'te kal
    if (isDirectChat) {
      return;
    }

    // Cizimli mod: canli player ekranina git
    final token = authProvider.token ?? '';
    String? imageUrl;
    if (result.imagePath != null) {
      imageUrl = chatProvider.vdsService.getImageUrl(result.imagePath!);
    }

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
    if (mounted) {
      await chatProvider.ensureRequestFinalized(result.requestId);
    }

    // Kullanici annotation gonderdi ise devam et
    if (annotationResult != null && mounted) {
      _handleAnnotationResult(annotationResult);
    }
  }

  /// ```maarifx-quiz``` kartından gelen cevap: normal bir metin turu olarak
  /// gönderilir (QUIZ_ANSWER.md — cevap tool değil, USER mesajıdır).
  /// Çizimsiz mod olduğu için PlayerScreen'e gidilmez, sohbette kalınır.
  Future<void> _handleQuizAnswer(String fence) async {
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
      return;
    }
    if (!chatProvider.serverReachable) {
      if (mounted) ServerErrorDialog.show(context);
      return;
    }

    await chatProvider.sendMessage(
      prompt: fence,
      classLevel: authProvider.user?.classLevel,
      forceDirectChat: true,   // çizim açık olsa bile oynatıcıya düşme, sohbette kal
    );
    _scrollToBottom(force: true);
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
      classLevel: authProvider.user?.classLevel,
      markedRegion: annotation.markedRegion,
      hintRef: annotation.hintRef,
      studentQuestion: studentQuestion,
    );
    _scrollToBottom(force: true);

    if (result != null && mounted) {
      final token = authProvider.token ?? '';
      String? imageUrl;
      if (result.imagePath != null) {
        imageUrl = chatProvider.vdsService.getImageUrl(result.imagePath!);
      }

      final nextAnnotation = await Navigator.of(context).push<AnnotationResult?>(
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

      if (mounted) {
        await chatProvider.ensureRequestFinalized(result.requestId);
      }

      if (nextAnnotation != null && mounted) {
        _handleAnnotationResult(nextAnnotation);
      }
    }
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
                  enabled: true,
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

  /// AppBar model rozetinden açılan model seçici (ChatInput sheet'i ile
  /// aynı ModelSelector'ı, dolayısıyla aynı provider state'ini kullanır)
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

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isGuest) {
    // select: yalnız model değişince rebuild (watch tüm token stream'inde AppBar'ı yeniden çizerdi)
    final isMax = context.select<ChatProvider, bool>((p) => p.model == '3.0-max');

    return AppBar(
      backgroundColor: context.bgPrimary,
      elevation: 0,
      leading: isGuest
          ? null // Guest modda menu butonu yok
          : IconButton(
              icon: Icon(Icons.menu, color: context.textPrimary),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
      automaticallyImplyLeading: false,
      title: GestureDetector(
        onTap: _showModelSheet,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: context.bgSecondary,
                boxShadow: AppTheme.shadowSm,
              ),
              padding: const EdgeInsets.all(5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.asset(
                  'assets/images/karahayri.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'MaariFx',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            // Model rozeti: standartta '3.0', MAX aktifken gradient 'MAX'
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: isMax
                    ? const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryDark],
                      )
                    : null,
                color: isMax ? null : AppTheme.primary.withOpacity(0.1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMax ? 'MAX' : '3.0',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: isMax ? Colors.white : AppTheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: isMax ? Colors.white : AppTheme.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: isGuest
          ? [
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text(
                  'Giriş Yap',
                  style: TextStyle(fontSize: 14),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
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
                  ),
                  child: const Text(
                    'Kayıt Ol',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ]
          : const [],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          color: context.borderColor,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildWelcomeMessage(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: context.bgPrimary,
                boxShadow: AppTheme.shadowMd,
              ),
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/images/karahayri.png'),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'MaariFx\'e Hoş Geldiniz',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Çözemediğin soruları çözmene yardımcı oluyorum.\n'
              'Soruyu yükleyerek cevabı öğrenmeye başlayabilirsin!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: context.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(ChatProvider chatProvider) {
    // Reverse ListView: en yeni mesaj viewport dibinde anchor'lanır.
    // Streaming sırasında bubble yukarı doğru büyür; kullanıcı en altta değilse
    // bu büyüme _compensateScroll ile telafi edilir (bkz. yukarısı).
    WidgetsBinding.instance.addPostFrameCallback((_) => _compensateScroll());
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: chatProvider.messages.length,
      itemBuilder: (context, index) {
        final message =
            chatProvider.messages[chatProvider.messages.length - 1 - index];

        final bubble = Padding(
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
                          if (result != null && mounted) {
                            final authProvider = context.read<AuthProvider>();
                            final token = authProvider.token ?? '';
                            String? imageUrl;
                            if (result.imagePath != null) {
                              imageUrl = chatProvider.vdsService.getImageUrl(result.imagePath!);
                            }
                            final annotationResult = await Navigator.of(context).push<AnnotationResult?>(
                              MaterialPageRoute(
                                builder: (_) => PlayerScreen(
                                  requestId: result.requestId,
                                  token: token,
                                  title: 'Çözüm',
                                  imageUrl: imageUrl,
                                  isLive: true,
                                ),
                              ),
                            );
                            if (mounted) {
                              await chatProvider.ensureRequestFinalized(result.requestId);
                            }
                            if (annotationResult != null && mounted) {
                              _handleAnnotationResult(annotationResult);
                            }
                          }
                        }
                      : null,
                  onReplay: (requestId) async {
                    final token = context.read<AuthProvider>().token ?? '';
                    final annotationResult = await Navigator.of(context).push<AnnotationResult?>(
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
        return index == 0 ? KeyedSubtree(key: _latestItemKey, child: bubble) : bubble;
      },
    );
  }
}
