import 'package:flutter/material.dart';

import '../../../core/routing/session_gate.dart';
import '../../../core/routing/app_routes.dart';
import '../../applications/domain/application.dart';
import '../../resumes/domain/resume.dart';
import '../domain/saved_job.dart';

class SavedJobsPage extends StatelessWidget {
  const SavedJobsPage({super.key, this.repositoryFactory, this.jobId});
  final SavedJobsRepository Function(String uid)? repositoryFactory;
  final String? jobId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved roles')),
    body: SessionGate(
      builder: (context, user) {
        if (!user.emailVerified) {
          return const Center(
            child: Text('Verify your email before saving roles.'),
          );
        }
        if (repositoryFactory == null) {
          return const Center(
            child: Text(
              'Saved roles are being connected. Please check back soon.',
            ),
          );
        }
        if (jobId != null && !resumeHex(jobId!, 32)) {
          return const Center(child: Text('This role is unavailable.'));
        }
        return _SavedWorkspace(
          key: ValueKey(user.uid),
          create: () => repositoryFactory!(user.uid),
          jobId: jobId,
        );
      },
    ),
  );
}

class _SavedWorkspace extends StatefulWidget {
  const _SavedWorkspace({super.key, required this.create, required this.jobId});
  final SavedJobsRepository Function() create;
  final String? jobId;
  @override
  State<_SavedWorkspace> createState() => _SavedWorkspaceState();
}

class _SavedWorkspaceState extends State<_SavedWorkspace> {
  late final SavedJobsRepository repository;
  List<SavedJob> items = [];
  String? cursor, message;
  bool busy = false, stale = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    repository = widget.create();
    refresh();
  }

  @override
  void dispose() {
    generation++;
    repository.close();
    super.dispose();
  }

  Future<void> run(Future<void> Function(int) action) async {
    if (busy) return;
    final token = ++generation;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action(token);
    } on ApplicationFailure catch (error) {
      if (!mounted || token != generation) return;
      setState(() {
        message = error.message;
        stale = error.reloadRequired || error.accessDenied;
        if (error.accessDenied) {
          items = [];
          cursor = null;
        }
      });
    } catch (_) {
      if (mounted && token == generation) {
        setState(() {
          message = 'Saved roles could not be loaded. Refresh and try again.';
          stale = true;
        });
      }
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  Future<void> refresh({bool more = false}) => run((token) async {
    final page = await repository.saved(cursor: more ? cursor : null);
    if (!mounted || token != generation) return;
    final merged = [...(more ? items : <SavedJob>[]), ...page.items];
    if (merged.map((row) => row.jobId).toSet().length != merged.length) {
      throw const ApplicationFailure(
        'Saved roles changed. Refresh again.',
        reloadRequired: true,
      );
    }
    setState(() {
      items = merged;
      cursor = page.nextCursor;
      stale = false;
    });
  });
  Future<void> save() => run((token) async {
    final value = await repository.save(widget.jobId!);
    if (mounted && token == generation) {
      setState(() {
        items = [value, ...items.where((row) => row.jobId != value.jobId)];
        message = 'Role saved to your account.';
      });
    }
  });
  Future<void> remove(SavedJob value) => run((token) async {
    await repository.remove(value.jobId);
    if (mounted && token == generation) {
      setState(() {
        items = items.where((row) => row.jobId != value.jobId).toList();
        message = 'Saved role removed.';
      });
    }
  });
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Saved roles belong to your account and remain available across sessions. Availability is checked again when you open them.',
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : () => refresh(),
                child: const Text('Refresh saved roles'),
              ),
              if (widget.jobId != null)
                FilledButton(
                  onPressed: busy || stale ? null : save,
                  child: const Text('Save this role'),
                ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (message != null) Text(message!),
          if (stale) const Text('Refresh before another action.'),
          if (!busy && items.isEmpty) const Text('No saved roles yet.'),
          for (final item in items)
            Card(
              key: ValueKey(item.id),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? 'Role no longer available',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (item.company != null) Text(item.company!),
                    Wrap(
                      spacing: 12,
                      children: [
                        if (item.title != null)
                          TextButton(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.jobDetails(item.jobId),
                            ),
                            child: const Text('View saved role'),
                          ),
                        TextButton(
                          onPressed: busy || stale ? null : () => remove(item),
                          child: const Text('Remove saved role'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (cursor != null)
            OutlinedButton(
              onPressed: busy || stale ? null : () => refresh(more: true),
              child: const Text('Load more saved roles'),
            ),
        ],
      ),
    ),
  );
}
