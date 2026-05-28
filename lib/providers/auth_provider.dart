import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// AuthProvider ang sentro ng auth logic ng buong app.
// Lahat ng screens na nangangailangan ng role o user info
// ay kumukunha dito sa provider, hindi direkta sa FirebaseAuth.
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

  // Flag para pigilin ang authStateChanges listener habang ang login screen
  // ay nag-a-asikaso ng sariling Firestore read. Dati nagka-crash ito dahil
  // sabay-sabay silang nagbabasa ng parehong document — fixed na ngayon.
  bool _suppressAuthListener = false;

  // Para sa Google sign-in users na hindi pa nagko-complete ng profile
  bool _isNeedsProfileCompletion = false;
  bool get isNeedsProfileCompletion => _isNeedsProfileCompletion;

  // Tanging valid roles lang ang tinatanggap ng app
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
    // Mag-listen sa auth state changes para reactive ang buong app
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  // Tawagin ito bago mag-manual na signIn para hindi mag-overlap
  // ang listener at ang login screen sa pagbabasa ng Firestore doc
  void suppressNextAuthEvent() {
    _suppressAuthListener = true;
  }

  // I-call ito pagkatapos ng manual sign-in para i-re-enable ang listener
  // at i-fetch agad ang role ng user
  Future<void> resumeAndFetchRole() async {
    _suppressAuthListener = false;
    final current = _auth.currentUser;
    if (current != null) {
      await _onAuthStateChanged(current);
    }
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (_suppressAuthListener) {
      debugPrint('AuthProvider: listener suppressed, skipping');
      return;
    }

    // Nag-sign out o walang naka-login — i-clear ang lahat ng state
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

    // Bago i-fetch ang role, ipakita muna ang loading state
    // pero kung may existing user na, huwag nang mag-flicker
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

      // Walang Firestore doc — posibleng Google user na hindi pa nagco-complete ng profile
      if (!doc.exists) {
        debugPrint('AuthProvider: walang user doc para sa $uid');
        _role = null;
        _isPending = false;
        _isUnverified = false;
        _isNeedsProfileCompletion = true;
        return;
      }

      final data = doc.data()!;
      final approvalStatus = data['approval_status'] as String? ?? 'approved';

      // Hindi pa nakukumpirma ang email — i-sign out at i-redirect sa OTP
      if (approvalStatus == 'unverified') {
        debugPrint('AuthProvider: account $uid ay unverified, nag-sign out');
        _isUnverified = true;
        _unverifiedEmail = data['email'] as String? ?? _user?.email ?? '';
        _isPending = false;
        _isAccountDisabled = false;
        _role = null;
        await _auth.signOut();
        return;
      }

      // Verified na ang email pero hinihintay pa ang admin approval
      if (approvalStatus == 'pending') {
        debugPrint('AuthProvider: account $uid ay pending approval');
        _isPending = true;
        _isUnverified = false;
        _isAccountDisabled = false;
        _role = null;
        return;
      }

      // Na-reject ng admin — i-block at i-sign out
      if (approvalStatus == 'rejected') {
        debugPrint('AuthProvider: account $uid ay na-reject');
        _isAccountDisabled = true;
        _isPending = false;
        _isUnverified = false;
        _role = null;
        await _auth.signOut();
        return;
      }

      // Naka-approve pero manually na-disable ng admin
      final isActive = data['is_active'] as bool? ?? true;
      if (!isActive) {
        debugPrint('AuthProvider: account $uid ay disabled ng admin');
        _isAccountDisabled = true;
        _isPending = false;
        _isUnverified = false;
        _role = null;
        await _auth.signOut();
        return;
      }

      // Validate ang role — kung hindi valid, huwag payagan
      final fetchedRole = data['role'] as String?;
      if (fetchedRole == null || !_validRoles.contains(fetchedRole)) {
        debugPrint('AuthProvider: invalid na role "$fetchedRole" para sa $uid');
        _role = null;
        _isPending = false;
        _isUnverified = false;
        await _auth.signOut();
        return;
      }

      // Lahat okay na — set na ang role at i-clear ang error states
      _role = fetchedRole;
      _isPending = false;
      _isUnverified = false;
      _isAccountDisabled = false;
      _unverifiedEmail = null;
      debugPrint('AuthProvider: uid=$uid role=$_role OK');
    } catch (e) {
      // Hindi namin gustong i-crash ang app kapag may Firestore error
      // kaya i-log na lang at hayaang mag-retry ang caller
      debugPrint('AuthProvider: error sa pag-fetch ng role para sa $uid - $e');
      _role = null;
    }
  }

  Future<void> logout() async {
    try {
      // I-clear muna ang local state bago mag-signOut
      // para hindi mag-flash ang authenticated screens
      _role = null;
      _user = null;
      _isPending = false;
      _isUnverified = false;
      _unverifiedEmail = null;
      notifyListeners();
      await _auth.signOut();
    } catch (e) {
      debugPrint('AuthProvider: error sa sign-out - $e');
    }
  }

  // Para sa cases na kailangan i-refresh ang role ng user, e.g.
  // pagkatapos i-approve ng admin ang account niya
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
