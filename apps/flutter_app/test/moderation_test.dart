import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';
import 'package:smarthire/features/applications/domain/application.dart';
import 'package:smarthire/features/profile/data/api_profile_repository.dart';
import 'package:smarthire/features/moderation/data/api_moderation_repository.dart';
import 'package:smarthire/features/moderation/domain/moderation.dart';

import 'applications_repository_test.dart' show ApplicationAdapter;
import 'auth_state_test.dart' show TestAuthRepository;

Map<String, dynamic> moderationJson([String status = 'published']) => {
  'id': 'a' * 32,
  'title': 'Fixture listing',
  'description': 'Fixture description',
  'status': status,
  'version': 2,
};
Map<String, dynamic> auditJson() => {
  'id': 'b' * 32,
  'action': 'job.suspend',
  'actor_uid': 'fixture-admin',
  'reason': 'Fixture reason',
  'created_at': '2026-10-28T00:00:00Z',
  'job_id': 'a' * 32,
};

class ModerationFake implements ModerationRepository {
  int changes = 0;
  String? reason;
  bool denied = false, stale = false, closed = false;
  Completer<ModerationPageData<ModerationJob>>? pending;
  @override
  Future<ModerationPageData<ModerationJob>> jobs(
    String status, {
    String? cursor,
  }) async {
    if (denied) {
      throw const ApplicationFailure(
        'Administrator access required.',
        accessDenied: true,
      );
    }
    return await (pending?.future ??
        Future.value(
          ModerationPageData([ModerationJob(moderationJson(status))], null),
        ));
  }

  @override
  Future<ModerationPageData<ModerationAudit>> audits({String? cursor}) async =>
      ModerationPageData([ModerationAudit(auditJson())], null);
  @override
  Future<void> moderate(ModerationJob job, String reason) async {
    changes++;
    this.reason = reason;
    if (stale) {
      throw const ApplicationFailure(
        'Job changed. Refresh.',
        reloadRequired: true,
      );
    }
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  test(
    'admin repository pins expected version and validates receipts',
    () async {
      final adapter = ApplicationAdapter()
        ..overrideBody = {
          'items': [moderationJson()],
          'next_cursor': null,
        };
      final repository = ApiModerationRepository(
        origin: Uri.https('api.example.com'),
        ownerUid: 'one',
        currentUid: () => 'one',
        session: () async =>
            const ProfileSession(uid: 'one', token: 'fixture', verified: true),
        adapter: adapter,
      );
      addTearDown(repository.close);
      final job = (await repository.jobs('published')).items.single;
      adapter.overrideBody = {
        'id': job.id,
        'status': 'suspended',
        'version': 3,
      };
      await repository.moderate(job, 'Fixture reason');
      expect(adapter.requests.last.data, {
        'expected_version': 2,
        'action': 'suspend',
        'reason': 'Fixture reason',
      });
      adapter.overrideBody = {
        'id': job.id,
        'status': 'published',
        'version': 3,
      };
      await expectLater(
        repository.moderate(job, 'Fixture reason'),
        throwsA(isA<ApplicationFailure>()),
      );
      adapter.overrideBody = {
        'items': [moderationJson('suspended')],
        'next_cursor': null,
      };
      await expectLater(
        repository.jobs('published'),
        throwsA(isA<ApplicationFailure>()),
      );
      adapter.overrideBody = {
        'items': [auditJson()],
        'next_cursor': null,
      };
      expect((await repository.audits()).items.single.action, 'job.suspend');
    },
  );
  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'moderation needs a reason and explicit confirmation at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = TestAuthRepository();
        addTearDown(auth.sessions.close);
        final repo = ModerationFake();
        await tester.pumpWidget(
          SmartHireApp(
            authRepository: auth,
            initialRoute: '/admin/moderation',
            moderationRepositoryFactory: (_) => repo,
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
        await tester.tap(find.text('Fixture listing'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Suspend listing'));
        await tester.pumpAndSettle();
        expect(repo.changes, 0);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm moderation'),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byType(TextField),
          'Fixture moderation reason',
        );
        await tester.pump();
        await tester.tap(find.text('Confirm moderation'));
        await tester.pumpAndSettle();
        expect(repo.changes, 1);
        expect(repo.reason, 'Fixture moderation reason');
        expect(find.text('Fixture listing'), findsNothing);
        await tester.tap(find.text('Audit events'));
        await tester.pumpAndSettle();
        expect(find.text('job.suspend'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'permission loss clears admin data and late response cannot survive signout',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = ModerationFake();
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/admin/moderation',
          moderationRepositoryFactory: (_) => repo,
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
      expect(find.text('Fixture listing'), findsOneWidget);
      repo.denied = true;
      await tester.tap(find.text('Refresh moderation'));
      await tester.pumpAndSettle();
      expect(find.text('Fixture listing'), findsNothing);
      repo.denied = false;
      repo.pending = Completer<ModerationPageData<ModerationJob>>();
      await tester.tap(find.text('Refresh moderation'));
      await tester.pump();
      auth.sessions.add(null);
      await tester.pumpAndSettle();
      repo.pending!.complete(
        ModerationPageData([ModerationJob(moderationJson())], null),
      );
      await tester.pumpAndSettle();
      expect(repo.closed, isTrue);
      expect(find.text('Fixture listing'), findsNothing);
    },
  );
}
