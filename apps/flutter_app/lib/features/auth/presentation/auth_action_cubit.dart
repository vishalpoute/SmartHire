import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/auth_repository.dart';

enum AuthActionStatus { idle, submitting, succeeded, failed }

class AuthActionState {
  const AuthActionState(this.status, {this.message});
  final AuthActionStatus status;
  final String? message;
}

class AuthActionCubit extends Cubit<AuthActionState> {
  AuthActionCubit(this._repository)
    : super(const AuthActionState(AuthActionStatus.idle));
  final AuthRepository _repository;

  Future<void> signIn(String email, String password) => _run(
    () => _repository.signIn(email: email, password: password),
    'Signed in.',
  );
  Future<void> register(String email, String password) => _run(
    () => _repository.register(email: email, password: password),
    'Account created. Verify your email before applying.',
  );
  Future<void> resetPassword(String email) => _run(
    () => _repository.sendPasswordReset(email),
    'If this email is eligible, a reset link has been requested.',
  );
  Future<void> verifyEmail() =>
      _run(_repository.sendVerification, 'Verification email requested.');
  Future<void> signOut() => _run(_repository.signOut, 'Signed out.');
  Future<void> refreshSession() =>
      _run(_repository.refreshSession, 'Account status refreshed.');

  Future<void> _run(Future<void> Function() operation, String success) async {
    if (isClosed || state.status == AuthActionStatus.submitting) return;
    emit(const AuthActionState(AuthActionStatus.submitting));
    try {
      await operation();
      if (!isClosed) {
        emit(AuthActionState(AuthActionStatus.succeeded, message: success));
      }
    } on AuthFailure catch (error) {
      if (!isClosed) {
        emit(AuthActionState(AuthActionStatus.failed, message: error.message));
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          const AuthActionState(
            AuthActionStatus.failed,
            message: 'Something went wrong. Please try again.',
          ),
        );
      }
    }
  }
}
