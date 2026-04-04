import '../../contacts/models/contact_model.dart';
import 'message_model.dart';

class Conversation {
  final String id;
  final Contact partner;
  final List<Message> messages;
  final int unreadCount;
  final String? lastMessageText;
  final DateTime? lastMessageTime;
  final bool isGroup;
  final List<String> memberIds;

  const Conversation({
    required this.id,
    required this.partner,
    required this.messages,
    this.unreadCount = 0,
    this.lastMessageText,
    this.lastMessageTime,
    this.isGroup = false,
    this.memberIds = const [],
  });

  Message? get lastMessage {
    if (messages.isNotEmpty) return messages.last;
    if (lastMessageText != null && lastMessageTime != null) {
      return Message(
        id: 'last',
        text: lastMessageText!,
        timestamp: lastMessageTime!,
        isSender: false, // Defaulting to false for preview
        isRead: true,
      );
    }
    return null;
  }
}
