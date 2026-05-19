import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthProvider extends ChangeNotifier {
  User? user;
  String? role;
  bool isLoading = true;

  StreamSubscription<User?>? _authSubscription;

  AuthProvider() {
    _init();
  }

  // ─── Init ────────────────────────────────────────────────────────────────────

  void _init() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _onAuthStateChanged,
      onError: (Object error) {
        debugPrint('[AuthProvider] authStateChanges error: $error');
        isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      // ── Logged out ──────────────────────────────────────────────────────────
      user = null;
      role = null;
      isLoading = false;
      notifyListeners();
      return;
    }

    // ── Logged in ─────────────────────────────────────────────────────────────
    user = firebaseUser;
    isLoading = true;
    notifyListeners();

    await _fetchRole(firebaseUser.uid);

    isLoading = false;
    notifyListeners();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> _fetchRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      role = doc.data()?['role'] as String?;
    } catch (e) {
      debugPrint('[AuthProvider] Failed to fetch role for $uid: $e');
      role = null;
    }
  }

  // ─── Public Methods ───────────────────────────────────────────────────────────

  /// Signs the current user out. Auth state listener handles clearing fields.
  Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[AuthProvider] logout error: $e');
      rethrow;
    }
  }

  /// Re-reads the role from Firestore for the currently signed-in user.
  Future<void> refreshRole() async {
    final uid = user?.uid;
    if (uid == null) return;

    isLoading = true;
    notifyListeners();

    await _fetchRole(uid);

    isLoading = false;
    notifyListeners();
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}