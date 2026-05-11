import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/vds_service.dart';
import '../../screens/settings/settings_screen.dart';

class NavDrawer extends StatelessWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final user = authProvider.user;

    return Drawer(
      backgroundColor: context.bgSecondary,
      child: SafeArea(
        child: Column(
          children: [
            // Header with Logo
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: context.bgPrimary,
                      boxShadow: AppTheme.shadowSm,
                    ),
                    padding: const EdgeInsets.all(7),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.asset(
                        'assets/images/karahayri.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MaariFx',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '2.7',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: context.borderColor),

            // New Chat Button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    chatProvider.startNewChat();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.add_rounded, size: 22),
                  label: const Text('Yeni Sohbet'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),

            // Chats Section Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.history_rounded,
                      size: 16, color: context.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Sohbet Gecmisi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Chat List
            Expanded(
              child: _ChatHistoryList(userId: user?.uid),
            ),

            Divider(height: 1, color: context.borderColor),

            // User Account Section
            if (user != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop(); // Drawer'ı kapat
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppTheme.primary, AppTheme.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              user.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.displayNameOrEmail,
                                style: TextStyle(
                                  fontSize: 14,
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
                                  fontSize: 12,
                                  color: context.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.bgTertiary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: context.textSecondary,
                            size: 20,
                          ),
                        ),
                      ],
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

  Future<void> _hideConversation(String conversationId) async {
    final chatProvider = context.read<ChatProvider>();
    if (chatProvider.currentConversationId == conversationId) {
      chatProvider.startNewChat();
    }

    setState(() {
      _hiddenIds.add(conversationId);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenKey, _hiddenIds.toList());
  }

  void _showDeleteSheet(BuildContext context, ConversationSummary conv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.bgPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  conv.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.danger),
                title: const Text(
                  'Sohbeti Sil',
                  style: TextStyle(color: AppTheme.danger),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _hideConversation(conv.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId == null) {
      return Center(
        child: Text(
          'Giriş yapınız',
          style: TextStyle(color: context.textMuted),
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final allConversations = _conversations
        .where((c) => !_hiddenIds.contains(c.id))
        .toList();

    final conversations = _searchQuery.isEmpty
        ? allConversations
        : allConversations
            .where((c) =>
                c.title.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return Column(
      children: [
        // Search field
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: TextStyle(fontSize: 13, color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'Sohbet ara...',
                hintStyle: TextStyle(fontSize: 13, color: context.textMuted),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 18, color: context.textMuted),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Icon(Icons.close_rounded,
                            size: 18, color: context.textMuted),
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: context.bgTertiary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1),
                ),
              ),
            ),
          ),

        // Conversation list
        Expanded(
          child: conversations.isEmpty
              ? _buildEmptyState(context, allConversations.isEmpty)
              : ListView.builder(
                  controller: _searchQuery.isEmpty ? _scrollController : null,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: conversations.length + (_isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= conversations.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final conv = conversations[index];
                    return _ChatListItem(
                      conversation: conv,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.bgTertiary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                noConversationsAtAll
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.search_off_rounded,
                size: 36,
                color: context.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              noConversationsAtAll ? 'Henüz sohbet yok' : 'Sonuç bulunamadı',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              noConversationsAtAll
                  ? 'Yeni bir sohbet baslatmak icin\nyukardaki butonu kullanin'
                  : 'Farkli bir arama terimi deneyin',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatListItem extends StatelessWidget {
  final ConversationSummary conversation;
  final VoidCallback? onLongPress;

  const _ChatListItem({required this.conversation, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            final chatProvider = context.read<ChatProvider>();
            chatProvider.loadConversation(conversation.id);
            Navigator.of(context).pop();
          },
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.bgTertiary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    conversation.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: context.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
