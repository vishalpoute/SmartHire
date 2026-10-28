import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';
import 'package:smarthire/features/applications/domain/application.dart';
import 'package:smarthire/features/profile/data/api_profile_repository.dart';
import 'package:smarthire/features/saved_jobs/data/api_saved_jobs_repository.dart';
import 'package:smarthire/features/saved_jobs/domain/saved_job.dart';

import 'auth_state_test.dart' show TestAuthRepository;
import 'applications_repository_test.dart' show ApplicationAdapter;
import 'application_test_fixtures.dart' show applicationJobId;

Map<String, dynamic> savedJson({bool hidden = false}) => {
  'id': 'b' * 32,
  'job_id': applicationJobId,
  'saved_at': '2026-10-28T00:00:00Z',
  'job': hidden
      ? null
      : {
          'id': applicationJobId,
          'title': 'Saved fixture role',
          'company_name': 'Fixture company',
        },
};

class SavedFake implements SavedJobsRepository {
  List<SavedJob> items = [];
  int saves = 0, removals = 0;
  bool closed = false, denied = false;
  Completer<SavedJobsData>? pending;
  @override
  Future<SavedJobsData> saved({String? cursor}) async {
    if (denied) {
      throw const ApplicationFailure('Permission changed.', accessDenied: true);
    }
    return await (pending?.future ?? Future.value(SavedJobsData(items, null)));
  }

  @override
  Future<SavedJob> save(String jobId) async {
    saves++;
    final value = SavedJob(savedJson());
    items = [value];
    return value;
  }

  @override
  Future<void> remove(String jobId) async {
    removals++;
    items = [];
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  test(
    'saved adapter pins identities and handles hidden rows and safe removals',
    () async {
      final adapter = ApplicationAdapter()
        ..overrideBody = {
          'items': [savedJson(hidden: true)],
          'next_cursor': null,
        };
      String? uid = 'one';
      final repo = ApiSavedJobsRepository(
        origin: Uri.https('api.example.com'),
        ownerUid: 'one',
        currentUid: () => uid,
        session: () async =>
            const ProfileSession(uid: 'one', token: 'fixture', verified: true),
        adapter: adapter,
      );
      addTearDown(repo.close);
      expect((await repo.saved()).items.single.title, isNull);
      adapter.overrideBody = savedJson();
      adapter.status = 201;
      expect((await repo.save(applicationJobId)).jobId, applicationJobId);
      adapter.overrideBody = {'job_id': applicationJobId, 'status': 'removed'};
      adapter.status = 200;
      await repo.remove(applicationJobId);
      expect(adapter.requests.last.method, 'DELETE');
      uid = 'two';
      await expectLater(
        repo.saved(),
        throwsA(
          isA<ApplicationFailure>().having(
            (e) => e.accessDenied,
            'denied',
            true,
          ),
        ),
      );
    },
  );
  test(
    'saved adapter rejects source substitution and duplicate or stalled pages',
    () async {
      final adapter = ApplicationAdapter();
      final repo = ApiSavedJobsRepository(
        origin: Uri.https('api.example.com'),
        ownerUid: 'one',
        currentUid: () => 'one',
        session: () async =>
            const ProfileSession(uid: 'one', token: 'fixture', verified: true),
        adapter: adapter,
      );
      addTearDown(repo.close);
      adapter.status = 201;
      adapter.overrideBody = savedJson()..['job_id'] = 'c' * 32;
      await expectLater(
        repo.save(applicationJobId),
        throwsA(isA<ApplicationFailure>()),
      );
      adapter.status = 200;
      adapter.overrideBody = {
        'items': [savedJson(), savedJson()],
        'next_cursor': null,
      };
      await expectLater(repo.saved(), throwsA(isA<ApplicationFailure>()));
      adapter.overrideBody = {'items': [], 'next_cursor': 'b' * 32};
      await expectLater(
        repo.saved(cursor: 'b' * 32),
        throwsA(isA<ApplicationFailure>()),
      );
    },
  );
  for (final width in [360.0, 1440.0]) {
    testWidgets('save and remove account bookmarks at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = SavedFake();
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/save/$applicationJobId',
          savedJobsRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(
        const AuthUser(
          uid: 'one',
          email: 'fixture@example.invalid',
          emailVerified: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      await tester.tap(find.text('Save this role'));
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(find.text('Saved fixture role'), findsOneWidget);
      await tester.tap(find.text('Remove saved role'));
      await tester.pumpAndSettle();
      expect(repo.removals, 1);
      expect(find.text('No saved roles yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'hidden bookmarks stay removable and denied refresh clears account data',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = SavedFake()..items = [SavedJob(savedJson(hidden: true))];
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/saved-jobs',
          savedJobsRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(
        const AuthUser(
          uid: 'one',
          email: 'fixture@example.invalid',
          emailVerified: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Role no longer available'), findsOneWidget);
      expect(find.text('View saved role'), findsNothing);
      repo.denied = true;
      await tester.tap(find.text('Refresh saved roles'));
      await tester.pumpAndSettle();
      expect(find.text('Role no longer available'), findsNothing);
    },
  );
  testWidgets(
    'late bookmark responses cannot restore signed-out account data',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = SavedFake()..pending = Completer<SavedJobsData>();
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/saved-jobs',
          savedJobsRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(
        const AuthUser(
          uid: 'one',
          email: 'fixture@example.invalid',
          emailVerified: true,
        ),
      );
      await tester.pump();
      auth.sessions.add(null);
      await tester.pumpAndSettle();
      repo.pending!.complete(SavedJobsData([SavedJob(savedJson())], null));
      await tester.pumpAndSettle();
      expect(repo.closed, isTrue);
      expect(find.text('Saved fixture role'), findsNothing);
    },
  );
}
