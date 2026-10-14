import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/auth_repository.dart';

enum SessionStatus { loading, signedOut, signedIn, unavailable }

class SessionState {
  const SessionState(this.status, {this.user});
  final SessionStatus status;
  final AuthUser? user;
  bool get isVerified =>
      status == SessionStatus.signedIn && (user?.emailVerified ?? false);
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit(AuthRepository? repository)
    : super(const SessionState(SessionStatus.loading)) {
    if (repository == null) {
      emit(const SessionState(SessionStatus.signedOut));
      return;
    }
    _subscription = repository.watchSession().listen(
      (user) {
        if (!isClosed) {
          emit(
            SessionState(
              user == null ? SessionStatus.signedOut : SessionStatus.signedIn,
              user: user,
            ),
          );
        }
      },
      onError: (Object error) {
        if (!isClosed) emit(const SessionState(SessionStatus.unavailable));
      },
    );
  }
  StreamSubscription<AuthUser?>? _subscription;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await super.close();
  }
}
