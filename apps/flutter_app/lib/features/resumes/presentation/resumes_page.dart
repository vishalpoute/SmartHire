import 'package:flutter/material.dart';

import '../../../core/routing/session_gate.dart';
import '../data/api_resume_repository.dart';
import '../data/resume_picker.dart';
import '../domain/resume.dart';

class ResumesPageView extends StatelessWidget {
  const ResumesPageView({super.key, this.repositoryFactory, this.picker});
  final ResumeRepository Function(String uid)? repositoryFactory;
  final Future<PickedResume?> Function()? picker;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Private resumes')),
    body: SessionGate(
      builder: (context, user) {
        if (!user.emailVerified) {
          return const Center(
            child: Text('Verify your email before uploading a resume.'),
          );
        }
        if (repositoryFactory == null) {
          return const Center(
            child: Text(
              'Private resumes are being connected. Please check back soon.',
            ),
          );
        }
        return _Workspace(
          key: ValueKey(user.uid),
          create: () => repositoryFactory!(user.uid),
          picker: picker ?? pickPrivateResume,
        );
      },
    ),
  );
}

class _Workspace extends StatefulWidget {
  const _Workspace({super.key, required this.create, required this.picker});
  final ResumeRepository Function() create;
  final Future<PickedResume?> Function() picker;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  late final ResumeRepository repository;
  final skills = TextEditingController();
  List<ResumeRecord> records = [];
  ResumeRecord? selected;
  PickedResume? pendingFile;
  String? pendingId, cursor, message;
  bool busy = false,
      dirty = false,
      filling = false,
      allowExit = false,
      needsRefresh = false;
  double? progress;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    repository = widget.create();
    skills.addListener(() {
      if (!filling && mounted) setState(() => dirty = true);
    });
    refresh();
  }

  @override
  void dispose() {
    generation++;
    if (repository case final ApiResumeRepository api) api.close();
    skills.dispose();
    pendingFile = null;
    super.dispose();
  }

  void select(ResumeRecord? value) {
    selected = value;
    filling = true;
    skills.text = (value?.confirmedSkills ?? value?.extractedSkills ?? []).join(
      ', ',
    );
    filling = false;
    dirty = false;
  }

  Future<bool> discard() async {
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard skill edits?'),
            content: const Text('Your unconfirmed skill changes will be lost.'),
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
    if (await discard() && mounted) {
      setState(() => allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> perform(Future<void> Function(int) action) async {
    if (busy) return;
    final run = ++generation;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action(run);
    } catch (error) {
      if (!mounted || run != generation) return;
      setState(() {
        message = error is ResumeFailure
            ? error.message
            : 'Unable to complete this action. Refresh and try again.';
        if (error is ResumeFailure && error.reloadRequired) needsRefresh = true;
        if (error is ResumeFailure && error.accessDenied) {
          records = [];
          cursor = null;
          select(null);
          pendingFile = null;
          pendingId = null;
        }
      });
    } finally {
      if (mounted && run == generation) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<void> refresh({bool more = false}) async {
    if (busy || (more && cursor == null) || !await discard() || !mounted) {
      return;
    }
    await perform((run) async {
      final page = await repository.list(cursor: more ? cursor : null);
      if (!mounted || run != generation) return;
      final combined = [if (more) ...records, ...page.items];
      if (combined.map((r) => r.id).toSet().length != combined.length) {
        throw const ResumeFailure('The resume list changed. Refresh it again.');
      }
      setState(() {
        records = combined;
        cursor = page.nextCursor;
        needsRefresh = false;
        final previous = selected;
        select(
          previous == null
              ? null
              : combined.where((item) => item.id == previous.id).firstOrNull,
        );
      });
    });
  }

  Future<void> choose() async {
    if (busy || !await discard() || !mounted) return;
    await perform((run) async {
      final file = await widget.picker();
      if (!mounted || run != generation || file == null) return;
      pendingFile = file;
      pendingId = newResumeUploadId();
      await send(run);
    });
  }

  Future<void> send(int run) async {
    final file = pendingFile, id = pendingId;
    if (file == null || id == null) return;
    final record = await repository.upload(file, id, (sent, total) {
      if (mounted && run == generation) {
        setState(() => progress = total > 0 ? sent / total : null);
      }
    });
    if (!mounted || run != generation) return;
    setState(() {
      records = [record, ...records.where((item) => item.id != record.id)];
      select(record);
      pendingFile = null;
      pendingId = null;
      needsRefresh = false;
      message = 'Private upload received. Refresh to check text extraction, then confirm your skills.';
    });
  }

  Future<void> confirm() async {
    final record = selected;
    if (record == null) return;
    final values = skills.text.trim().isEmpty
        ? <String>[]
        : skills.text.split(',').map((s) => s.trim()).toList();
    await perform((run) async {
      final saved = await repository.confirm(record, values);
      if (!mounted || run != generation) return;
      setState(() {
        records = records.map((r) => r.id == saved.id ? saved : r).toList();
        select(saved);
        message = 'Skills confirmed. These are the skills used for matching.';
      });
    });
  }

  Future<void> retry() async {
    final record = selected;
    if (record == null) return;
    await perform((run) async {
      final saved = await repository.retry(record);
      if (!mounted || run != generation) return;
      setState(() {
        records = records.map((r) => r.id == saved.id ? saved : r).toList();
        select(saved);
        message = 'Processing queued. Refresh to check its status.';
      });
    });
  }

  Future<void> remove(ResumeRecord record) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this private resume?'),
        content: const Text(
          'The original and extracted text will be removed. Applications retain their submitted skill snapshots.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove resume'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await perform((run) async {
      final deleted = await repository.delete(record);
      if (!mounted || run != generation) return;
      setState(() {
        records = records.where((r) => r.id != record.id).toList();
        if (selected?.id == record.id) select(null);
        message = deleted
            ? 'Private resume removed.'
            : 'Removal is pending. Refresh to check its status.';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final record = selected;
    final editable =
        record != null &&
        [ResumeStatus.parsed, ResumeStatus.confirmed].contains(record.status);
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
                  'Your private resumes',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'PDF or DOCX, up to 5 MB. PDFs may have up to 20 pages. Scanned images are not supported. '
                  'Check and confirm extracted skill suggestions before matching.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : choose,
                  child: const Text('Upload private resume'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => refresh(),
                  child: const Text('Refresh resumes'),
                ),
                if (busy) LinearProgressIndicator(value: progress?.clamp(0, 1)),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(liveRegion: true, child: Text(message!)),
                  ),
                if (pendingFile != null) ...[
                  Text('Selected: ${pendingFile!.name}'),
                  TextButton(
                    onPressed: busy || needsRefresh
                        ? null
                        : () => perform(send),
                    child: const Text('Retry private upload'),
                  ),
                ],
                if (!busy && records.isEmpty && message == null)
                  const Text('No private resumes yet.'),
                for (final item in records)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${item.extension.toUpperCase()} · ${(item.size / 1024).toStringAsFixed(0)} KB',
                          ),
                          Text(switch (item.status) {
                            ResumeStatus.uploading => 'Waiting for upload',
                            ResumeStatus.queued => 'Queued for text extraction',
                            ResumeStatus.processing => 'Extracting text',
                            ResumeStatus.parsed => 'Confirm your skills',
                            ResumeStatus.unscored => 'Document needs attention',
                            ResumeStatus.confirmed => 'Skills confirmed',
                            ResumeStatus.deleting => 'Removal pending',
                          }),
                          Text('Updated ${item.updatedAt.toLocal()}'),
                          TextButton(
                            onPressed:
                                busy || item.status == ResumeStatus.deleting
                                ? null
                                : () async {
                                    if (await discard() && mounted) {
                                      setState(() {
                                        select(item);
                                        message = null;
                                      });
                                    }
                                  },
                            child: const Text('Review resume'),
                          ),
                          TextButton(
                            onPressed: busy || needsRefresh
                                ? null
                                : () => remove(item),
                            child: const Text('Remove private resume'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (cursor != null)
                  OutlinedButton(
                    onPressed: busy ? null : () => refresh(more: true),
                    child: const Text('Load more resumes'),
                  ),
                if (record != null) ...[
                  const SizedBox(height: 20),
                  if (record.status == ResumeStatus.unscored)
                    Text(resumeErrorMessage(record.errorCode)),
                  if (record.status == ResumeStatus.unscored &&
                      [
                        'resource_limit',
                        'storage_unavailable',
                      ].contains(record.errorCode))
                    OutlinedButton(
                      onPressed: busy || needsRefresh ? null : retry,
                      child: const Text('Retry processing'),
                    ),
                  if (editable) ...[
                    const Text(
                      'Suggestions can be incomplete or incorrect. Keep only skills you can demonstrate.',
                    ),
                    TextField(
                      controller: skills,
                      enabled: !busy,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Your skills (comma separated)',
                      ),
                    ),
                    FilledButton(
                      onPressed: busy || needsRefresh ? null : confirm,
                      child: const Text('Confirm resume skills'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
