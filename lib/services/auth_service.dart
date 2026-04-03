import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_client.dart';
import '../models/user.dart';

/// Authentication Service completely updated to use Firebase
class AuthService {
  final firebase_auth.FirebaseAuth _firebaseAuth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  // Standard initialization for Web requires clientId. 
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '332094720906-4bn299ff7t05hrhqgmf08k4qvq242fg3.apps.googleusercontent.com',
  );

  User? _currentUser;
  
  User? get currentUser => _currentUser;

  // Initialize and get the current user if already logged in
  Future<void> initialize() async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      String username = user.email ?? '';
      if (doc.exists) {
        username = doc.data()?['username'] ?? username;
      }
      _currentUser = User(
        username: username,
        email: user.email ?? '',
        password: '',
        totpSecret: '',
      );
      await _updateFCMToken(user.uid);
    }
  }

  Future<void> _updateFCMToken(String uid) async {
    try {
      await _messaging.requestPermission();
      String? token = await _messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(uid).set({
          'fcmToken': token,
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }

  /// Login with email and password
  Future<LoginResult> login(String usernameOrEmail, String password) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: usernameOrEmail,
        password: password,
      );
      
      if (credential.user != null) {
        final doc = await _firestore.collection('users').doc(credential.user!.uid).get();
        String username = usernameOrEmail;
        if (doc.exists) {
           username = doc.data()?['username'] ?? usernameOrEmail;
        }

        _currentUser = User(
          username: username,
          email: credential.user!.email ?? '',
          password: '',
          totpSecret: '',
        );

        await _updateFCMToken(credential.user!.uid);

        return LoginResult(
          success: true,
          message: 'Đăng nhập thành công',
          requiresTOTP: false, 
        );
      }
      return LoginResult(success: false, message: 'Đăng nhập thất bại');
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return LoginResult(success: false, message: 'Sai email hoặc mật khẩu');
      }
      return LoginResult(success: false, message: e.message ?? 'Lỗi đăng nhập');
    } catch (e) {
      return LoginResult(success: false, message: 'Lỗi kết nối');
    }
  }

  /// Google Sign In
  Future<LoginResult> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        return LoginResult(success: false, message: 'Đăng nhập Google bị hủy');
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final firebase_auth.AuthCredential credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final firebase_auth.UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);

      if (userCredential.user != null) {
        final user = userCredential.user!;
        
        // Save or update user info in Firestore
        await _firestore.collection('users').doc(user.uid).set({
          'username': user.displayName ?? 'Google User',
          'email': user.email,
          'avatarUrl': user.photoURL,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await _updateFCMToken(user.uid);

        _currentUser = User(
          username: user.displayName ?? 'Google User',
          email: user.email ?? '',
          password: '',
          totpSecret: '', 
        );

        return LoginResult(success: true, message: 'Đăng nhập Google thành công');
      }
      return LoginResult(success: false, message: 'Đăng nhập Google thất bại');
    } catch (e) {
      debugPrint('Google Sign In Error: $e');
      return LoginResult(success: false, message: 'Lỗi đăng nhập Google: $e');
    }
  }

  /// Verify TOTP code (Disabled in Firebase transition)
  Future<LoginResult> verifyTOTP(String code) async {
    return LoginResult(success: false, message: 'TOTP không còn được hỗ trợ');
  }

  /// Register new user with Firebase
  Future<RegisterResult> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        // Save additional user info to Firestore
        await _firestore.collection('users').doc(credential.user!.uid).set({
          'username': username,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await _updateFCMToken(credential.user!.uid);

        return RegisterResult(
          success: true,
          message: 'Đăng ký thành công',
          totpSecret: null,
        );
      }
      return RegisterResult(success: false, message: 'Đăng ký thất bại');
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return RegisterResult(success: false, message: 'Email đã được sử dụng');
      }
      return RegisterResult(success: false, message: e.message ?? 'Lỗi đăng ký');
    } catch (e) {
      return RegisterResult(success: false, message: 'Lỗi kết nối');
    }
  }

  /// Request password reset via Firebase email
  Future<ResetResult> requestPasswordReset(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      return ResetResult(success: true, message: 'Đã gửi link khôi phục qua email');
    } catch (e) {
      return ResetResult(success: false, message: 'Lỗi khi gửi email');
    }
  }

  /// Logout
  void logout() async {
    if (_firebaseAuth.currentUser != null) {
      await _firestore.collection('users').doc(_firebaseAuth.currentUser!.uid).set({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
    _currentUser = null;
    ApiClient().clearToken();
  }

  /// Update Profile
  Future<bool> updateProfile(User updatedUser) async {
    _currentUser = updatedUser;
    if (_firebaseAuth.currentUser != null) {
      try {
        await _firestore.collection('users').doc(_firebaseAuth.currentUser!.uid).update({
          'fullName': updatedUser.fullName,
          'phoneNumber': updatedUser.phoneNumber,
          'username': updatedUser.username,
        });
        return true;
      } catch (e) {
        debugPrint('Error updating profile: $e');
      }
    }
    return false;
  }
}

class LoginResult {
  final bool success;
  final String message;
  final bool requiresTOTP;

  LoginResult({
    required this.success,
    required this.message,
    this.requiresTOTP = false,
  });
}

class RegisterResult {
  final bool success;
  final String message;
  final String? totpSecret;

  RegisterResult({
    required this.success,
    required this.message,
    this.totpSecret,
  });
}

class ResetResult {
  final bool success;
  final String message;

  ResetResult({required this.success, required this.message});
}
