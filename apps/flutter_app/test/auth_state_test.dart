import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';
import 'package:smarthire/features/auth/data/firebase_auth_repository.dart';
import 'package:smarthire/features/auth/presentation/auth_action_cubit.dart';
import 'package:smarthire/features/auth/presentation/session_cubit.dart';

class TestAuthRepository implements AuthRepository {
  final sessions = StreamController<AuthUser?>.broadcast();
  Completer<void>? pending;
  Object? failure;
  int requests = 0;
  @override
  Stream<AuthUser?> watchSession() => sessions.stream;
  Future<void> execute() async {
    requests++;
    if (failure != null) throw failure!;
    if (pending != null) await pending!.future;
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      execute();
  @override
  Future<void> register({required String email, required String password}) =>
      execute();
  @override
  Future<void> sendPasswordReset(String email) => execute();
  @override
  Future<void> sendVerification() => execute();
  @override
  Future<void> signOut() => execute();
  @override
  Future<void> refreshSession() => execute();
}

void main() {
  test('duplicate submissions cannot send a second auth request', () async {
    final repo = TestAuthRepository()..pending = Completer<void>();
    final cubit = AuthActionCubit(repo);
    addTearDown(cubit.close);
    final first = cubit.signIn('demo@example.com', 'password');
    await cubit.signIn('demo@example.com', 'password');
    expect(repo.requests, 1);
    expect(cubit.state.status, AuthActionStatus.submitting);
    repo.pending!.complete();
    await first;
    expect(cubit.state.status, AuthActionStatus.succeeded);
  });
  test('a failed request can be retried successfully', () async {
    final repo = TestAuthRepository()
      ..failure = const AuthFailure('Connection unavailable.');
    final cubit = AuthActionCubit(repo);
    addTearDown(cubit.close);
    await cubit.signIn('demo@example.com', 'password');
    expect(cubit.state.status, AuthActionStatus.failed);
    repo.failure = null;
    await cubit.signIn('demo@example.com', 'password');
    expect(cubit.state.status, AuthActionStatus.succeeded);
  });
  test('unexpected errors are not exposed to users', () async {
    final repo = TestAuthRepository()
      ..failure = Exception('sensitive diagnostic');
    final cubit = AuthActionCubit(repo);
    addTearDown(cubit.close);
    await cubit.register('demo@example.com', 'password');
    expect(cubit.state.message, isNot(contains('sensitive')));
    expect(cubit.state.status, AuthActionStatus.failed);
  });
  test('closing during a request prevents late state updates', () async {
    final repo = TestAuthRepository()..pending = Completer<void>();
    final cubit = AuthActionCubit(repo);
    final request = cubit.resetPassword('demo@example.com');
    await cubit.close();
    repo.pending!.complete();
    await request;
    expect(cubit.isClosed, isTrue);
  });
  test('session handles sign-in, verification changes and sign-out', () async {
    final repo = TestAuthRepository();
    final cubit = SessionCubit(repo);
    repo.sessions.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.status, SessionStatus.signedOut);
    repo.sessions.add(
      const AuthUser(
        uid: 'demo',
        email: 'demo@example.com',
        emailVerified: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isVerified, isFalse);
    repo.sessions.add(
      const AuthUser(
        uid: 'demo',
        email: 'demo@example.com',
        emailVerified: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isVerified, isTrue);
    repo.sessions.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.user, isNull);
    await cubit.close();
    expect(repo.sessions.hasListener, isFalse);
    await repo.sessions.close();
  });
  test('session stream errors revoke local signed-in state', () async {
    final repo = TestAuthRepository();
    final cubit = SessionCubit(repo);
    repo.sessions.add(
      const AuthUser(
        uid: 'demo',
        email: 'demo@example.com',
        emailVerified: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    repo.sessions.addError(Exception('service failed'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.status, SessionStatus.unavailable);
    expect(cubit.state.user, isNull);
    expect(cubit.state.isVerified, isFalse);
    await cubit.close();
    await repo.sessions.close();
  });
  test(
    'sign-in errors do not distinguish unknown users from wrong passwords',
    () {
      expect(
        FirebaseAuthRepository.messageForCode('user-not-found'),
        FirebaseAuthRepository.messageForCode('wrong-password'),
      );
    },
  );
}
