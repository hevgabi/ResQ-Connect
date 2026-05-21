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

    // Logged in — fetch role from Firestore.
    // Only show the loading/splash screen when this is a cold start
    // (no user was previously resolved). This prevents the splash from
    // flashing during a logout attempt that briefly re-triggers the
    // auth state stream before settling on null.
    if (_user == null) {
      _isLoading = true;
      notifyListeners();
    }

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

  /// FIXED: Signs the current user out without triggering the global loading screen.
  /// This prevents the navigation conflict in _RootRouter.
  Future<void> logout() async {
    try {
      // Direkta nang mag-sign out. Ang _onAuthStateChanged(null) ang bahalang mag-clear
      // ng local state at mag-trigger ng auto-navigate papuntang LoginScreen.
      await _auth.signOut();
    } catch (e) {
      debugPrint('AuthProvider: sign-out error — $e');
    }
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
