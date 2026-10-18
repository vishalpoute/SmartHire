import 'package:firebase_auth/firebase_auth.dart';

import 'api_profile_repository.dart';

/// Bind once per signed-in user, then discard with the profile screen.
/// Firebase owns token refresh; no token is persisted or included in logs.
class FirebaseProfileSession {
  FirebaseProfileSession(this._auth, {required this.ownerUid});
  final FirebaseAuth _auth;
  final String ownerUid;

  String? get currentUid => _auth.currentUser?.uid;

  Future<ProfileSession?> read() async {
    try {
      final user = _auth.currentUser;
      if (user == null || ownerUid.isEmpty || user.uid != ownerUid) return null;
      if (!user.emailVerified) {
        throw const ProfileFailure(
          'Verify your email before editing your profile.',
        );
      }
      final token = await user.getIdToken(true);
      final current = _auth.currentUser;
      if (current == null || current.uid != ownerUid) return null;
      if (!current.emailVerified) {
        throw const ProfileFailure(
          'Verify your email before editing your profile.',
        );
      }
      if (token == null || token.isEmpty) return null;
      return ProfileSession(uid: ownerUid, token: token, verified: true);
    } on ProfileFailure {
      rethrow;
    } catch (_) {
      throw const ProfileFailure(
        'Unable to verify your session. Please sign in again.',
      );
    }
  }

  ApiProfileRepository repository(Uri origin) => ApiProfileRepository(
    origin: origin,
    session: read,
    currentUid: () => currentUid,
  );
}
