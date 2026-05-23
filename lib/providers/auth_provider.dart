import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthProvider extends ChangeNotifier {
  // ── Private fields ────────────────────────────────────────────────────────
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  String? _role;
  bool _isLoading = true;
  bool _isAccountDisabled = false;

  StreamSubscription<User?>? _authSubscription;

  // ── Valid roles whitelist ─────────────────────────────────────────────────
  static const _validRoles = {'citizen', 'rescuer', 'moderator', 'admin'};

  // ── Public getters ────────────────────────────────────────────────────────
  User? get user => _user;
  String? get role => _role;
  bool get isLoading => _isLoading;
  bool get isAccountDisabled => _isAccountDisabled;

  // ── Constructor ───────────────────────────────────────────────────────────
  AuthProvider() {
    _init();
  }

  // ── Initialization ────────────────────────────────────────────────────────
  void _init() {
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      _user = null;
      _role = null;
      _isLoading = false;
      _isAccountDisabled = false;
      notifyListeners();
      return;
    }

    if (_user == null) {
      _isLoading = true;
      notifyListeners();
    }

    _user = firebaseUser;
    await _fetchRole(firebaseUser.uid);

    _isLoading = false;
    notifyListeners();
  }

  // ── Internal role fetch ───────────────────────────────────────────────────
  Future<void> _fetchRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) {
        // No Firestore doc — could be mid-registration, set null and retry
        debugPrint('AuthProvider: no user doc found for $uid');
        _role = null;
        return;
      }

      final data = doc.data()!;

      // Security check: is account active?
      final isActive = data['is_active'] as bool? ?? true;
      if (!isActive) {
        debugPrint('AuthProvider: account $uid is disabled — forcing logout');
        _isAccountDisabled = true;
        _role = null;
        await _auth.signOut();
        return;
      }

      // Security check: is role valid?
      final fetchedRole = data['role'] as String?;
      if (fetchedRole == null || !_validRoles.contains(fetchedRole)) {
        debugPrint(
          'AuthProvider: invalid role "$fetchedRole" for $uid — forcing logout',
        );
        _role = null;
        await _auth.signOut();
        return;
      }

      _role = fetchedRole;
      _isAccountDisabled = false;
      debugPrint('AuthProvider: uid=$uid role=$_role verified ✓');
    } catch (e) {
      debugPrint('AuthProvider: failed to fetch role for $uid — $e');
      _role = null;
    }
  }

  // ── Public methods ────────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      _role = null;
      _user = null;
      notifyListeners();
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

  // ── Dispose ───────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
