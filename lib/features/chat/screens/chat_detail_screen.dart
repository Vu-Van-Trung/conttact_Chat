import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
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
  final ImagePicker _imagePicker = ImagePicker();

  late String myUserId;
  String? receiverId;
  late String chatRoomId;
  late bool isGroup;

  String getChatRoomId(String a, String b) {
    if (a.compareTo(b) > 0) {
      return '${a}_$b';
    } else {
      return '${b}_$a';
    }
  }

  MessageType _parseMessageType(String? type) {
    switch (type) {
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      case 'emoji':
        return MessageType.emoji;
      default:
        return MessageType.text;
    }
  }

  String _serializeType(MessageType type) {
    switch (type) {
      case MessageType.image:
        return 'image';
      case MessageType.file:
        return 'file';
      case MessageType.emoji:
        return 'emoji';
      case MessageType.text:
        return 'text';
    }
  }

  @override
  void initState() {
    super.initState();
    myUserId = _auth.currentUser?.uid ?? '';
    isGroup = widget.conversation.isGroup;
    receiverId = isGroup ? null : widget.conversation.partner.id;
    chatRoomId = isGroup
        ? widget.conversation.id
        : getChatRoomId(myUserId, receiverId ?? widget.conversation.partner.id);

    _ensureChatRoom();

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
          type: _parseMessageType(data['type']?.toString()),
          attachmentUrl: data['attachmentUrl']?.toString(),
          attachmentName: data['attachmentName']?.toString(),
        );
      }).toList();

      setState(() => _messages = dbMessages);
    }, onError: (error) {
      debugPrint('Error fetching messages: $error');
    });
  }

  Future<void> _ensureChatRoom() async {
    final participants = isGroup
        ? widget.conversation.memberIds
        : [myUserId, receiverId ?? widget.conversation.partner.id];

    final payload = <String, dynamic>{
      'users': participants,
      'groupMembers': isGroup ? participants : null,
      'isGroup': isGroup,
      'groupName': isGroup ? widget.conversation.partner.name : null,
      'lastMessage': widget.conversation.lastMessageText ?? 'Bắt đầu trò chuyện',
      'lastMessageTime': FieldValue.serverTimestamp(),
    };
    await _firestore.collection('chatRooms').doc(chatRoomId).set(payload, SetOptions(merge: true));
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    await _sendMessagePayload(
      text: text,
      type: MessageType.text,
    );
    _messageController.clear();
  }

  Future<void> _sendMessagePayload({
    required String text,
    required MessageType type,
    String? attachmentUrl,
    String? attachmentName,
  }) async {
    setState(() => _isSending = true);

    try {
      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': myUserId,
        'receiverId': receiverId,
        'text': text,
        'type': _serializeType(type),
        'attachmentUrl': attachmentUrl,
        'attachmentName': attachmentName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      final preview = switch (type) {
        MessageType.image => 'Da gui mot hinh anh',
        MessageType.file => 'Da gui tep: ${attachmentName ?? 'tap tin'}',
        MessageType.emoji => text,
        MessageType.text => text,
      };

      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .set({
        'lastMessage': preview,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'users': isGroup
            ? widget.conversation.memberIds
            : [myUserId, receiverId ?? widget.conversation.partner.id],
        'groupMembers': isGroup ? widget.conversation.memberIds : null,
        'isGroup': isGroup,
        'groupName': isGroup ? widget.conversation.partner.name : null,
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

  Future<void> _pickAndSendImage() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null) return;
    await _sendMessagePayload(
      text: 'Hinh anh',
      type: MessageType.image,
      attachmentUrl: image.path,
      attachmentName: image.name,
    );
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final file = result?.files.first;
    if (file == null) return;
    await _sendMessagePayload(
      text: file.name,
      type: MessageType.file,
      attachmentUrl: file.path,
      attachmentName: file.name,
    );
  }

  void _showAttachmentMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined, color: Colors.white),
                title: const Text('Gui hinh anh', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickAndSendImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file, color: Colors.white),
                title: const Text('Gui tap tin', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickAndSendFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEmojiPicker() {
    const emojis = ['😀', '😂', '😍', '🥳', '👍', '❤️', '🔥', '🎉', '🙏', '😎'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (_) {
        return SafeArea(
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 5,
            padding: const EdgeInsets.all(16),
            children: emojis
                .map(
                  (emoji) => IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      final current = _messageController.text;
                      _messageController.text = '$current$emoji';
                      _messageController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _messageController.text.length),
                      );
                    },
                    icon: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
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
                  backgroundColor: const Color(0xFF667EEA).withValues(alpha: 0.3),
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
                    isGroup
                        ? '${widget.conversation.memberIds.length} thanh vien'
                        : (partner.isOnline ? 'Dang hoat dong' : (partner.lastSeen ?? 'Ngoai tuyen')),
                    style: TextStyle(
                      fontSize: 12,
                      color: (!isGroup && partner.isOnline)
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
              onAttachmentTap: _showAttachmentMenu,
              onEmojiTap: _showEmojiPicker,
              isSending: _isSending,
            ),
          ],
        ),
      ),
    );
  }
}
