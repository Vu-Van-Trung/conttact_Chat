import 'package:flutter/material.dart';
import '../../../widgets/gradient_background.dart';
import '../../contacts/models/contact_model.dart';
import '../models/conversation_model.dart';
import '../widgets/chat_list_item.dart';
import 'chat_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  void _navigateToDetail(Conversation conversation) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(conversation: conversation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Center(
        child: Text(
          'Vui lòng đăng nhập',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return GradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                   const Text(
                    'Tin nhắn',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white70),
                    onPressed: () {
                      // Logic tìm kiếm có thể thêm sau
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('chatRooms')
                    .where('users', arrayContains: currentUser.uid)
                    .orderBy('lastMessageTime', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmptyState();
                  }

                  final docs = snapshot.data!.docs;
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final users = data['users'] as List<dynamic>;

                      if (users.length < 2) return const SizedBox.shrink();

                      final partnerId = users.firstWhere(
                        (id) => id != currentUser.uid,
                        orElse: () => null,
                      );
                      if (partnerId == null) return const SizedBox.shrink();

                      return FutureBuilder<DocumentSnapshot>(
                        future: _firestore.collection('users').doc(partnerId).get(),
                        builder: (context, userSnapshot) {
                          if (!userSnapshot.hasData) return const SizedBox.shrink();

                          final userData =
                              userSnapshot.data?.data() as Map<String, dynamic>?;
                          if (userData == null) return const SizedBox.shrink();

                          final contact = Contact(
                            id: partnerId,
                            name: userData['username'] ??
                                userData['email'] ??
                                'Đang tải...',
                            phoneNumber: userData['phoneNumber'] ?? '',
                            avatarUrl: userData['avatarUrl'],
                            isOnline: userData['isOnline'] ?? false,
                          );

                          final conversation = Conversation(
                            id: docs[index].id,
                            partner: contact,
                            messages: [],
                            lastMessageText: data['lastMessage'] ?? 'Bắt đầu trò chuyện',
                            lastMessageTime:
                                (data['lastMessageTime'] as Timestamp?)?.toDate(),
                          );

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ChatListItem(
                              conversation: conversation,
                              onTap: () => _navigateToDetail(conversation),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 24),
          const Text(
            'Chưa có cuộc hội thoại nào',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hãy tìm bạn bè trong Danh bạ để bắt đầu nhắn tin',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
