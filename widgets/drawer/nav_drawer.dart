import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/vds_service.dart';
import '../../screens/settings/settings_screen.dart';
import '../common/class_level_sheet.dart';
import '../common/ui_bits.dart';

/// Çekmece: yazı-logo + yeni sohbet kalemi, arama, tarihe göre gruplu düz
/// satırlar, altta profil. Satırlarda ikon ve ok yok; açık sohbet tintli.
class NavDrawer extends StatelessWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final user = authProvider.user;

    return Drawer(
      backgroundColor: context.bgSecondary,
      elevation: 1,
      width: 300,
      child: SafeArea(
        child: Column(
          children: [
            // Başlık: yazı-logo + yeni sohbet
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 12, 12),
              child: Row(
                children: [
                  const MaarifxYazi(height: 27),
                  const Spacer(),
                  Tooltip(
                    message: 'Yeni sohbet',
                    child: InkWell(
                      onTap: () {
                        chatProvider.startNewChat();
                        Navigator.of(context).pop();
                      },
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: context.bgPrimary,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Icon(Icons.edit_outlined, size: 21, color: context.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Sohbet listesi (arama + gruplar)
            Expanded(
              child: _ChatHistoryList(userId: user?.uid),
            ),

            // Profil satırı → Ayarlar
            if (user != null) ...[
              Divider(height: 1, color: context.borderColor),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop(); // çekmeceyi kapat
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 14, 14),
                    child: Row(
                      children: [
                        BasHarfDairesi(harfler: user.initials),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.displayNameOrEmail,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                  color: context.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _altSatir(user.classLevel, user.email),
                                style: context.mono(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.settings_outlined, size: 18, color: context.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Profil altında sınıf; sınıf yoksa e-posta.
  static String _altSatir(String? classLevel, String email) {
    final n = normalizeSinifSeviyesi(classLevel);
    if (n != null) {
      final s = kSinifSeviyeleri.where((x) => x.deger == n);
      if (s.isNotEmpty) return s.first.etiket.replaceAll('Sınıf', 'sınıf');
    }
    return email;
  }
}

class _ChatHistoryList extends StatefulWidget {
  final String? userId;

  const _ChatHistoryList({this.userId});

  @override
  State<_ChatHistoryList> createState() => _ChatHistoryListState();
}

class _ChatHistoryListState extends State<_ChatHistoryList> {
  final List<ConversationSummary> _conversations = [];
  Set<String> _hiddenIds = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _total = 0;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  static const _hiddenKey = 'hidden_conversation_ids';
  static const _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100 &&
        !_isLoadingMore &&
        _hasMore &&
        _searchQuery.isEmpty) {
      _loadMore();
    }
  }

  Future<void> _loadConversations() async {
    if (widget.userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    final chatProvider = context.read<ChatProvider>();
    final prefs = await SharedPreferences.getInstance();
    // GERİYE UYUM: eski sürümlerde "Sil" yalnız cihazda gizliyordu. O kayıtlar
    // sunucuda hâlâ duruyor; kullanıcının beklentisini bozmamak için gizli
    // kalmaya devam ediyorlar. Yeni silmeler sunucudan gerçekten siliniyor.
    final hiddenList = prefs.getStringList(_hiddenKey) ?? [];
    final result = await chatProvider.getConversations(limit: _pageSize, offset: 0);
    if (mounted) {
      setState(() {
        _hiddenIds = hiddenList.toSet();
        _conversations.clear();
        _conversations.addAll(result.conversations);
        _total = result.total;
        _hasMore = _conversations.length < _total;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    final chatProvider = context.read<ChatProvider>();
    final result = await chatProvider.getConversations(
      limit: _pageSize,
      offset: _conversations.length,
    );
    if (mounted) {
      setState(() {
        _conversations.addAll(result.conversations);
        _hasMore = _conversations.length < _total;
        _isLoadingMore = false;
      });
    }
  }

  /// Sohbeti GERÇEKTEN siler (önce onay; silme başarısızsa liste değişmez).
  Future<void> _deleteConversation(String conversationId) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sohbet silinsin mi?'),
        content: const Text(
          'Bu sohbetteki tüm mesajlar, fotoğraflar ve çözümler kalıcı olarak '
          'silinir. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ctx.pen),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    final chatProvider = context.read<ChatProvider>();
    final silindi = await chatProvider.vdsService.deleteConversation(conversationId);
    if (!mounted) return;

    if (!silindi) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sohbet silinemedi. Bağlantını kontrol edip tekrar dene.'),
      ));
      return;
    }

    if (chatProvider.currentConversationId == conversationId) {
      chatProvider.startNewChat();
    }
    setState(() {
      _conversations.removeWhere((c) => c.id == conversationId);
      if (_total > 0) _total--;
      _hasMore = _conversations.length < _total;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sohbet silindi'),
    ));
  }

  void _showDeleteSheet(BuildContext context, ConversationSummary conv) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetTutamac(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  conv.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: ctx.pen),
                title: Text('Sohbeti sil', style: TextStyle(color: ctx.pen)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteConversation(conv.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tarih grubu: Bugün / Dün / Bu hafta / Daha eski.
  static String _grup(DateTime t, DateTime simdi) {
    final bugun = DateTime(simdi.year, simdi.month, simdi.day);
    final gun = DateTime(t.year, t.month, t.day);
    final fark = bugun.difference(gun).inDays;
    if (fark <= 0) return 'Bugün';
    if (fark == 1) return 'Dün';
    if (fark < 7) return 'Bu hafta';
    if (fark < 30) return 'Bu ay';
    return 'Daha eski';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId == null) {
      return Center(
        child: Text('Giriş yapınca sohbetlerin burada görünür',
            style: TextStyle(color: context.textMuted, fontSize: 13)),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final allConversations =
        _conversations.where((c) => !_hiddenIds.contains(c.id)).toList();

    final conversations = _searchQuery.isEmpty
        ? allConversations
        : allConversations
            .where((c) =>
                c.title.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    // Düz liste: grup başlığı (String) ya da sohbet (ConversationSummary)
    final simdi = DateTime.now();
    final ogeler = <Object>[];
    String? sonGrup;
    for (final c in conversations) {
      final g = _grup(c.updatedAt.toLocal(), simdi);
      if (g != sonGrup) {
        ogeler.add(g);
        sonGrup = g;
      }
      ogeler.add(c);
    }
    final acikId = context.select<ChatProvider, String?>((p) => p.currentConversationId);

    return Column(
      children: [
        // Arama
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: TextStyle(fontSize: 14.5, color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'Sohbetlerde ara',
                hintStyle: TextStyle(fontSize: 14.5, color: context.textMuted),
                prefixIcon: Icon(Icons.search_rounded, size: 19, color: context.textMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 0),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                filled: true,
                fillColor: context.bgPrimary,
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
                  borderSide: BorderSide(color: context.blue, width: 1.2),
                ),
              ),
            ),
          ),
        ),

        // Liste
        Expanded(
          child: conversations.isEmpty
              ? _buildEmptyState(context, allConversations.isEmpty)
              : ListView.builder(
                  controller: _searchQuery.isEmpty ? _scrollController : null,
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                  itemCount: ogeler.length + (_isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= ogeler.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final o = ogeler[index];
                    if (o is String) {
                      return Padding(
                        padding: EdgeInsets.fromLTRB(10, index == 0 ? 6 : 14, 10, 4),
                        child: Text(trBuyuk(o), style: context.eyebrow),
                      );
                    }
                    final conv = o as ConversationSummary;
                    return _ChatListItem(
                      conversation: conv,
                      acik: conv.id == acikId,
                      onLongPress: () => _showDeleteSheet(context, conv),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, bool noConversationsAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          noConversationsAtAll
              ? 'Henüz sohbet yok.\nİlk sorunu sorunca burada görünür.'
              : 'Sonuç yok',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: context.textMuted),
        ),
      ),
    );
  }
}

class _ChatListItem extends StatelessWidget {
  final ConversationSummary conversation;
  final bool acik;
  final VoidCallback? onLongPress;

  const _ChatListItem({
    required this.conversation,
    required this.acik,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: acik ? context.tint : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          final chatProvider = context.read<ChatProvider>();
          chatProvider.loadConversation(conversation.id);
          Navigator.of(context).pop();
        },
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Text(
            conversation.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: acik ? FontWeight.w500 : FontWeight.w400,
              color: context.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
