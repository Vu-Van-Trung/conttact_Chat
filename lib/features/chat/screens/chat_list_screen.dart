import 'package:flutter/material.dart';
import '../../../widgets/gradient_background.dart';
import '../../contacts/models/contact_model.dart';
import '../../../services/friend_service.dart';
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
  final FriendService _friendService = FriendService();

  String _displayNameFromUser(Map<String, dynamic> data) {
    final fullName = (data['fullName'] ?? '').toString().trim();
    final username = (data['username'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();

    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    if (email.isNotEmpty) return email;
    return 'Dang tai...';
  }

  String _groupRoomId(List<String> memberIds) {
    final sorted = [...memberIds]..sort();
    return 'group_${sorted.join('_')}';
  }

  void _navigateToDetail(Conversation conversation) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(conversation: conversation),
      ),
    );
  }

  Future<void> _showCreateGroupSheet(String currentUserId) async {
    final controller = TextEditingController();
    final selectedIds = <String>{};
    bool isCreating = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tao nhom chat',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(hintText: 'Ten nhom'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 260,
                      child: StreamBuilder<List<Contact>>(
                        stream: _friendService.getFriends(),
                        builder: (context, snapshot) {
                          final friends = snapshot.data ?? const <Contact>[];
                          if (friends.isEmpty) {
                            return const Center(
                              child: Text('Khong co ban be de tao nhom', style: TextStyle(color: Colors.white60)),
                            );
                          }

                          return ListView.builder(
                            itemCount: friends.length,
                            itemBuilder: (context, index) {
                              final friend = friends[index];
                              final checked = selectedIds.contains(friend.id);
                              return CheckboxListTile(
                                value: checked,
                                activeColor: const Color(0xFF667EEA),
                                title: Text(friend.name, style: const TextStyle(color: Colors.white)),
                                onChanged: (value) {
                                  setModalState(() {
                                    if (value == true) {
                                      selectedIds.add(friend.id);
                                    } else {
                                      selectedIds.remove(friend.id);
                                    }
                                  });
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isCreating
                            ? null
                            : () async {
                          final messenger = ScaffoldMessenger.of(this.context);
                          final groupName = controller.text.trim();
                          if (groupName.isEmpty || selectedIds.isEmpty) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Nhap ten nhom va chon it nhat 1 thanh vien'),
                              ),
                            );
                            return;
                          }

                          setModalState(() => isCreating = true);

                          try {
                            final users = <String>{currentUserId, ...selectedIds}.toList();
                            final roomId = _groupRoomId(users);

                            await _firestore.collection('chatRooms').doc(roomId).set({
                              'users': users,
                              'groupMembers': users,
                              'isGroup': true,
                              'groupName': groupName,
                              'createdBy': currentUserId,
                              'createdAt': FieldValue.serverTimestamp(),
                              'lastMessage': 'Nhom vua duoc tao',
                              'lastMessageTime': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));

                            if (!mounted) return;
                            Navigator.pop(context);
                            messenger.showSnackBar(
                              SnackBar(content: Text('Da tao nhom "$groupName" thanh cong')),
                            );

                            _navigateToDetail(
                              Conversation(
                                id: roomId,
                                partner: Contact(
                                  id: roomId,
                                  name: groupName,
                                  phoneNumber: '',
                                  isOnline: false,
                                ),
                                messages: const [],
                                isGroup: true,
                                memberIds: users,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setModalState(() => isCreating = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text('Tao nhom that bai: $e')),
                            );
                          }
                        },
                        child: const Text('Tao nhom'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
                  IconButton(
                    icon: const Icon(Icons.group_add_outlined, color: Colors.white70),
                    onPressed: () => _showCreateGroupSheet(currentUser.uid),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('chatRooms')
                    .where('users', arrayContains: currentUser.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Khong tai duoc danh sach chat: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmptyState();
                  }

                  final docs = snapshot.data!.docs.toList()
                    ..sort((a, b) {
                      final aData = a.data() as Map<String, dynamic>;
                      final bData = b.data() as Map<String, dynamic>;
                      final aTime = (aData['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                      final bTime = (bData['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                      return bTime.compareTo(aTime);
                    });
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final users = data['users'] as List<dynamic>;

                      final isGroup = data['isGroup'] == true;
                      if (isGroup) {
                        final groupName = (data['groupName'] ?? 'Nhom chat').toString();
                        final groupMembers = (data['groupMembers'] as List<dynamic>? ?? users)
                            .map((e) => e.toString())
                            .toList();
                        final conversation = Conversation(
                          id: docs[index].id,
                          partner: Contact(
                            id: docs[index].id,
                            name: groupName,
                            phoneNumber: '',
                            avatarUrl: data['groupAvatarUrl']?.toString(),
                            isOnline: false,
                          ),
                          messages: const [],
                          lastMessageText: data['lastMessage']?.toString() ?? 'Bat dau tro chuyen',
                          lastMessageTime: (data['lastMessageTime'] as Timestamp?)?.toDate(),
                          isGroup: true,
                          memberIds: groupMembers,
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ChatListItem(
                            conversation: conversation,
                            onTap: () => _navigateToDetail(conversation),
                          ),
                        );
                      }

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
                            name: _displayNameFromUser(userData),
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
            color: Colors.white.withValues(alpha: 0.1),
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
