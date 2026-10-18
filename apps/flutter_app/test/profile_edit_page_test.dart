import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';
import 'package:smarthire/features/profile/domain/profile.dart';
import 'package:smarthire/features/profile/domain/profile_repository.dart';

import 'auth_state_test.dart' show TestAuthRepository;

class Profiles implements ProfileRepository {
  bool fail = true;
  @override
  Future<SavedProfile?> load() async {
    if (fail) throw Exception('private diagnostics');
    return SavedProfile(
      uid: 'one',
      updatedAt: DateTime.utc(2026),
      draft: ProfileDraft(displayName: 'Ada'),
    );
  }

  @override
  Future<SavedProfile> save(ProfileDraft draft) async =>
      SavedProfile(uid: 'one', updatedAt: DateTime.utc(2026), draft: draft);
}

void main() {
  testWidgets(
    'direct edit route hides form for signed-out and unverified users',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      int creates = 0;
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/profile/edit',
          profileRepositoryFactory: (_) {
            creates++;
            return Profiles();
          },
        ),
      );
      await tester.pump();
      auth.sessions.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      auth.sessions.add(
        const AuthUser(
          uid: 'one',
          email: 'a@example.com',
          emailVerified: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Verify your email in'), findsOneWidget);
      expect(creates, 0);
    },
  );
  testWidgets('verified editor retries load and removes form on sign-out', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    final profiles = Profiles();
    await tester.pumpWidget(
      SmartHireApp(
        authRepository: auth,
        initialRoute: '/profile/edit',
        profileRepositoryFactory: (_) => profiles,
      ),
    );
    await tester.pump();
    auth.sessions.add(
      const AuthUser(uid: 'one', email: 'a@example.com', emailVerified: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load your profile.'), findsOneWidget);
    profiles.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    auth.sessions.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('missing backend never presents a working save form', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    addTearDown(auth.sessions.close);
    await tester.pumpWidget(
      SmartHireApp(authRepository: auth, initialRoute: '/profile/edit'),
    );
    await tester.pump();
    auth.sessions.add(
      const AuthUser(uid: 'one', email: 'a@example.com', emailVerified: true),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Profile saving is being connected'),
      findsOneWidget,
    );
    expect(find.text('Save profile'), findsNothing);
  });
}
