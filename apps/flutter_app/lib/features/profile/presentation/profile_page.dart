import 'package:flutter/material.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/routing/session_gate.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your profile')),
    body: SessionGate(
      builder: (context, user) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A good next step starts with you.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 20),
                    const Text('ACCOUNT EMAIL'),
                    const SizedBox(height: 8),
                    SelectableText(user.email ?? 'No email address available'),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        user.emailVerified
                            ? Icons.verified_outlined
                            : Icons.mail_outline,
                      ),
                      title: Text(
                        user.emailVerified
                            ? 'Email verified'
                            : 'Email verification needed',
                      ),
                      subtitle: Text(
                        user.emailVerified
                            ? 'Your account email is confirmed.'
                            : 'Open your account to request verification or refresh your status.',
                      ),
                    ),
                    const Divider(height: 32),
                    Text(
                      'Profile details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Add your profile details and skills when profile saving is available. Resume uploads are coming later.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Email verification does not grant recruiter or administrator permissions. Job listings remain fictional samples.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.profileEdit),
                      child: const Text('Edit profile'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.signIn),
                      child: const Text('Manage account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
