import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/profile/domain/profile.dart';
import 'package:smarthire/features/profile/domain/profile_repository.dart';
import 'package:smarthire/features/profile/presentation/profile_cubit.dart';

class FakeProfiles implements ProfileRepository {
  Completer<SavedProfile?> loading = Completer();
  Completer<SavedProfile> saving = Completer();
  int writes = 0;
  @override
  Future<SavedProfile?> load() => loading.future;
  @override
  Future<SavedProfile> save(ProfileDraft draft) {
    writes++;
    return saving.future;
  }
}

SavedProfile saved() => SavedProfile(
  uid: 'owner',
  updatedAt: DateTime.utc(2026),
  draft: ProfileDraft(displayName: 'Ada'),
);

void main() {
  test(
    'load distinguishes absent profile and existing normalized response',
    () async {
      final repo = FakeProfiles();
      final cubit = ProfileCubit(repo);
      final request = cubit.load();
      expect(cubit.state.status, ProfileStatus.loading);
      repo.loading.complete(null);
      await request;
      expect(cubit.state.status, ProfileStatus.ready);
      expect(cubit.state.draft.displayName, '');
      repo.loading = Completer();
      final next = cubit.load();
      repo.loading.complete(saved());
      await next;
      expect(cubit.state.draft.displayName, 'Ada');
      await cubit.close();
    },
  );
  test('invalid form never reaches repository', () async {
    final repo = FakeProfiles();
    final cubit = ProfileCubit(repo);
    await cubit.save();
    expect(repo.writes, 0);
    expect(cubit.state.errors, contains('display_name'));
    await cubit.close();
  });
  test(
    'failed save preserves edits, hides diagnostics and supports retry',
    () async {
      final repo = FakeProfiles();
      final cubit = ProfileCubit(repo);
      final draft = ProfileDraft(displayName: 'Ada');
      cubit.edit(draft);
      final request = cubit.save();
      await cubit.save();
      expect(repo.writes, 1);
      repo.saving.completeError(Exception('secret transport diagnostics'));
      await request;
      expect(cubit.state.status, ProfileStatus.failure);
      expect(cubit.state.draft, same(draft));
      expect(cubit.state.message, isNot(contains('secret')));
      repo.saving = Completer();
      final retry = cubit.save();
      repo.saving.complete(saved());
      await retry;
      expect(cubit.state.status, ProfileStatus.saved);
      await cubit.close();
    },
  );
  test('reset invalidates a late load and clears private fields', () async {
    final repo = FakeProfiles();
    final cubit = ProfileCubit(repo);
    final request = cubit.load();
    cubit.reset();
    repo.loading.complete(saved());
    await request;
    expect(cubit.state.status, ProfileStatus.initial);
    expect(cubit.state.draft.displayName, '');
    await cubit.close();
  });
  test('closed controller ignores a late save response', () async {
    final repo = FakeProfiles();
    final cubit = ProfileCubit(repo);
    cubit.edit(ProfileDraft(displayName: 'Ada'));
    final request = cubit.save();
    await cubit.close();
    repo.saving.complete(saved());
    await request;
    expect(cubit.isClosed, isTrue);
  });
  test(
    'failed load preserves draft and reset invalidates a late save',
    () async {
      final repo = FakeProfiles();
      final cubit = ProfileCubit(repo);
      final draft = ProfileDraft(displayName: 'Ada');
      cubit.edit(draft);
      final loading = cubit.load();
      repo.loading.completeError(Exception('private'));
      await loading;
      expect(cubit.state.draft, same(draft));
      expect(cubit.state.status, ProfileStatus.failure);
      final saving = cubit.save();
      cubit.reset();
      repo.saving.complete(saved());
      await saving;
      expect(cubit.state.draft.displayName, '');
      await cubit.close();
    },
  );
}
