import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/presentation/session_cubit.dart';
import 'app_routes.dart';

/// A UI boundary only. Server authorization and data rules remain mandatory.
class SessionGate extends StatelessWidget {
  const SessionGate({super.key, required this.builder});
  final Widget Function(BuildContext, AuthUser) builder;

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionCubit, SessionState>(
    builder: (context, state) {
      if (state.status == SessionStatus.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final user = state.user;
      if (state.status == SessionStatus.signedIn && user != null) {
        return builder(context, user);
      }
      final unavailable = state.status == SessionStatus.unavailable;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  unavailable
                      ? 'Account connection unavailable'
                      : 'Sign in to view your profile',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  unavailable
                      ? 'Your account details are hidden until the connection is restored.'
                      : 'Your profile belongs to your signed-in account.',
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.signIn),
                  child: const Text('Open sign-in'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
