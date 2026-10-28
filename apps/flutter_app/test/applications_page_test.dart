import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';
import 'package:smarthire/features/applications/domain/application.dart';

import 'auth_state_test.dart' show TestAuthRepository;
import 'application_test_fixtures.dart';

const applicationActor = AuthUser(
  uid: 'one',
  email: 'fixture@example.invalid',
  emailVerified: true,
);
void main() {
  testWidgets(
    'terminal history removal requires explicit confirmation and clears snapshots',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = ApplicationsFake()
        ..items = [
          JobApplication(applicationJson(status: 'withdrawn', revision: 2)),
        ];
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/applications',
          applicationsRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(applicationActor);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fixture role'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove application history'));
      await tester.tap(find.text('Remove application history'));
      await tester.pumpAndSettle();
      expect(repo.items, isNotEmpty);
      await tester.tap(find.text('Remove application'));
      await tester.pumpAndSettle();
      expect(repo.items, isEmpty);
      expect(find.text('Fixture role'), findsNothing);
      expect(find.text('Application history removed.'), findsOneWidget);
    },
  );
  for (final width in [360.0, 1440.0]) {
    testWidgets('explicit match review and application consent at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = ApplicationsFake();
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/apply/$applicationJobId',
          applicationsRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(applicationActor);
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('Resume ${confirmedResume().id.substring(0, 8)}'),
      );
      await tester.pump();
      await tester.tap(find.text('Review skill match'));
      await tester.pumpAndSettle();
      expect(repo.matches, 1);
      expect(repo.submissions, 0);
      expect(find.text('50.00% required skill coverage'), findsOneWidget);
      await tester.ensureVisible(find.text('Apply with this resume'));
      await tester.tap(find.text('Apply with this resume'));
      await tester.pumpAndSettle();
      expect(repo.submissions, 0);
      expect(find.text('Submit application?'), findsOneWidget);
      await tester.tap(find.text('Submit application'));
      await tester.pumpAndSettle();
      expect(repo.submissions, 1);
      expect(find.textContaining('Application submitted.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('withdrawal is confirmed and stale actions require refresh', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    final repo = ApplicationsFake()
      ..items = [JobApplication(applicationJson())]
      ..stale = true;
    await tester.pumpWidget(
      SmartHireApp(
        authRepository: auth,
        initialRoute: '/applications',
        applicationsRepositoryFactory: (_) => repo,
      ),
    );
    await tester.pump();
    auth.sessions.add(applicationActor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixture role'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Withdraw'));
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    expect(repo.changes, 0);
    await tester.tap(find.text('Confirm decision'));
    await tester.pumpAndSettle();
    expect(repo.changes, 1);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Withdraw'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Withdraw'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('recruiter rejection needs reason and explicit decision', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    final repo = ApplicationsFake()
      ..items = [JobApplication(applicationJson())];
    await tester.pumpWidget(
      SmartHireApp(
        authRepository: auth,
        initialRoute: '/recruiter/applications',
        applicationsRepositoryFactory: (_) => repo,
      ),
    );
    await tester.pump();
    auth.sessions.add(applicationActor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixture role'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reject with reason'));
    await tester.tap(find.text('Reject with reason'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm decision'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byType(TextField),
      'Required experience not demonstrated',
    );
    await tester.pump();
    await tester.tap(find.text('Confirm decision'));
    await tester.pumpAndSettle();
    expect(repo.changes, 1);
    expect(find.text('Fixture company · rejected'), findsOneWidget);
  });
  testWidgets(
    'late matching cannot restore private data after account switch',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      final repo = ApplicationsFake()..pending = Completer<ApplicationMatch>();
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/apply/$applicationJobId',
          applicationsRepositoryFactory: (_) => repo,
        ),
      );
      await tester.pump();
      auth.sessions.add(applicationActor);
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('Resume ${confirmedResume().id.substring(0, 8)}'),
      );
      await tester.pump();
      await tester.tap(find.text('Review skill match'));
      await tester.pump();
      auth.sessions.add(null);
      await tester.pumpAndSettle();
      repo.pending!.complete(ApplicationMatch(matchJson()));
      await tester.pumpAndSettle();
      expect(repo.closed, isTrue);
      expect(find.text('50.00% required skill coverage'), findsNothing);
      expect(find.text('Apply with this resume'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
