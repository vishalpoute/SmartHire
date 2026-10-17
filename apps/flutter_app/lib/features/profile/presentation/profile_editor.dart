import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/profile.dart';
import 'profile_cubit.dart';

/// Mount with a session-scoped ProfileCubit after live API integration is ready.
class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key});
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final TextEditingController name;
  late final TextEditingController headline;
  late final TextEditingController location;
  late final TextEditingController skills;
  @override
  void initState() {
    super.initState();
    final draft = context.read<ProfileCubit>().state.draft;
    name = TextEditingController(text: draft.displayName);
    headline = TextEditingController(text: draft.headline);
    location = TextEditingController(text: draft.location);
    skills = TextEditingController(text: draft.skills.join(', '));
  }

  @override
  void dispose() {
    for (final controller in [name, headline, location, skills]) {
      controller.dispose();
    }
    super.dispose();
  }

  void save() {
    final cubit = context.read<ProfileCubit>();
    cubit.edit(
      ProfileDraft(
        displayName: name.text,
        headline: headline.text,
        location: location.text,
        skills: skills.text.trim().isEmpty ? [] : skills.text.split(','),
      ),
    );
    cubit.save();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ProfileCubit, ProfileState>(
        listener: (context, state) {
          if (state.status == ProfileStatus.saved) {
            name.text = state.draft.displayName;
            headline.text = state.draft.headline;
            location.text = state.draft.location;
            skills.text = state.draft.skills.join(', ');
          }
        },
        builder: (context, state) {
          final busy =
              state.status == ProfileStatus.saving ||
              state.status == ProfileStatus.loading;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Your profile',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: name,
                      enabled: !busy,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Display name',
                        errorText: state.errors['display_name'],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: headline,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: 'Headline',
                        errorText: state.errors['headline'],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: location,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: 'Location',
                        errorText: state.errors['location'],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: skills,
                      enabled: !busy,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Skills',
                        helperText: 'Separate skills with commas.',
                        errorText: state.errors['skills'],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (state.message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(state.message!),
                        ),
                      ),
                    if (state.status == ProfileStatus.saved)
                      Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text('Profile saved.'),
                        ),
                      ),
                    FilledButton(
                      onPressed: busy ? null : save,
                      child: Text(busy ? 'Saving...' : 'Save profile'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
