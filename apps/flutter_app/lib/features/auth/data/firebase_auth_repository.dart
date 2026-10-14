import 'package:firebase_auth/firebase_auth.dart';

import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);
  final FirebaseAuth _auth;

  @override
  Stream<AuthUser?> watchSession() => _auth.userChanges().map(
    (user) => user == null
        ? null
        : AuthUser(
            uid: user.uid,
            email: user.email,
            emailVerified: user.emailVerified,
          ),
  );

  @override
  Future<void> signIn({required String email, required String password}) =>
      _translate(() async {
        await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      });

  @override
  Future<void> register({required String email, required String password}) =>
      _translate(() async {
        await _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        // Verification is a separate action: its failure must not imply signup failed.
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _translate(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> sendVerification() => _translate(() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure('Sign in before requesting verification.');
    }
    await user.sendEmailVerification();
  });

  @override
  Future<void> signOut() => _translate(_auth.signOut);

  Future<void> _translate(Future<void> Function() operation) async {
    try {
      await operation();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(messageForCode(error.code));
    }
  }

  static String messageForCode(String code) => switch (code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'Check your email and password and try again.',
    'email-already-in-use' => 'An account already uses this email. Try signing in or resetting your password.',
    'invalid-email' => 'Enter a valid email address.',
    'weak-password' =>
      'Choose a stronger password that meets the account policy.',
    'too-many-requests' =>
      'Too many attempts. Please wait before trying again.',
    'network-request-failed' => 'Check your connection and try again.',
    'user-disabled' => 'This account is unavailable. Contact support.',
    'operation-not-allowed' =>
      'Email sign-in is not enabled yet. Please try later.',
    _ =>
      'The account service could not complete this request. Please try again.',
  };
}
