import 'package:flutter/material.dart';

import '../../../core/routing/session_gate.dart';
import '../data/api_recruiter_jobs_repository.dart';
import '../domain/recruiter_job.dart';

class RecruiterJobsPage extends StatelessWidget {
  const RecruiterJobsPage({super.key, this.repositoryFactory});
  final RecruiterJobsRepository Function(String uid)? repositoryFactory;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manage jobs')),
    body: SessionGate(
      builder: (context, user) {
        if (!user.emailVerified) {
          return const Center(
            child: Text('Verify your email before managing jobs.'),
          );
        }
        if (repositoryFactory == null) {
          return const Center(
            child: Text('Job management is not available yet.'),
          );
        }
        return _Editor(
          key: ValueKey(user.uid),
          create: () => repositoryFactory!(user.uid),
        );
      },
    ),
  );
}

class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.create});
  final RecruiterJobsRepository Function() create;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final RecruiterJobsRepository repository;
  final id = TextEditingController();
  final fields = List.generate(5, (_) => TextEditingController());
  RecruiterJob? job;
  List<RecruiterJob> ownedJobs = [];
  String? nextCursor;
  String workMode = 'onsite', employmentType = 'full_time';
  String? message;
  bool busy = false,
      dirty = false,
      filling = false,
      reloadRequired = false,
      allowExit = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    repository = widget.create();
    for (final field in fields) {
      field.addListener(changed);
    }
  }

  void changed() {
    if (!filling && mounted) setState(() => dirty = true);
  }

  @override
  void dispose() {
    generation++;
    id.dispose();
    for (final field in fields) {
      field.dispose();
    }
    if (repository case final ApiRecruiterJobsRepository api) api.close();
    super.dispose();
  }

  RecruiterJobFields get draft => RecruiterJobFields(
    title: fields[0].text,
    description: fields[1].text,
    location: fields[2].text,
    requiredSkills: splitSkills(fields[3].text),
    preferredSkills: splitSkills(fields[4].text),
    workMode: workMode,
    employmentType: employmentType,
  );
  List<String> splitSkills(String value) => value.trim().isEmpty
      ? []
      : value.split(',').map((s) => s.trim()).toList();

  void fill(RecruiterJob? value) {
    filling = true;
    final data = value?.fields;
    final texts = [
      data?.title ?? '',
      data?.description ?? '',
      data?.location ?? '',
      data?.requiredSkills.join(', ') ?? '',
      data?.preferredSkills.join(', ') ?? '',
    ];
    for (var i = 0; i < fields.length; i++) {
      fields[i].text = texts[i];
    }
    id.text = value?.id ?? '';
    filling = false;
    job = value;
    workMode = data?.workMode ?? 'onsite';
    employmentType = data?.employmentType ?? 'full_time';
    dirty = false;
    reloadRequired = false;
  }

  Future<bool> discard() async {
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard job edits?'),
            content: const Text('Your unsaved job changes will be lost.'),
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
        ) ??
        false;
  }

  Future<void> leave(bool didPop) async {
    if (didPop || busy || !dirty) return;
    if (!await discard() || !mounted) return;
    setState(() => allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> listJobs({bool more = false}) async {
    if (busy || (more && nextCursor == null)) return;
    await run(() async {
      final page = await repository.list(cursor: more ? nextCursor : null);
      if (!mounted) return;
      final merged = [if (more) ...ownedJobs, ...page.items];
      if (merged.map((item) => item.id).toSet().length != merged.length) {
        throw const RecruiterJobFailure(
          'The job list changed. Reload your jobs.',
        );
      }
      ownedJobs = merged;
      nextCursor = page.nextCursor;
    }, 'Your jobs loaded. Select a job to load its latest version.');
  }

  Future<void> load() async {
    if (busy || !await discard() || !mounted) return;
    final target = id.text.trim();
    if (!validJobId(target)) {
      setState(() => message = 'Enter a valid 32-character job ID.');
      return;
    }
    await run(() async {
      final loaded = await repository.load(target);
      if (mounted) fill(loaded);
    }, 'Job loaded.');
  }

  Future<void> save() async {
    if (busy || reloadRequired) return;
    final error = draft.validate();
    if (error != null) {
      setState(() => message = error);
      return;
    }
    await run(() async {
      final saved = await repository.save(draft, previous: job);
      if (mounted) fill(saved);
    }, 'Private draft saved. Keep the job ID to reopen it.');
  }

  Future<void> transition(bool publish) async {
    final current = job;
    if (busy || dirty || reloadRequired || current == null) return;
    final error = publish ? current.fields.validate(publish: true) : null;
    if (error != null) {
      setState(() => message = error);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(publish ? 'Publish this job?' : 'Close this vacancy?'),
        content: Text(
          publish
              ? '${current.fields.title} will become publicly visible if approved by the service.'
              : '${current.fields.title} will stop accepting applications and disappear from public discovery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(publish ? 'Publish now' : 'Close now'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    await run(() async {
      await repository.transition(current, publish: publish);
      if (!mounted) return;
      final loaded = await repository.load(current.id);
      if (mounted) fill(loaded);
    }, publish ? 'Job published.' : 'Vacancy closed.');
  }

  Future<void> run(Future<void> Function() action, String success) async {
    final runId = ++generation;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
      if (!mounted || runId != generation) return;
      setState(() => message = success);
    } catch (error) {
      if (!mounted || runId != generation) return;
      setState(() {
        ownedJobs = [];
        nextCursor = null;
        if (error is RecruiterJobFailure && error.accessDenied) fill(null);
        reloadRequired = true;
        message = error is RecruiterJobFailure
            ? error.message
            : 'Unable to complete this action. Reload before retrying.';
      });
    } finally {
      if (mounted && runId == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = !busy && (job == null || job!.status == 'draft');
    return PopScope<void>(
      canPop: allowExit || (!dirty && !busy),
      onPopInvokedWithResult: (didPop, _) => leave(didPop),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Recruiter job workspace',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Creating, editing and publishing require an approved recruiter account and company. '
                  'Drafts stay private until you explicitly publish.',
                ),
                TextField(
                  controller: id,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Existing job ID',
                  ),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => listJobs(),
                  child: const Text('Load my jobs'),
                ),
                for (final owned in ownedJobs)
                  ListTile(
                    title: Text(owned.fields.title),
                    subtitle: Text('${owned.status} · ${owned.id}'),
                    onTap: busy
                        ? null
                        : () {
                            id.text = owned.id;
                            load();
                          },
                  ),
                if (nextCursor != null)
                  OutlinedButton(
                    onPressed: busy ? null : () => listJobs(more: true),
                    child: const Text('More of my jobs'),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : load,
                  child: const Text('Load job'),
                ),
                OutlinedButton(
                  onPressed: busy || reloadRequired
                      ? null
                      : () async {
                          if (await discard() && mounted) {
                            setState(() {
                              fill(null);
                              message = null;
                            });
                          }
                        },
                  child: const Text('New draft'),
                ),
                if (busy) const LinearProgressIndicator(),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(liveRegion: true, child: Text(message!)),
                  ),
                if (job != null) ...[
                  SelectableText('Job ID: ${job!.id}'),
                  Text('Status: ${job!.status} · Version ${job!.version}'),
                ],
                if (reloadRequired)
                  const Text(
                    'Reload the job before another write. '
                    'If a new draft save failed, it may still have completed; do not create a duplicate.',
                  ),
                for (var i = 0; i < fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: fields[i],
                      enabled: editable,
                      minLines: i == 1 ? 4 : 1,
                      maxLines: i == 1 ? 12 : 1,
                      decoration: InputDecoration(
                        labelText: const [
                          'Job title',
                          'Job description',
                          'Location',
                          'Required skills (comma separated)',
                          'Preferred skills (comma separated)',
                        ][i],
                      ),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: workMode,
                  key: ValueKey('mode-$workMode'),
                  decoration: const InputDecoration(labelText: 'Work mode'),
                  items: RecruiterJobFields.workModes
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: editable
                      ? (v) => setState(() {
                          workMode = v!;
                          dirty = true;
                        })
                      : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: employmentType,
                  key: ValueKey('type-$employmentType'),
                  decoration: const InputDecoration(
                    labelText: 'Employment type',
                  ),
                  items: RecruiterJobFields.employmentTypes
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: editable
                      ? (v) => setState(() {
                          employmentType = v!;
                          dirty = true;
                        })
                      : null,
                ),
                const SizedBox(height: 20),
                if (job == null || job!.status == 'draft')
                  FilledButton(
                    onPressed: busy || reloadRequired ? null : save,
                    child: const Text('Save private draft'),
                  ),
                if (job?.status == 'draft')
                  OutlinedButton(
                    onPressed: busy || dirty || reloadRequired
                        ? null
                        : () => transition(true),
                    child: const Text('Publish job'),
                  ),
                if (job?.status == 'published')
                  OutlinedButton(
                    onPressed: busy || reloadRequired
                        ? null
                        : () => transition(false),
                    child: const Text('Close vacancy'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
