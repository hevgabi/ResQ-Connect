import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  String? _role;
  bool _isLoading = true;
  bool _isAccountDisabled = false;
  bool _isPending = false;
  bool _isUnverified = false;
  String? _unverifiedEmail;

  StreamSubscription<User?>? _authSubscription;

  bool _isNeedsProfileCompletion = false;
  bool get isNeedsProfileCompletion => _isNeedsProfileCompletion;

  static const _validRoles = {'citizen', 'rescuer', 'moderator', 'admin'};

  User? get user => _user;
  String? get role => _role;
  bool get isLoading => _isLoading;
  bool get isAccountDisabled => _isAccountDisabled;
  bool get isPending => _isPending;
  bool get isUnverified => _isUnverified;
  String? get unverifiedEmail => _unverifiedEmail;

  AuthProvider() {
    _init();
  }

  void _init() {
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      _user = null;
      _role = null;
      _isLoading = false;
      _isAccountDisabled = false;
      _isPending = false;
      _isUnverified = false;
      _isNeedsProfileCompletion = false;
      _unverifiedEmail = null;
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

  Future<void> _fetchRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) {
        debugPrint('AuthProvider: no user doc found for $uid');
        _role = null;
        _isPending = false;
        _isUnverified = false;
        _isNeedsProfileCompletion = true;
        return;
      }

      final data = doc.data()!;
      final approvalStatus = data['approval_status'] as String? ?? 'approved';

      // ── Unverified: OTP not yet confirmed ─────────────────────────────────
      // Sign them out so they can't access app, but keep email for OTP screen
      if (approvalStatus == 'unverified') {
        debugPrint('AuthProvider: account $uid is unverified — signing out');
        _isUnverified = true;
        _unverifiedEmail = data['email'] as String? ?? _user?.email ?? '';
        _isPending = false;
        _isAccountDisabled = false;
        _role = null;
        await _auth
            .signOut(); // sign out silently — main.dart shows _UnverifiedScreen
        return;
      }

      // ── Pending: email verified, waiting for admin ─────────────────────────
      if (approvalStatus == 'pending') {
        debugPrint('AuthProvider: account $uid is pending approval');
        _isPending = true;
        _isUnverified = false;
        _isAccountDisabled = false;
        _role = null;
        return;
      }

      // ── Rejected ───────────────────────────────────────────────────────────
      if (approvalStatus == 'rejected') {
        debugPrint('AuthProvider: account $uid was rejected');
        _isAccountDisabled = true;
        _isPending = false;
        _isUnverified = false;
        _role = null;
        await _auth.signOut();
        return;
      }

      // ── Disabled ───────────────────────────────────────────────────────────
      final isActive = data['is_active'] as bool? ?? true;
      if (!isActive) {
        debugPrint('AuthProvider: account $uid is disabled');
        _isAccountDisabled = true;
        _isPending = false;
        _isUnverified = false;
        _role = null;
        await _auth.signOut();
        return;
      }

      // ── Invalid role ───────────────────────────────────────────────────────
      final fetchedRole = data['role'] as String?;
      if (fetchedRole == null || !_validRoles.contains(fetchedRole)) {
        debugPrint('AuthProvider: invalid role "$fetchedRole" for $uid');
        _role = null;
        _isPending = false;
        _isUnverified = false;
        await _auth.signOut();
        return;
      }

      // ── All good ───────────────────────────────────────────────────────────
      _role = fetchedRole;
      _isPending = false;
      _isUnverified = false;
      _isAccountDisabled = false;
      _unverifiedEmail = null;
      debugPrint('AuthProvider: uid=$uid role=$_role verified ✓');
    } catch (e) {
      debugPrint('AuthProvider: failed to fetch role for $uid — $e');
      _role = null;
    }
  }

  Future<void> logout() async {
    try {
      _role = null;
      _user = null;
      _isPending = false;
      _isUnverified = false;
      _unverifiedEmail = null;
      notifyListeners();
      await _auth.signOut();
    } catch (e) {
      debugPrint('AuthProvider: sign-out error — $e');
    }
  }

  Future<void> refreshRole() async {
    final uid = _user?.uid;
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();

    await _fetchRole(uid);

    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
