import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import 'hesap_silme_ekrani.dart';
import '../../widgets/common/class_level_sheet.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/user_model.dart';
import '../chat/chat_screen.dart';
import 'privacy_policy_screen.dart';
import '../../widgets/common/ui_bits.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _passwordExpanded = false;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _passwordLoading = false;
  String? _passwordMessage;
  bool _passwordSuccess = false;

  @override
  void initState() {
    super.initState();
    // Uzak ayarlar: samimiyet4 bayrağı + sunucudaki tanıtım metni.
    // Ekran bunları BEKLEMEDEN açılır; geldiklerinde kendini tazeler.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ChatProvider>().refreshRemoteSettings();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final current = _currentPasswordController.text.trim();
    final newPw = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (current.isEmpty || newPw.isEmpty || confirm.isEmpty) {
      setState(() {
        _passwordMessage = 'Tüm alanları doldurun';
        _passwordSuccess = false;
      });
      return;
    }
    if (newPw.length < 6) {
      setState(() {
        _passwordMessage = 'Yeni şifre en az 6 karakter olmalı';
        _passwordSuccess = false;
      });
      return;
    }
    if (newPw != confirm) {
      setState(() {
        _passwordMessage = 'Yeni şifreler eşleşmiyor';
        _passwordSuccess = false;
      });
      return;
    }

    setState(() {
      _passwordLoading = true;
      _passwordMessage = null;
    });

    final vdsService = context.read<ChatProvider>().vdsService;
    final result = await vdsService.changePassword(current, newPw);

    if (mounted) {
      setState(() {
        _passwordLoading = false;
        _passwordSuccess = result['success'] == true;
        _passwordMessage = result['message'] as String? ??
            (_passwordSuccess
                ? 'Şifre başarıyla değiştirildi'
                : 'Hata oluştu');
        if (_passwordSuccess) {
          _currentPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();
        }
      });
    }
  }

  Future<void> _updateClassLevel(String? classLevel) async {
    if (classLevel == null) return;
    final vdsService = context.read<ChatProvider>().vdsService;
    final authProvider = context.read<AuthProvider>();
    final success = await vdsService.updateProfile(classLevel: classLevel);
    if (!mounted) return;
    if (success && authProvider.user != null) {
      authProvider.updateUser(
        authProvider.user!.copyWith(classLevel: classLevel),
      );
    } else if (!success) {
      // Sessiz fail olmasın — kullanıcı seçiminin kaydedilmediğini bilsin
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sınıf güncellenemedi. Tekrar dene.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _submitBugReport() async {
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hata bildir'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Sorunu kısaca anlat…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );

    if (submitted == true && controller.text.trim().isNotEmpty && mounted) {
      final vdsService = context.read<ChatProvider>().vdsService;
      final success =
          await vdsService.submitBugReport(controller.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Hata raporu gönderildi. Teşekkürler!'
                : 'Gönderilemedi. Tekrar dene.'),
          ),
        );
      }
    }
    controller.dispose();
  }

  /// Hesap silme — TEK DOKUNUŞLA OLMAZ.
  ///
  /// Ayarlarda yanlışlıkla dokunulan bir satır hesabı kalıcı olarak
  /// siliyordu. Artık ayrı bir ekranda e-posta + şifre + onay cümlesi
  /// istenir; sunucu da (server.js delete-account) aynı ikisini doğrular,
  /// yani koruma yalnız arayüzde değil.
  Future<void> _handleDeleteAccount() async {
    final eposta = context.read<AuthProvider>().user?.email ?? '';
    final kimlik = await Navigator.of(context).push<({String eposta, String sifre})>(
      MaterialPageRoute(
        builder: (_) => HesapSilmeEkrani(hesapEpostasi: eposta),
        fullscreenDialog: true,
      ),
    );

    if (kimlik != null && mounted) {
      final vdsService = context.read<ChatProvider>().vdsService;
      final result = await vdsService.deleteAccount(
        email: kimlik.eposta,
        password: kimlik.sifre,
      );

      if (mounted) {
        if (result['success'] == true) {
          final authProvider = context.read<AuthProvider>();
          // Çıkış yoluyla aynı temizlik: silinen hesabın sohbeti, uçuştaki
          // istekleri ve eski jetonlu WebSocket'i bırakılır.
          context.read<ChatProvider>().signOutCleanup();
          await authProvider.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Hesabın silindi'),
              ),
            );
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ChatScreen()),
              (route) => false,
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] as String? ?? 'Hesap silinemedi'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çıkış yap'),
        content: const Text('Hesabından çıkmak istiyor musun?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkış yap'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final authProvider = context.read<AuthProvider>();
      // Sohbet durumu ÖNCE bırakılır: mesajlar, uçuştaki istekler ve eski
      // jetonlu WebSocket. Yoksa yeni ChatScreen açılana kadar önceki
      // kullanıcının sohbeti ekranda kalıyor ve soket eski jetonla bağlı
      // olmaya devam ediyordu.
      context.read<ChatProvider>().signOutCleanup();
      await authProvider.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ChatScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgSecondary,
      appBar: AppBar(
        title: const Text('Ayarlar'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Consumer2<AuthProvider, ChatProvider>(
        builder: (context, authProvider, chatProvider, _) {
          final user = authProvider.user;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              if (user != null) _profil(context, user),

              _grupBaslik(context, 'Hesap'),
              _grup(context, [
                if (user != null) ...[
                  _satir(
                    context,
                    baslik: 'Ad',
                    deger: (user.displayName ?? '').trim().isEmpty
                        ? 'Ekle'
                        : user.displayName!,
                    onTap: () => _editDisplayName(context),
                  ),
                  if (user.schoolName != null && user.schoolName!.isNotEmpty)
                    _satir(context, baslik: 'Kurum', deger: user.schoolName!),
                  _satir(
                    context,
                    baslik: 'Sınıf',
                    deger: _sinifEtiketi(user.classLevel),
                    onTap: () => _sinifSec(context, user),
                  ),
                ],
                _satir(
                  context,
                  baslik: 'Şifre',
                  deger: 'Değiştir',
                  trailing: AnimatedRotation(
                    turns: _passwordExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded,
                        size: 18, color: context.textMuted),
                  ),
                  onTap: () =>
                      setState(() => _passwordExpanded = !_passwordExpanded),
                ),
              ], ek: _passwordForm(context)),

              _grupBaslik(context, 'Görünüm'),
              _grup(context, [
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    return _satir(
                      context,
                      baslik: 'Karanlık mod',
                      trailing: Switch(
                        value: themeProvider.isDarkMode,
                        onChanged: (_) => themeProvider.toggleTheme(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onTap: () => themeProvider.toggleTheme(),
                    );
                  },
                ),
              ]),

              _grupBaslik(context, 'Öğretmen'),
              _grup(context, [
                _satir(
                  context,
                  baslik: 'Samimiyet',
                  deger: _samimiyetEtiketi(chatProvider.samimiyet),
                  onTap: () => _samimiyetSec(context, chatProvider),
                ),
                _satir(
                  context,
                  baslik: 'Kendini tanıt',
                  deger: chatProvider.studentIntro.isEmpty
                      ? 'Ekle'
                      : chatProvider.studentIntro,
                  onTap: () => _editIntro(context, chatProvider),
                ),
              ]),

              _grupBaslik(context, 'Diğer'),
              _grup(context, [
                _satir(context, baslik: 'Hata bildir', onTap: _submitBugReport),
                _satir(
                  context,
                  baslik: 'Gizlilik politikası',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                    );
                  },
                ),
              ]),

              _grupBaslik(context, 'Hesap işlemleri'),
              _grup(context, [
                _satir(context, baslik: 'Çıkış yap', onTap: _handleLogout, okGoster: false),
                _satir(
                  context,
                  baslik: 'Hesabı sil',
                  onTap: _handleDeleteAccount,
                  tehlike: true,
                  okGoster: false,
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // Parçalar: profil, grup, satır
  // ─────────────────────────────────────────────────────

  Widget _profil(BuildContext context, UserModel user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
      child: Row(
        children: [
          BasHarfDairesi(harfler: user.initials, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayNameOrEmail,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: TextStyle(fontSize: 12.5, color: context.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grupBaslik(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 6),
      child: Text(trBuyuk(text), style: context.eyebrow),
    );
  }

  /// Yüzey rengi, 1 px kenarlık, köşe 12; satırlar arasında ince çizgi.
  /// [ek] açılır/kapanır içerik (şifre formu): kendi çizgisini kendi çizer.
  Widget _grup(BuildContext context, List<Widget> satirlar, {Widget? ek}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.bgPrimary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < satirlar.length; i++) ...[
            if (i > 0) Container(height: 1, color: context.borderColor),
            satirlar[i],
          ],
          if (ek != null) ek,
        ],
      ),
    );
  }

  /// Satır: solda başlık, sağda değer ya da kontrol. İkon ve alt yazı yok.
  /// Ayar satırı — SİMETRİ KURALI:
  /// başlık solda, değer sağa yaslı, en sağda SABİT GENİŞLİKTE bir işaret yuvası.
  /// Yuva satırda ok/anahtar olmasa bile ayrılır; böylece bütün değerler
  /// (Ad, Sınıf, Şifre…) aynı dikey hatta biter. Eskiden ok yalnız tıklanabilir
  /// satırlarda çiziliyordu ve değerler satırdan satıra kayıyordu.
  Widget _satir(
    BuildContext context, {
    required String baslik,
    String? deger,
    Widget? trailing,
    VoidCallback? onTap,
    bool tehlike = false,
    bool okGoster = true,
  }) {
    const yuva = 22.0;   // ok/işaret yuvası — her satırda aynı
    final Widget sagUc = trailing ??
        SizedBox(
          width: yuva,
          child: (onTap != null && okGoster)
              ? Icon(Icons.chevron_right_rounded, size: 18, color: context.textMuted)
              : null,
        );
    final icerik = Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(
                baslik,
                style: TextStyle(
                  fontSize: 14.5,
                  color: tehlike ? context.pen : context.textPrimary,
                ),
              ),
            ),
            if (deger != null)
              Expanded(
                flex: 4,
                child: Text(
                  deger,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 13.5, color: context.textSecondary),
                ),
              ),
            const SizedBox(width: 8),
            sagUc,
          ],
        ),
      ),
    );
    if (onTap == null) return icerik;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: icerik),
    );
  }

  // ─────────────────────────────────────────────────────
  // Açılır listeler
  // ─────────────────────────────────────────────────────

  String _sinifEtiketi(String? deger) {
    final d = normalizeSinifSeviyesi(deger);
    if (d == null) return 'Seç';
    for (final s in kSinifSeviyeleri) {
      if (s.deger == d) return s.etiket;
    }
    return d;
  }

  Future<void> _sinifSec(BuildContext context, UserModel user) async {
    final secim = await showSinifSeviyesiSheet(
      context,
      mevcut: normalizeSinifSeviyesi(user.classLevel),
    );
    if (secim != null) await _updateClassLevel(secim);
  }

  static const List<String> _samimiyetAdlari = [
    'Resmî', 'Dengeli', 'Samimi', 'Çok samimi',
  ];

  String _samimiyetEtiketi(int seviye) =>
      _samimiyetAdlari[(seviye.clamp(1, 4)) - 1];

  Future<void> _samimiyetSec(BuildContext context, ChatProvider chatProvider) async {
    // "Çok samimi" UZAKTAN kapatılabilir (/api/app-config → samimiyet4Enabled);
    // kapalıysa listede HİÇ görünmez. Sunucu istek anında da reddeder.
    final adet = chatProvider.samimiyet4Enabled ? 4 : 3;
    final secili = chatProvider.samimiyet.clamp(1, adet);
    final secim = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.bgPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTutamac(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text('Samimiyet', style: ctx.eyebrow),
            ),
            for (var i = 1; i <= adet; i++)
              InkWell(
                onTap: () => Navigator.of(ctx).pop(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _samimiyetAdlari[i - 1],
                          style: TextStyle(fontSize: 15, color: ctx.textPrimary),
                        ),
                      ),
                      if (i == secili)
                        Icon(Icons.check_rounded, size: 19, color: ctx.blue),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (secim != null) await chatProvider.setSamimiyet(secim);
  }



  // ─────────────────────────────────────────────────────
  // Kullanıcı adı
  // ─────────────────────────────────────────────────────
  Future<void> _editDisplayName(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final controller = TextEditingController(text: auth.user?.displayName ?? '');
    final sonuc = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ad'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Adın',
            helperText: 'Öğretmenin sana bu adla hitap eder',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    // `context` bu metoda PARAMETRE olarak geliyor; State'in `mounted`'i onun
    // icin dogru koruma degil. BuildContext'in kendi canliligina bakiyoruz.
    if (sonuc == null || !context.mounted) return;

    final ad = sonuc.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (ad.length < 2 || ad.length > 40) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ad 2-40 karakter olmalı'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final basarili = await context.read<ChatProvider>().vdsService
        .updateProfile(displayName: ad);
    if (!context.mounted) return;
    if (basarili) {
      if (auth.user != null) auth.updateUser(auth.user!.copyWith(displayName: ad));
      // ChatProvider kendi kopyasını tutuyor (isteğe `studentName` olarak gider)
      // → onu da tazele, yoksa model eski adı kullanmaya devam eder.
      context.read<ChatProvider>().setDisplayName(ad);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adın güncellendi')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ad güncellenemedi. Tekrar dene.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _editIntro(BuildContext context, ChatProvider chatProvider) async {
    final controller = TextEditingController(text: chatProvider.studentIntro);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kendini tanıt'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 400,
          decoration: const InputDecoration(
            hintText:
                'Örn. 10. sınıfım, sayısal seviyem orta, görsel anlatımı severim…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (result != null) {
      await chatProvider.setStudentIntro(result);
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  // ─────────────────────────────────────────────────────
  // Şifre formu (satırın altında açılır)
  // ─────────────────────────────────────────────────────

  Widget _passwordForm(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: !_passwordExpanded
          ? const SizedBox.shrink()
          : Column(
              children: [
                Container(height: 1, color: context.borderColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    children: [
                      _pwField(_currentPasswordController, 'Mevcut şifre'),
                      const SizedBox(height: 8),
                      _pwField(_newPasswordController, 'Yeni şifre'),
                      const SizedBox(height: 8),
                      _pwField(_confirmPasswordController, 'Yeni şifre, tekrar'),
                      if (_passwordMessage != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _passwordMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: _passwordSuccess ? context.ok : context.pen,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _passwordLoading ? null : _changePassword,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                        ),
                        child: _passwordLoading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: context.onBlue),
                              )
                            : const Text('Şifreyi değiştir'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _pwField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: TextStyle(fontSize: 14, color: context.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
    );
  }
}
