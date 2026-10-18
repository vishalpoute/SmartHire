import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  late List<String> savedValues;
  bool dirty = false;
  bool allowExit = false;
  bool updating = false;
  bool confirming = false;
  List<String> get values => [
    name.text,
    headline.text,
    location.text,
    skills.text,
  ];

  void changed() {
    if (!updating && mounted) {
      setState(() => dirty = !listEquals(values, savedValues));
    }
  }

  Future<void> tryExit(bool didPop, bool busy) async {
    if (didPop || confirming) return;
    if (busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for the save to finish.')),
      );
      return;
    }
    if (!dirty) return;
    confirming = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Your profile edits have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    confirming = false;
    if (discard == true) {
      setState(() => allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final draft = context.read<ProfileCubit>().state.draft;
    name = TextEditingController(text: draft.displayName);
    headline = TextEditingController(text: draft.headline);
    location = TextEditingController(text: draft.location);
    skills = TextEditingController(text: draft.skills.join(', '));
    savedValues = values;
    for (final controller in [name, headline, location, skills]) {
      controller.addListener(changed);
    }
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
            updating = true;
            name.text = state.draft.displayName;
            headline.text = state.draft.headline;
            location.text = state.draft.location;
            skills.text = state.draft.skills.join(', ');
            savedValues = values;
            dirty = false;
            updating = false;
          }
        },
        builder: (context, state) {
          final busy =
              state.status == ProfileStatus.saving ||
              state.status == ProfileStatus.loading;
          return PopScope<void>(
            canPop: allowExit || (!dirty && !busy),
            onPopInvokedWithResult: (didPop, _) => tryExit(didPop, busy),
            child: SingleChildScrollView(
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
            ),
          );
        },
      );
}
