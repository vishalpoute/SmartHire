import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/profile/data/api_profile_repository.dart';
import 'package:smarthire/features/profile/data/firebase_profile_session.dart';

class Auth extends Fake implements FirebaseAuth {
  User? user;
  @override
  User? get currentUser => user;
}

class Identity extends Fake implements User {
  Identity(this.uid);
  @override
  final String uid;
  @override
  bool emailVerified = true;
  int requests = 0;
  bool? forced;
  Future<String?> Function() token = () async => 'test-token';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) {
    requests++;
    forced = forceRefresh;
    return token();
  }
}

void main() {
  late Auth auth;
  late Identity user;
  late FirebaseProfileSession session;
  setUp(() {
    auth = Auth();
    user = Identity('owner');
    auth.user = user;
    session = FirebaseProfileSession(auth, ownerUid: 'owner');
  });
  test(
    'refreshes through Firebase on each request without caching token',
    () async {
      final first = await session.read();
      expect(first!.uid, 'owner');
      expect(first.token, 'test-token');
      expect(user.forced, isTrue);
      user.token = () async => 'new-test-token';
      expect((await session.read())!.token, 'new-test-token');
      expect(user.requests, 2);
    },
  );
  test('absent and mismatched identities never request tokens', () async {
    auth.user = null;
    expect(await session.read(), isNull);
    auth.user = Identity('other');
    expect(await session.read(), isNull);
    expect(user.requests, 0);
  });
  test('unverified identity is blocked before retrieving token', () async {
    user.emailVerified = false;
    await expectLater(session.read(), throwsA(isA<ProfileFailure>()));
    expect(user.requests, 0);
  });
  test(
    'sign-out or account switch during refresh discards old token',
    () async {
      for (final replacement in <User?>[null, Identity('other')]) {
        auth.user = user;
        final token = Completer<String?>();
        user.token = () => token.future;
        final request = session.read();
        auth.user = replacement;
        token.complete('old-test-token');
        expect(await request, isNull);
      }
    },
  );
  test('empty token and revoked verification fail closed', () async {
    user.token = () async => null;
    expect(await session.read(), isNull);
    user.token = () async {
      user.emailVerified = false;
      return 'test-token';
    };
    await expectLater(session.read(), throwsA(isA<ProfileFailure>()));
  });
  test('SDK exception diagnostics are hidden', () async {
    user.token = () async => throw FirebaseAuthException(
      code: 'private-code',
      message: 'private diagnostic',
    );
    await expectLater(
      session.read(),
      throwsA(
        isA<ProfileFailure>().having(
          (error) => error.message,
          'safe text',
          isNot(contains('private')),
        ),
      ),
    );
  });
}
