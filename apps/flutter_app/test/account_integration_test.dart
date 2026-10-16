import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';

import 'auth_state_test.dart' show TestAuthRepository;

class UiAuthRepository extends TestAuthRepository {
  @override
  Future<void> signIn({required String email, required String password}) async {
    await super.signIn(email: email, password: password);
    sessions.add(
      const AuthUser(
        uid: 'demo',
        email: 'demo@example.com',
        emailVerified: false,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    await super.signOut();
    sessions.add(null);
  }

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    await super.register(email: email, password: password);
    sessions.add(
      const AuthUser(
        uid: 'demo',
        email: 'demo@example.com',
        emailVerified: false,
      ),
    );
  }

  @override
  Future<void> refreshSession() async {
    await super.refreshSession();
    sessions.add(
      const AuthUser(
        uid: 'demo',
        email: 'demo@example.com',
        emailVerified: true,
      ),
    );
  }
}

void main() {
  testWidgets(
    'Google sign-in works without filling email fields and handles cancellation',
    (tester) async {
      final repo = TestAuthRepository()
        ..failure = const AuthFailure('Google sign-in was cancelled.');
      addTearDown(repo.sessions.close);
      await tester.pumpWidget(
        SmartHireApp(authRepository: repo, initialRoute: '/sign-in'),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('google-sign-in')));
      await tester.tap(find.byKey(const Key('google-sign-in')));
      await tester.pumpAndSettle();
      expect(repo.requests, 1);
      expect(find.text('Google sign-in was cancelled.'), findsOneWidget);
      expect(find.text('Enter your email address'), findsNothing);
    },
  );

  testWidgets('connected signup creates only an unverified email account', (
    tester,
  ) async {
    final repo = UiAuthRepository();
    await tester.pumpWidget(SmartHireApp(authRepository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign in'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('New to SmartHire? Create an account'),
    );
    await tester.tap(find.text('New to SmartHire? Create an account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-name')), findsNothing);
    expect(find.text('Hire people'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('account-email')),
      'demo@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('account-password')),
      'test-password',
    );
    await tester.enterText(
      find.byKey(const Key('account-confirm')),
      'test-password',
    );
    await tester.ensureVisible(find.byKey(const Key('account-submit')));
    await tester.tap(find.byKey(const Key('account-submit')));
    await tester.pumpAndSettle();
    expect(repo.requests, 1);
    expect(find.text('Your account'), findsOneWidget);
    expect(
      find.text('Verify your email before applying for jobs.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await repo.sessions.close();
  });
  testWidgets(
    'connected forms retry errors, disable duplicate submits and show session actions',
    (tester) async {
      final repo = UiAuthRepository()
        ..failure = const AuthFailure('Check your email and password.');
      await tester.pumpWidget(SmartHireApp(authRepository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-email')),
        'demo@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('account-password')),
        'test-password',
      );
      await tester.ensureVisible(find.byKey(const Key('account-submit')));
      await tester.tap(find.byKey(const Key('account-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Check your email and password.'), findsOneWidget);
      repo.failure = null;
      repo.pending = Completer<void>();
      await tester.ensureVisible(find.byKey(const Key('account-submit')));
      await tester.tap(find.byKey(const Key('account-submit')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('account-submit')))
            .onPressed,
        isNull,
      );
      repo.pending!.complete();
      repo.pending = null;
      await tester.pumpAndSettle();
      expect(find.text('Your account'), findsOneWidget);
      await tester.ensureVisible(find.text('Send verification email'));
      await tester.tap(find.text('Send verification email'));
      await tester.pumpAndSettle();
      expect(find.text('Verification email requested.'), findsOneWidget);
      await tester.ensureVisible(find.text('I verified my email — refresh'));
      await tester.tap(find.text('I verified my email — refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Email verified'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back.'), findsOneWidget);
      expect(find.text('demo@example.com'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await repo.sessions.close();
    },
  );
  testWidgets(
    'navigation away during a submitted reset does not update disposed screen',
    (tester) async {
      final repo = UiAuthRepository()..pending = Completer<void>();
      await tester.pumpWidget(SmartHireApp(authRepository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sign in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-email')),
        'demo@example.com',
      );
      await tester.tap(find.byKey(const Key('account-submit')));
      await tester.pump();
      await tester.tap(find.text('Explore jobs'));
      await tester.pumpAndSettle();
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Discover opportunities'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await repo.sessions.close();
    },
  );
}
