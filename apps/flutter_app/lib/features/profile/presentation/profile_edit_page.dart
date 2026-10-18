import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/routing/session_gate.dart';
import '../data/api_profile_repository.dart';
import '../domain/profile_repository.dart';
import 'profile_cubit.dart';
import 'profile_editor.dart';

class ProfileEditPage extends StatelessWidget {
  const ProfileEditPage({super.key, this.repositoryFactory});
  final ProfileRepository Function(String uid)? repositoryFactory;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit profile')),
    body: SessionGate(
      builder: (context, user) {
        if (!user.emailVerified) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Verify your email in Manage account before editing your profile.',
              ),
            ),
          );
        }
        if (repositoryFactory == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Profile saving is being connected. Please check back soon.',
              ),
            ),
          );
        }
        return _EditorSession(
          key: ValueKey(user.uid),
          create: () => repositoryFactory!(user.uid),
        );
      },
    ),
  );
}

class _EditorSession extends StatefulWidget {
  const _EditorSession({super.key, required this.create});
  final ProfileRepository Function() create;
  @override
  State<_EditorSession> createState() => _EditorSessionState();
}

class _EditorSessionState extends State<_EditorSession> {
  late final ProfileRepository repository;
  late final ProfileCubit cubit;
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    repository = widget.create();
    cubit = ProfileCubit(repository)..load();
  }

  @override
  void dispose() {
    cubit.close();
    if (repository case final ApiProfileRepository api) {
      api.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: cubit,
    child: BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (!loaded && state.status == ProfileStatus.ready) loaded = true;
        if (!loaded) {
          if (state.status == ProfileStatus.failure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unable to load your profile.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: cubit.load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        return const ProfileEditor();
      },
    ),
  );
}
