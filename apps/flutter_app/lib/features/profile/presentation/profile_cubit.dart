import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/profile.dart';
import '../domain/profile_repository.dart';

enum ProfileStatus { initial, loading, ready, saving, saved, failure }

class ProfileState {
  const ProfileState({
    required this.status,
    required this.draft,
    this.message,
    this.errors = const {},
  });
  final ProfileStatus status;
  final ProfileDraft draft;
  final String? message;
  final Map<String, String> errors;
}

/// Create per signed-in session and close on sign-out. No profile is cached.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit(this._repository)
    : super(
        ProfileState(
          status: ProfileStatus.initial,
          draft: ProfileDraft(displayName: ''),
        ),
      );
  final ProfileRepository _repository;
  int _generation = 0;

  void edit(ProfileDraft draft) {
    if (isClosed ||
        state.status == ProfileStatus.loading ||
        state.status == ProfileStatus.saving) {
      return;
    }
    emit(ProfileState(status: ProfileStatus.ready, draft: draft));
  }

  Future<void> load() async {
    if (isClosed ||
        state.status == ProfileStatus.saving ||
        state.status == ProfileStatus.loading) {
      return;
    }
    final generation = ++_generation;
    final draft = state.draft;
    emit(ProfileState(status: ProfileStatus.loading, draft: draft));
    try {
      final profile = await _repository.load();
      if (isClosed || generation != _generation) return;
      emit(
        ProfileState(
          status: ProfileStatus.ready,
          draft: profile?.draft ?? draft,
        ),
      );
    } catch (_) {
      if (isClosed || generation != _generation) return;
      emit(
        ProfileState(
          status: ProfileStatus.failure,
          draft: draft,
          message: 'Unable to load your profile. Please retry.',
        ),
      );
    }
  }

  Future<void> save() async {
    if (isClosed ||
        state.status == ProfileStatus.loading ||
        state.status == ProfileStatus.saving) {
      return;
    }
    final draft = state.draft;
    final errors = draft.validate();
    if (errors.isNotEmpty) {
      emit(
        ProfileState(status: ProfileStatus.ready, draft: draft, errors: errors),
      );
      return;
    }
    final generation = ++_generation;
    emit(ProfileState(status: ProfileStatus.saving, draft: draft));
    try {
      final saved = await _repository.save(draft);
      if (isClosed || generation != _generation) return;
      emit(ProfileState(status: ProfileStatus.saved, draft: saved.draft));
    } catch (_) {
      if (isClosed || generation != _generation) return;
      emit(
        ProfileState(
          status: ProfileStatus.failure,
          draft: draft,
          message: 'Unable to save your profile. Your edits are still here.',
        ),
      );
    }
  }

  /// Clear sensitive form state before replacing or ending a session.
  void reset() {
    if (isClosed) return;
    ++_generation;
    emit(
      ProfileState(
        status: ProfileStatus.initial,
        draft: ProfileDraft(displayName: ''),
      ),
    );
  }
}
