import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';
import 'package:smarthire/features/resumes/domain/resume.dart';

import 'auth_state_test.dart' show TestAuthRepository;
import 'resume_test_fixtures.dart';

const actor = AuthUser(
  uid: 'one',
  email: 'one@example.com',
  emailVerified: true,
);

void main() {
  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'resume upload waits for extraction and explicit skill confirmation at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = TestAuthRepository();
        addTearDown(auth.sessions.close);
        final repo = ResumesFake();
        await tester.pumpWidget(
          SmartHireApp(
            authRepository: auth,
            initialRoute: '/resumes',
            resumeRepositoryFactory: (_) => repo,
            resumePicker: () async => fixtureResume(),
          ),
        );
        await tester.pump();
        auth.sessions.add(actor);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Upload private resume'));
        await tester.pumpAndSettle();
        expect(repo.nonces.length, 1);
        expect(repo.confirmations, 0);
        expect(find.text('Queued for text extraction'), findsOneWidget);
        expect(find.text('Confirm resume skills'), findsNothing);
        repo.items = [fixtureRecord(id: repo.items.single.id)];
        await tester.tap(find.text('Refresh resumes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review resume'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Flutter, Python');
        await tester.ensureVisible(find.text('Confirm resume skills'));
        await tester.tap(find.text('Confirm resume skills'));
        await tester.pumpAndSettle();
        expect(repo.confirmations, 1);
        expect(
          find.textContaining('Skills confirmed. These are'),
          findsOneWidget,
        );
        auth.sessions.add(null);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Selected: fixture.pdf'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('private upload retry keeps its original idempotency key', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    final repo = ResumesFake()..failUpload = true;
    await tester.pumpWidget(
      SmartHireApp(
        authRepository: auth,
        initialRoute: '/resumes',
        resumeRepositoryFactory: (_) => repo,
        resumePicker: () async => fixtureResume(),
      ),
    );
    await tester.pump();
    auth.sessions.add(actor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload private resume'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: fixture.pdf'), findsOneWidget);
    repo.failUpload = false;
    await tester.tap(find.text('Retry private upload'));
    await tester.pumpAndSettle();
    expect(repo.nonces.length, 2);
    expect(repo.nonces.toSet().length, 1);
  });
  testWidgets(
    'removal requires confirmation and pending cleanup is reported honestly',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = ResumesFake()
        ..items = [fixtureRecord()]
        ..deletionPending = true;
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/resumes',
          resumeRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(actor);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove private resume'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      await tester.tap(find.text('Remove private resume'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove resume'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(find.text('Private resume removed.'), findsNothing);
      expect(find.textContaining('Removal is pending'), findsOneWidget);
    },
  );
  testWidgets(
    'stale skill confirmation disables writes until an explicit refresh',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = ResumesFake()
        ..items = [fixtureRecord()]
        ..staleConfirm = true;
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/resumes',
          resumeRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(actor);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review resume'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm resume skills'));
      await tester.tap(find.text('Confirm resume skills'));
      await tester.pumpAndSettle();
      expect(repo.confirmations, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm resume skills'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Refresh resumes'));
      await tester.tap(find.text('Refresh resumes'));
      await tester.pumpAndSettle();
      expect(repo.reads, 2);
    },
  );
  testWidgets('unscored files do not expose a confirmation action', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    final repo = ResumesFake()
      ..items = [fixtureRecord(status: 'unscored', errorCode: 'empty_text')];
    await tester.pumpWidget(
      SmartHireApp(
        authRepository: auth,
        initialRoute: '/resumes',
        resumeRepositoryFactory: (_) => repo,
      ),
    );
    await tester.pump();
    auth.sessions.add(actor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review resume'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No readable text'), findsOneWidget);
    expect(find.text('Confirm resume skills'), findsNothing);
    expect(find.text('Retry processing'), findsNothing);
  });
  testWidgets(
    'late upload and progress callbacks cannot restore a previous account resume',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final previous = ResumesFake()..pendingUpload = Completer<ResumeRecord>();
      final current = ResumesFake();
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/resumes',
          resumeRepositoryFactory: (uid) => uid == 'one' ? previous : current,
          resumePicker: () async => fixtureResume(),
        ),
      );
      await tester.pump();
      auth.sessions.add(actor);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload private resume'));
      await tester.pump();
      auth.sessions.add(
        const AuthUser(
          uid: 'two',
          email: 'two@example.com',
          emailVerified: true,
        ),
      );
      await tester.pumpAndSettle();
      previous.progress?.call(4, 4);
      previous.pendingUpload!.complete(fixtureRecord());
      await tester.pumpAndSettle();
      expect(find.text('Selected: fixture.pdf'), findsNothing);
      expect(find.text('Confirm your skills'), findsNothing);
      expect(find.text('No private resumes yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unverified accounts cannot create repositories or open the picker',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      var creates = 0, picks = 0;
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/resumes',
          resumeRepositoryFactory: (_) {
            creates++;
            return ResumesFake();
          },
          resumePicker: () async {
            picks++;
            return fixtureResume();
          },
        ),
      );
      await tester.pump();
      auth.sessions.add(null);
      await tester.pumpAndSettle();
      expect(creates, 0);
      expect(picks, 0);
      auth.sessions.add(
        const AuthUser(
          uid: 'one',
          email: 'one@example.com',
          emailVerified: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(creates, 0);
      expect(picks, 0);
      expect(
        find.text('Verify your email before uploading a resume.'),
        findsOneWidget,
      );
    },
  );
}
