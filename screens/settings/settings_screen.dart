import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/user_model.dart';
import '../chat/chat_screen.dart';
import 'privacy_policy_screen.dart';

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
          content: Text('Sınıf seviyesi güncellenemedi. Lütfen tekrar deneyin.'),
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
        title: const Text('Hata Bildir'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Karşılaştığınız sorunu açıklayınız...',
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
                : 'Gönderme başarısız oldu. Lütfen tekrar deneyin.'),
          ),
        );
      }
    }
    controller.dispose();
  }

  Future<void> _handleDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabı Sil'),
        content: const Text(
          'Hesabınız ve tüm verileriniz kalıcı olarak silinecektir. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Hesabı Sil'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final vdsService = context.read<ChatProvider>().vdsService;
      final result = await vdsService.deleteAccount();

      if (mounted) {
        if (result['success'] == true) {
          final authProvider = context.read<AuthProvider>();
          await authProvider.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Hesabınız başarıyla silindi'),
                backgroundColor: AppTheme.success,
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
        title: const Text('Çıkış Yap'),
        content:
            const Text('Hesabınızdan çıkmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final authProvider = context.read<AuthProvider>();
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
        backgroundColor: context.bgPrimary,
        surfaceTintColor: Colors.transparent,
        title: const Text('Ayarlar'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.borderColor, height: 0.5),
        ),
      ),
      body: Consumer2<AuthProvider, ChatProvider>(
        builder: (context, authProvider, chatProvider, _) {
          final user = authProvider.user;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 20),

              // ── Profile ──
              if (user != null) _buildProfileTile(context, user),

              const SizedBox(height: 28),

              // ── Hesap ──
              _sectionLabel(context, 'Hesap'),
              _cardGroup(context, [
                if (user != null) ...[
                  // Kullanıcı adı — öğretmenin hitap ettiği ad
                  _tileTap(
                    context,
                    icon: Icons.badge_outlined,
                    title: 'Kullanıcı Adı',
                    subtitle: (user.displayName ?? '').trim().isEmpty
                        ? 'Öğretmenin sana nasıl hitap etsin?'
                        : user.displayName!,
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: context.textMuted, size: 22),
                    onTap: () => _editDisplayName(context),
                  ),
                  _divider(context),
                  if (user.schoolName != null && user.schoolName!.isNotEmpty) ...[
                    _tile(
                      context,
                      icon: Icons.school_outlined,
                      title: 'Kurum',
                      subtitle: 'Kayıtlı olduğunuz kurum',
                      value: user.schoolName!,
                    ),
                    _divider(context),
                  ],
                  _tile(
                    context,
                    icon: Icons.auto_stories_outlined,
                    title: 'Sınıf',
                    subtitle: 'Çözümler sınıf seviyenize göre uyarlanır',
                    child: _classDropdown(context, user),
                  ),
                  _divider(context),
                ],
                _tileTap(
                  context,
                  icon: Icons.lock_outline_rounded,
                  title: 'Şifre Değiştir',
                  subtitle: 'Hesap güvenliğiniz için şifrenizi güncelleyin',
                  trailing: AnimatedRotation(
                    turns: _passwordExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded,
                        color: context.textMuted, size: 22),
                  ),
                  onTap: () =>
                      setState(() => _passwordExpanded = !_passwordExpanded),
                ),
                _passwordForm(context),
              ]),

              const SizedBox(height: 28),

              // ── Görünüm ──
              _sectionLabel(context, 'Görünüm'),
              _cardGroup(context, [
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    return _tileTap(
                      context,
                      icon: themeProvider.isDarkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      title: 'Karanlık Mod',
                      subtitle: 'Göz yorgunluğunu azaltmak için karanlık tema',
                      trailing: Switch(
                        value: themeProvider.isDarkMode,
                        onChanged: (_) => themeProvider.toggleTheme(),
                      ),
                      onTap: () => themeProvider.toggleTheme(),
                    );
                  },
                ),
              ]),

              const SizedBox(height: 28),

              // ── Öğretmen ──
              _sectionLabel(context, 'Öğretmen'),
              _cardGroup(context, [
                _tile(
                  context,
                  icon: Icons.favorite_outline_rounded,
                  title: 'Samimiyet',
                  subtitle: 'Öğretmen seninle ne kadar samimi konuşsun',
                  child: _samimiyetDropdown(context, chatProvider),
                ),
                _divider(context),
                _tileTap(
                  context,
                  icon: Icons.person_outline_rounded,
                  title: 'Kendini Tanıt',
                  subtitle: chatProvider.studentIntro.isEmpty
                      ? 'Öğretmen seni tanısın diye birkaç kelime'
                      : chatProvider.studentIntro,
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: context.textMuted, size: 22),
                  onTap: () => _editIntro(context, chatProvider),
                ),
              ]),

              const SizedBox(height: 28),

              // ── Diğer ──
              _sectionLabel(context, 'Diğer'),
              _cardGroup(context, [
                _tileTap(
                  context,
                  icon: Icons.flag_outlined,
                  title: 'Hata Bildir',
                  subtitle: 'Karşılaştığınız sorunları bize bildirin',
                  onTap: _submitBugReport,
                ),
                _divider(context),
                _tileTap(
                  context,
                  icon: Icons.description_outlined,
                  title: 'Gizlilik Politikası',
                  subtitle: 'Verilerinizin nasıl korunduğunu öğrenin',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                    );
                  },
                ),
              ]),

              const SizedBox(height: 28),

              // ── Cikis ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _tileTap(
                  context,
                  icon: Icons.logout_rounded,
                  title: 'Çıkış Yap',
                  iconColor: AppTheme.danger,
                  titleColor: AppTheme.danger,
                  standalone: true,
                  onTap: _handleLogout,
                ),
              ),

              const SizedBox(height: 12),

              // ── Hesabi Sil ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _tileTap(
                  context,
                  icon: Icons.delete_forever_rounded,
                  title: 'Hesabı Sil',
                  subtitle: 'Hesabınızı ve tüm verilerinizi kalıcı olarak silin',
                  iconColor: AppTheme.danger,
                  titleColor: AppTheme.danger,
                  standalone: true,
                  onTap: _handleDeleteAccount,
                ),
              ),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // Profile
  // ─────────────────────────────────────────────────────

  Widget _buildProfileTile(BuildContext context, UserModel user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.bgPrimary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderColor, width: 0.5),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  user.initials,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayNameOrEmail,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // Shared pieces
  // ─────────────────────────────────────────────────────

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: context.textSecondary,
        ),
      ),
    );
  }

  Widget _cardGroup(BuildContext context, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: context.bgPrimary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderColor, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Container(height: 0.5, color: context.borderColor),
    );
  }

  // Static info tile
  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    String? value,
    Widget? child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (child != null) child,
          if (value != null)
            Flexible(
              child: Text(
                value,
                style: TextStyle(fontSize: 14, color: context.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
        ],
      ),
    );
  }

  // Tappable tile
  Widget _tileTap(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? iconColor,
    Color? titleColor,
    bool standalone = false,
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? context.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: titleColor ?? context.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else
            Icon(Icons.chevron_right_rounded,
                size: 20, color: context.textMuted),
        ],
      ),
    );

    if (standalone) {
      return Container(
        decoration: BoxDecoration(
          color: context.bgPrimary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderColor, width: 0.5),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: content,
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }

  // ─────────────────────────────────────────────────────
  // Class dropdown
  // ─────────────────────────────────────────────────────

  Widget _classDropdown(BuildContext context, UserModel user) {
    // Eski 'TYT'/'AYT' hesapları → 'TYT/AYT'e normalize et (aksi halde value item'la
    // eşleşmez, DropdownButton assert atar). 7/11 gibi kaldırılan değerler → null (hint).
    const validLevels = ['8', '9', '10', 'TYT/AYT'];
    String? cl = user.classLevel;
    if (cl == 'TYT' || cl == 'AYT') cl = 'TYT/AYT';
    if (cl != null && !validLevels.contains(cl)) cl = null;
    return DropdownButton<String>(
      value: cl,
      underline: const SizedBox(),
      isDense: true,
      style: TextStyle(fontSize: 14, color: context.textSecondary),
      icon: Icon(Icons.unfold_more_rounded,
          size: 18, color: context.textMuted),
      items: const [
        DropdownMenuItem(value: '8', child: Text('8. Sınıf')),
        DropdownMenuItem(value: '9', child: Text('9. Sınıf')),
        DropdownMenuItem(value: '10', child: Text('10. Sınıf')),
        DropdownMenuItem(value: 'TYT/AYT', child: Text('TYT/AYT')),
      ],
      onChanged: _updateClassLevel,
      hint: Text('Seç', style: TextStyle(color: context.textMuted)),
    );
  }

  Widget _samimiyetDropdown(BuildContext context, ChatProvider chatProvider) {
    // "Çok samimi" UZAKTAN kapatılabilir (/api/app-config → samimiyet4Enabled;
    // okul veya kullanıcı bazında). Kapalıysa seçenek LİSTEDE HİÇ GÖRÜNMEZ.
    // Sunucu ayrıca istek anında da reddediyor — bu yalnız arayüz katmanı.
    final dortAcik = chatProvider.samimiyet4Enabled;
    final secili = chatProvider.samimiyet.clamp(1, dortAcik ? 4 : 3);
    return DropdownButton<int>(
      value: secili,
      underline: const SizedBox(),
      isDense: true,
      style: TextStyle(fontSize: 14, color: context.textSecondary),
      icon: Icon(Icons.unfold_more_rounded, size: 18, color: context.textMuted),
      items: [
        const DropdownMenuItem(value: 1, child: Text('Resmî')),
        const DropdownMenuItem(value: 2, child: Text('Dengeli')),
        const DropdownMenuItem(value: 3, child: Text('Samimi')),
        if (dortAcik) const DropdownMenuItem(value: 4, child: Text('Çok samimi')),
      ],
      onChanged: (v) {
        if (v != null) chatProvider.setSamimiyet(v);
      },
    );
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
        title: const Text('Kullanıcı Adı'),
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
    if (sonuc == null || !mounted) return;

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
    if (!mounted) return;
    if (basarili) {
      if (auth.user != null) auth.updateUser(auth.user!.copyWith(displayName: ad));
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı adın güncellendi')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kullanıcı adı güncellenemedi. Tekrar deneyin.'),
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
        title: const Text('Kendini Tanıt'),
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
  // Password form
  // ─────────────────────────────────────────────────────

  Widget _passwordForm(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: !_passwordExpanded
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Container(height: 0.5, color: context.borderColor),
                  const SizedBox(height: 14),
                  _pwField(_currentPasswordController, 'Mevcut Şifre'),
                  const SizedBox(height: 10),
                  _pwField(_newPasswordController, 'Yeni Şifre'),
                  const SizedBox(height: 10),
                  _pwField(_confirmPasswordController, 'Yeni Şifre (Tekrar)'),
                  if (_passwordMessage != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          _passwordSuccess
                              ? Icons.check_circle_outline_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: _passwordSuccess
                              ? AppTheme.success
                              : AppTheme.danger,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _passwordMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: _passwordSuccess
                                  ? AppTheme.success
                                  : AppTheme.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _passwordLoading ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _passwordLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Şifreyi Değiştir',
                              style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ],
              ),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }

}
