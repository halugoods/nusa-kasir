import 'package:supabase_flutter/supabase_flutter.dart';

/// AI chat message.
class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };
}

/// Calls the Supabase Edge Function `ai-assistant` for AI chat.
class AiService {
  final SupabaseClient supabase;

  AiService(this.supabase);

  /// Send a conversation and get the assistant's reply.
  /// [messages] includes the full history (user + assistant turns).
  /// [storeName] is optional — adds store context to the prompt.
  Future<String> chat({
    required List<ChatMessage> messages,
    String? storeName,
  }) async {
    final body = {
      'messages': messages.map((m) => m.toJson()).toList(),
      if (storeName != null) 'store_name': storeName,
    };

    try {
      final res = await supabase.functions.invoke(
        'ai-assistant',
        body: body,
      );

      if (res.status >= 400) {
        return 'Maaf, AI Assistant sedang tidak tersedia.';
      }

      final data = res.data as Map<String, dynamic>;
      return data['reply'] as String? ?? 'Maaf, tidak ada jawaban.';
    } catch (e) {
      return 'Gagal menghubungi AI Assistant: $e';
    }
  }
}
