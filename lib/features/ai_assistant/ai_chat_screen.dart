import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nusa_kasir/core/providers.dart';
import 'package:nusa_kasir/core/config/nusa_config.dart';
import 'package:nusa_kasir/core/services/ai_service.dart';
import 'package:nusa_kasir/shared/widgets/screen_scaffold.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});
  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <ChatMessage>[];
  bool _loading = false;
  String? _storeName;

  @override
  void initState() {
    super.initState();
    _loadStoreName();
    _messages.add(ChatMessage(
      role: 'assistant',
      content:
          'ðŸ‘‹ Halo! Saya AI Assistant NUSA Kasir. Tanya apa saja — stok, laporan, tips bisnis, atau cara pakai fitur. Ada yang bisa saya bantu?',
    ));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStoreName() async {
    final name = await ref.read(settingsRepoProvider).getStoreName();
    if (mounted && name.isNotEmpty) setState(() => _storeName = name);
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _loading = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    try {
      final svc = AiService(Supabase.instance.client);
      final reply = await svc.chat(
        messages: _messages,
        storeName: _storeName,
      );

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(role: 'assistant', content: reply));
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
              role: 'assistant', content: '⚠ï¸ Gagal: $e'));
          _loading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScreenScaffold(
      'AI Assistant',
      Column(
        children: [
          // Header info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: NusaConfig.primaryColor.withValues(alpha: 0.06),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: NusaConfig.primaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _storeName != null
                        ? 'AI Assistant • $_storeName'
                        : 'AI Assistant NUSA Kasir',
                    style: const TextStyle(
                        fontSize: 12,
                        color: NusaConfig.primaryColor,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: NusaConfig.accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('BETA',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: NusaConfig.accentGreen)),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) {
                  return _typingIndicator(isDark);
                }
                return _bubble(_messages[i], isDark);
              },
            ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: isDark ? NusaConfig.darkSurface : Colors.white,
              border: Border(
                top: BorderSide(
                    color: isDark ? NusaConfig.darkDivider : NusaConfig.dividerColor),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark
                            ? NusaConfig.darkTextPrimary
                            : isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Tanya tentang NUSA Kasir...',
                        hintStyle: TextStyle(color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary),
                        filled: true,
                        fillColor: isDark
                            ? NusaConfig.darkSurface2
                            : NusaConfig.backgroundColor,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _loading
                          ? NusaConfig.primaryColor.withValues(alpha: 0.3)
                          : NusaConfig.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _loading ? null : _send,
                      icon: Icon(_loading ? Icons.hourglass_top : Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage msg, bool isDark) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: NusaConfig.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 16, color: NusaConfig.primaryColor),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? NusaConfig.primaryColor
                    : (isDark ? NusaConfig.darkSurface2 : NusaConfig.surfaceColor),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
              ),
              child: Text(
                msg.content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isUser
                      ? Colors.white
                      : (isDark
                          ? NusaConfig.darkTextPrimary
                          : isDark ? NusaConfig.darkTextPrimary : NusaConfig.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: NusaConfig.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome,
                size: 16, color: NusaConfig.primaryColor),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? NusaConfig.darkSurface2 : NusaConfig.surfaceColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(
                  color: isDark ? NusaConfig.darkBorder : NusaConfig.borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(isDark: isDark),
                const SizedBox(width: 4),
                _dot(delay: 200, isDark: isDark),
                const SizedBox(width: 4),
                _dot(delay: 400, isDark: isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot({int delay = 0, required bool isDark}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (_, val, __) => Opacity(
        opacity: val,
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: isDark ? NusaConfig.darkTextTertiary : NusaConfig.textTertiary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
