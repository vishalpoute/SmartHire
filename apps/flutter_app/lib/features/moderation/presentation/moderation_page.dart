import 'package:flutter/material.dart';

import '../../../core/routing/session_gate.dart';
import '../../applications/domain/application.dart';
import '../domain/moderation.dart';

class ModerationPage extends StatelessWidget {
  const ModerationPage({super.key, this.repositoryFactory});
  final ModerationRepository Function(String uid)? repositoryFactory;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Moderation and audit')),
    body: SessionGate(
      builder: (context, user) {
        if (!user.emailVerified) {
          return const Center(
            child: Text(
              'Verify your email before requesting administrator access.',
            ),
          );
        }
        if (repositoryFactory == null) {
          return const Center(
            child: Text('Administrator tools are being connected.'),
          );
        }
        return _Workspace(
          key: ValueKey(user.uid),
          create: () => repositoryFactory!(user.uid),
        );
      },
    ),
  );
}

class _Workspace extends StatefulWidget {
  const _Workspace({super.key, required this.create});
  final ModerationRepository Function() create;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  late final ModerationRepository repository;
  List<ModerationJob> jobs = [];
  List<ModerationAudit> audits = [];
  String view = 'published';
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
        stale = error.accessDenied || error.reloadRequired;
        if (error.accessDenied) {
          jobs = [];
          audits = [];
          cursor = null;
        }
      });
    } catch (_) {
      if (mounted && token == generation) {
        setState(() {
          message = 'Administrator request failed. Refresh and retry.';
          stale = true;
        });
      }
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  Future<void> refresh({bool more = false}) => run((token) async {
    if (view == 'audit') {
      final page = await repository.audits(cursor: more ? cursor : null);
      if (!mounted || token != generation) return;
      final values = [...(more ? audits : <ModerationAudit>[]), ...page.items];
      if (values.map((row) => row.id).toSet().length != values.length) {
        throw const ApplicationFailure(
          'Audit list changed. Refresh.',
          reloadRequired: true,
        );
      }
      setState(() {
        audits = values;
        jobs = [];
        cursor = page.nextCursor;
        stale = false;
      });
    } else {
      final page = await repository.jobs(view, cursor: more ? cursor : null);
      if (!mounted || token != generation) return;
      final values = [...(more ? jobs : <ModerationJob>[]), ...page.items];
      if (values.map((row) => row.id).toSet().length != values.length) {
        throw const ApplicationFailure(
          'Job list changed. Refresh.',
          reloadRequired: true,
        );
      }
      setState(() {
        jobs = values;
        audits = [];
        cursor = page.nextCursor;
        stale = false;
      });
    }
  });
  Future<void> moderate(ModerationJob job) async {
    if (busy || stale) return;
    var reason = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            job.status == 'published'
                ? 'Suspend listing?'
                : 'Restore as draft?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                job.status == 'published'
                    ? 'This removes the listing from public discovery and prevents new applications.'
                    : 'The owner must review and explicitly publish again; current approval checks still apply.',
              ),
              TextField(
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Moderation reason',
                ),
                onChanged: (value) => update(() => reason = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: reason.trim().length < 3
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Confirm moderation'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || accepted != true) return;
    await run((token) async {
      await repository.moderate(job, reason);
      if (mounted && token == generation) {
        setState(() {
          jobs = jobs.where((row) => row.id != job.id).toList();
          message = 'Moderation recorded with an audit event.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Administrator access is verified by the server for every request. Audit entries are ordered by record ID, not recency.',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in ['published', 'suspended', 'audit'])
                ChoiceChip(
                  label: Text(
                    value == 'audit' ? 'Audit events' : '$value listings',
                  ),
                  selected: view == value,
                  onSelected: busy
                      ? null
                      : (_) {
                          setState(() {
                            view = value;
                            jobs = [];
                            audits = [];
                            cursor = null;
                          });
                          refresh();
                        },
                ),
              OutlinedButton(
                onPressed: busy ? null : () => refresh(),
                child: const Text('Refresh moderation'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (message != null) Text(message!),
          if (stale) const Text('Refresh before another action.'),
          if (!busy && jobs.isEmpty && audits.isEmpty)
            const Text('No records in this view.'),
          for (final job in jobs)
            Card(
              key: ValueKey(job.id),
              child: ExpansionTile(
                title: Text(job.title),
                subtitle: Text('${job.status} · version ${job.version}'),
                childrenPadding: const EdgeInsets.all(16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.description),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy || stale ? null : () => moderate(job),
                    child: Text(
                      job.status == 'published'
                          ? 'Suspend listing'
                          : 'Restore as draft',
                    ),
                  ),
                ],
              ),
            ),
          for (final audit in audits)
            Card(
              key: ValueKey(audit.id),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audit.action,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Actor: ${audit.actor}'),
                    if (audit.target != null) Text('Target: ${audit.target}'),
                    Text(audit.createdAt),
                    if (audit.reason.isNotEmpty) Text(audit.reason),
                  ],
                ),
              ),
            ),
          if (cursor != null)
            OutlinedButton(
              onPressed: busy || stale ? null : () => refresh(more: true),
              child: const Text('Load more admin records'),
            ),
        ],
      ),
    ),
  );
}
