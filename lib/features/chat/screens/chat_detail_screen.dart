import 'package:flutter/material.dart';
import '../../../widgets/gradient_background.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatDetailScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatDetailScreen({super.key, required this.conversation});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  List<Message> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late String myUserId; 
  late String receiverId;
  late String chatRoomId;

  String getChatRoomId(String a, String b) {
    if (a.compareTo(b) > 0) {
      return '${a}_$b';
    } else {
      return '${b}_$a';
    }
  }

  @override
  void initState() {
    super.initState();
    myUserId = _auth.currentUser?.uid ?? "";
    receiverId = widget.conversation.partner.id;
    chatRoomId = getChatRoomId(myUserId, receiverId);

    // Lắng nghe tin nhắn từ Firestore
    _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final dbMessages = snapshot.docs.map((doc) {
        final data = doc.data();
        bool isMyMessage = data['senderId'] == myUserId;
        Timestamp? t = data['timestamp'] as Timestamp?;
        return Message(
          id: doc.id,
          text: data['text'] ?? '',
          timestamp: t?.toDate() ?? DateTime.now(),
          isSender: isMyMessage,
          isRead: true,
        );
      }).toList();

      setState(() {
        _messages = dbMessages;
      });
    }, onError: (error) {
       debugPrint('Error fetching messages: $error');
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    setState(() => _isSending = true);
    _messageController.clear();

    try {
      // Gửi tin nhắn lên Firestore
      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': myUserId,
        'receiverId': receiverId,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Cập nhật thông tin phòng chat
      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId).set({
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'users': [myUserId, receiverId],
      }, SetOptions(merge: true));

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi gửi tin nhắn: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.conversation.partner;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 1,
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF667EEA).withOpacity(0.3),
                  backgroundImage: partner.avatarUrl != null
                      ? NetworkImage(partner.avatarUrl!)
                      : null,
                  child: partner.avatarUrl == null
                      ? Text(
                          partner.name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                if (partner.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ECDC4),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1A1A2E), // Match background
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    partner.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    partner.isOnline ? 'Đang hoạt động' : (partner.lastSeen ?? 'Ngoại tuyến'),
                    style: TextStyle(
                      fontSize: 12,
                      color: partner.isOnline
                          ? const Color(0xFF4ECDC4)
                          : const Color.fromRGBO(255, 255, 255, 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            onPressed: () {}, // Not implemented
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () {}, // Not implemented
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GradientBackground(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                reverse: true, // Show bottom to top
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  // For reverse ListView, index 0 is at bottom
                  final message = _messages[index];
                  return MessageBubble(
                    message: message,
                    partner: partner,
                  );
                },
              ),
            ),
            ChatInputField(
              controller: _messageController,
              onSend: _sendMessage,
              isSending: _isSending,
            ),
          ],
        ),
      ),
    );
  }
}
