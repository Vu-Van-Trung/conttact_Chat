import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../features/contacts/models/contact_model.dart';

class FriendService {
      String _displayNameFromUser(Map<String, dynamic> data) {
        final fullName = (data['fullName'] ?? '').toString().trim();
        final username = (data['username'] ?? '').toString().trim();
        final email = (data['email'] ?? '').toString().trim();

        if (fullName.isNotEmpty) return fullName;
        if (username.isNotEmpty) return username;
        if (email.isNotEmpty) return email;
        return 'Unknown';
      }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Search for users by email
  Future<List<Contact>> searchUsers(String email) async {
    if (email.isEmpty) return [];
    
    final snapshot = await _firestore
        .collection('users')
        .where('email', isGreaterThanOrEqualTo: email)
        .where('email', isLessThanOrEqualTo: '$email\uf8ff')
        .get();

    return snapshot.docs
        .where((doc) => doc.id != currentUserId)
        .map((doc) => _contactFromDoc(doc))
        .toList();
  }

  // Send friend request
  Future<String?> sendFriendRequest(String targetUserId) async {
    final myId = currentUserId;
    if (myId == null) return 'Chưa đăng nhập';
    if (myId == targetUserId) return 'Bạn không thể kết bạn với chính mình';

    // 1. Check if already friends
    final friendshipId = myId.compareTo(targetUserId) < 0 
        ? '${myId}_$targetUserId' 
        : '${targetUserId}_$myId';
    
    final friendshipDoc = await _firestore.collection('friendships').doc(friendshipId).get();
    if (friendshipDoc.exists) return 'Đã là bạn bè';

    // 2. Check if a request already exists (either direction)
    // We'll search for any pending request. If it was rejected, we might allow sending again,
    // but the user said "chỉ được gửi 1 lần". Let's check for PENDING or ACCEPTED.
    
    final sentRequest = await _firestore
        .collection('friendRequests')
        .where('from', isEqualTo: myId)
        .where('to', isEqualTo: targetUserId)
        .get();

    if (sentRequest.docs.isNotEmpty) {
      final status = sentRequest.docs.first.data()['status'];
      if (status == 'pending') return 'Đã gửi lời mời trước đó';
      if (status == 'accepted') return 'Đã là bạn bè';
      return 'Bạn đã gửi lời mời trước đó'; // For rejected or others
    }

    final receivedRequest = await _firestore
        .collection('friendRequests')
        .where('from', isEqualTo: targetUserId)
        .where('to', isEqualTo: myId)
        .where('status', isEqualTo: 'pending')
        .get();

    if (receivedRequest.docs.isNotEmpty) return 'Người này đã gửi lời mời cho bạn';

    // 3. Send new request
    // Using a predictable ID to prevent duplicates at the database level
    final requestId = '${myId}_$targetUserId';
    await _firestore.collection('friendRequests').doc(requestId).set({
      'from': myId,
      'to': targetUserId,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    
    return null; // Success
  }

  // Get friends list (real-time)
  Stream<List<Contact>> getFriends() {
    if (currentUserId == null) return const Stream.empty();

    // In a real app, you'd check a 'friendships' collection.
    // For simplicity here, we'll mark users as friends if they have an active friendship record.
    return _firestore
        .collection('friendships')
        .where('users', arrayContains: currentUserId)
        .snapshots()
        .asyncMap((snapshot) async {
      List<Contact> friends = [];
      for (var doc in snapshot.docs) {
        List<dynamic> userIds = doc.data()['users'];
        String friendId = userIds.firstWhere((id) => id != currentUserId);
        
        final userDoc = await _firestore.collection('users').doc(friendId).get();
        if (userDoc.exists) {
          friends.add(_contactFromDoc(userDoc));
        }
      }
      return friends;
    });
  }

  // Accept friend request and create friendship
  Future<void> acceptFriendRequest(String requestId, String fromUserId) async {
    final myId = currentUserId;
    if (myId == null) return;

    final friendshipId = myId.compareTo(fromUserId) < 0 
        ? '${myId}_$fromUserId' 
        : '${fromUserId}_$myId';

    await _firestore.runTransaction((transaction) async {
      // 1. Update request status
      transaction.update(_firestore.collection('friendRequests').doc(requestId), {
        'status': 'accepted',
      });

      // 2. Create friendship record
      transaction.set(_firestore.collection('friendships').doc(friendshipId), {
        'users': [myId, fromUserId],
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  Contact _contactFromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Contact(
      id: doc.id,
      name: _displayNameFromUser(data),
      phoneNumber: data['phoneNumber'] ?? '',
      avatarUrl: data['avatarUrl'],
      isOnline: data['isOnline'] ?? false,
      lastSeen: 'Ngoại tuyến', // Should be formatted from data['lastSeen']
    );
  }
}
