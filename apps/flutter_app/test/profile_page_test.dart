import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';

import 'auth_state_test.dart' show TestAuthRepository;

void main() {
  testWidgets(
    'direct profile link requires a session before exposing identity',
    (tester) async {
      await tester.pumpWidget(const SmartHireApp(initialRoute: '/profile'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to view your profile'), findsOneWidget);
      expect(find.text('ACCOUNT EMAIL'), findsNothing);
      await tester.tap(find.text('Open sign-in'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back.'), findsOneWidget);
    },
  );

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'profile at $width revokes visible identity on failure and sign-out',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = TestAuthRepository();
        addTearDown(repo.sessions.close);
        await tester.pumpWidget(
          SmartHireApp(authRepository: repo, initialRoute: '/profile'),
        );
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        repo.sessions.add(
          const AuthUser(
            uid: 'one',
            email: 'private@example.com',
            emailVerified: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('private@example.com'), findsOneWidget);
        expect(find.text('Email verification needed'), findsOneWidget);
        expect(tester.takeException(), isNull);
        repo.sessions.addError(Exception('private service diagnostics'));
        await tester.pumpAndSettle();
        expect(find.text('private@example.com'), findsNothing);
        expect(find.text('Account connection unavailable'), findsOneWidget);
        repo.sessions.add(
          const AuthUser(
            uid: 'two',
            email: 'another@example.com',
            emailVerified: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Email verified'), findsOneWidget);
        expect(find.text('private@example.com'), findsNothing);
        repo.sessions.add(null);
        await tester.pumpAndSettle();
        expect(find.text('another@example.com'), findsNothing);
        expect(find.text('Sign in to view your profile'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
