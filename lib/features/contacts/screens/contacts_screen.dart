import 'package:flutter/material.dart';
import '../../../widgets/gradient_background.dart';
import '../models/contact_model.dart';
import '../widgets/contact_list_item.dart';
import '../../../services/friend_service.dart';
import '../../chat/models/conversation_model.dart';
import '../../chat/screens/chat_detail_screen.dart';
import 'add_friend_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _friendService = FriendService();
  List<Contact> _friends = [];
  List<Contact> _filteredFriends = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  void _fetchFriends() {
    _friendService.getFriends().listen((friends) {
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _filterFriends(_searchQuery);
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterFriends(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredFriends = List.from(_friends);
      } else {
        _filteredFriends = _friends.where((friend) {
          final nameMatch = friend.name.toLowerCase().contains(_searchQuery);
          return nameMatch;
        }).toList();
      }
    });
  }

  void _handleContactTap(Contact contact) {
    final conversation = Conversation(
      id: contact.id, // Using partner's ID as conversation ID placeholder, ChatDetailScreen will generate chatRoomId
      partner: contact,
      messages: [],
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(conversation: conversation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            // Header with Add Friend button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text(
                    'Danh bạ của bạn',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_add_outlined, color: Color(0xFF667EEA)),
                    onPressed: () {
                       Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AddFriendScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: _filterFriends,
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm bạn bè...',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color.fromRGBO(255, 255, 255, 0.6),
                  ),
                ),
              ),
            ),

            // Friend Requests Section
            _buildFriendRequests(),

            // Contact list
            Expanded(
              child: _buildContactList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendRequests() {
    final currentUserId = _friendService.currentUserId;
    if (currentUserId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friendRequests')
          .where('to', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        // Deduplicate requests by fromId just in case
        final docs = snapshot.data!.docs;
        final uniqueFromIds = <String>{};
        final requests = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final fromId = data['from'];
          if (uniqueFromIds.contains(fromId)) return false;
          uniqueFromIds.add(fromId);
          return true;
        }).toList();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lời mời kết bạn',
                style: TextStyle(color: Color(0xFF667EEA), fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...requests.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final fromId = data['from'];
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(fromId).get(),
                  builder: (context, userSnapshot) {
                    if (!userSnapshot.hasData) return const SizedBox.shrink();
                    final fromUser = userSnapshot.data?.data() as Map<String, dynamic>?;
                    if (fromUser == null) return const SizedBox.shrink();
                    
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(fromUser['username'] ?? fromUser['email'] ?? 'Người dùng', style: const TextStyle(color: Colors.white)),
                      subtitle: const Text('Muốn kết bạn với bạn', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () => _friendService.acceptFriendRequest(doc.id, fromId),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => doc.reference.update({'status': 'rejected'}),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContactList() {
    if (_friends.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Color.fromRGBO(255, 255, 255, 0.3)),
            SizedBox(height: 16),
            Text(
              'Chưa có bạn bè nào',
              style: TextStyle(fontSize: 18, color: Color.fromRGBO(255, 255, 255, 0.7)),
            ),
            SizedBox(height: 8),
            Text(
              'Gửi lời mời kết bạn bằng email của họ',
              style: TextStyle(fontSize: 14, color: Color.fromRGBO(255, 255, 255, 0.5)),
            ),
          ],
        ),
      );
    }

    if (_filteredFriends.isEmpty) {
      return const Center(
        child: Text('Không tìm thấy bạn bè nào', style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredFriends.length,
      itemBuilder: (context, index) {
        final friend = _filteredFriends[index];
        return ContactListItem(
          contact: friend,
          onTap: () => _handleContactTap(friend),
        );
      },
    );
  }
}
