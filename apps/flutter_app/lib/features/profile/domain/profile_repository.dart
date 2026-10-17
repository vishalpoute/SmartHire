import 'profile.dart';

/// Bound to the current authenticated session. Implementations must not accept
/// a caller-selected owner or retain data after that session ends.
abstract interface class ProfileRepository {
  Future<SavedProfile?> load();
  Future<SavedProfile> save(ProfileDraft draft);
}
