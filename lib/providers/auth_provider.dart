import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthProvider extends ChangeNotifier {
  // ── Private fields ────────────────────────────────────────────────────────────
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  String? _role;
  bool _isLoading = true;

  StreamSubscription<User?>? _authSubscription;

  // ── Public getters ────────────────────────────────────────────────────────────
  User? get user => _user;
  String? get role => _role;
  bool get isLoading => _isLoading;

  // ── Constructor ───────────────────────────────────────────────────────────────
  AuthProvider() {
    _init();
  }

  // ── Initialization ────────────────────────────────────────────────────────────
  void _init() {
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      // Logged out
      _user = null;
      _role = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Logged in — fetch role from Firestore
    _isLoading = true;
    notifyListeners();

    _user = firebaseUser;
    await _fetchRole(firebaseUser.uid);

    _isLoading = false;
    notifyListeners();
  }

  // ── Internal role fetch ───────────────────────────────────────────────────────
  Future<void> _fetchRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        _role = doc.data()?['role'] as String?;
      } else {
        // Document doesn't exist yet (e.g. mid-registration race condition)
        _role = null;
      }
    } catch (e) {
      debugPrint('AuthProvider: failed to fetch role for $uid — $e');
      _role = null;
    }
  }

  // ── Public methods ────────────────────────────────────────────────────────────

  /// Signs the current user out and clears local state.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('AuthProvider: sign-out error — $e');
    }
    // _onAuthStateChanged(null) will fire automatically and clear state.
  }

  /// Re-reads users/{uid}.role from Firestore without re-authenticating.
  /// Call this after registration or after an admin changes a user's role.
  Future<void> refreshRole() async {
    final uid = _user?.uid;
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();

    await _fetchRole(uid);

    _isLoading = false;
    notifyListeners();
  }

  // ── Dispose ───────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
