import 'package:flutter/material.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/auth_repository.dart';
import 'auth_action_cubit.dart';

class AccountSummary extends StatelessWidget {
  const AccountSummary({
    super.key,
    required this.user,
    required this.actions,
    required this.state,
  });
  final AuthUser user;
  final AuthActionCubit actions;
  final AuthActionState state;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  size: 48,
                  color: AppTheme.ink,
                ),
                const SizedBox(height: 20),
                Text(
                  'Your account',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                SelectableText(user.email ?? 'Signed-in account'),
                const SizedBox(height: 20),
                Text(
                  user.emailVerified
                      ? 'Email verified'
                      : 'Verify your email before applying for jobs.',
                ),
                if (!user.emailVerified)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: FilledButton(
                      onPressed: state.status == AuthActionStatus.submitting
                          ? null
                          : actions.verifyEmail,
                      child: const Text('Send verification email'),
                    ),
                  ),
                if (!user.emailVerified)
                  TextButton(
                    onPressed: state.status == AuthActionStatus.submitting
                        ? null
                        : actions.refreshSession,
                    child: const Text('I verified my email — refresh'),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Jobs are still sample listings. Profiles, applications and recruiter approval are coming next.',
                ),
                if (state.message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      state.message!,
                      key: const Key('account-action-message'),
                      semanticsLabel: state.message,
                    ),
                  ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context,
                        AppRoutes.discover,
                        (_) => false,
                      ),
                      child: const Text('Explore jobs'),
                    ),
                    TextButton(
                      onPressed: state.status == AuthActionStatus.submitting
                          ? null
                          : actions.signOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
