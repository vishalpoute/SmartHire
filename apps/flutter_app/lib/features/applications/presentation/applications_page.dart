import 'package:flutter/material.dart';

import '../../../core/routing/session_gate.dart';
import '../../../core/routing/app_routes.dart';
import '../../resumes/domain/resume.dart';
import '../domain/application.dart';

class ApplicationsPage extends StatelessWidget {
  const ApplicationsPage({
    super.key,
    this.repositoryFactory,
    this.jobId,
    this.recruiter = false,
  });
  final ApplicationsRepository Function(String uid)? repositoryFactory;
  final String? jobId;
  final bool recruiter;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        jobId != null
            ? 'Match and apply'
            : recruiter
            ? 'Candidate applications'
            : 'My applications',
      ),
    ),
    body: SessionGate(
      builder: (context, user) {
        if (!user.emailVerified) {
          return const Center(
            child: Text('Verify your email before using applications.'),
          );
        }
        if (repositoryFactory == null) {
          return const Center(
            child: Text(
              'Applications are being connected. Please check back soon.',
            ),
          );
        }
        if (jobId != null && !resumeHex(jobId!, 32)) {
          return const Center(child: Text('This job is unavailable.'));
        }
        return _Workspace(
          key: ValueKey('${user.uid}:$recruiter:$jobId'),
          create: () => repositoryFactory!(user.uid),
          jobId: jobId,
          recruiter: recruiter,
        );
      },
    ),
  );
}

class _Workspace extends StatefulWidget {
  const _Workspace({
    super.key,
    required this.create,
    required this.jobId,
    required this.recruiter,
  });
  final ApplicationsRepository Function() create;
  final String? jobId;
  final bool recruiter;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  late final ApplicationsRepository repository;
  List<ResumeRecord> resumes = [];
  List<JobApplication> applications = [];
  ResumeRecord? selected;
  ApplicationMatch? match;
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
        if (error.accessDenied) {
          resumes = [];
          applications = [];
          selected = null;
          match = null;
          cursor = null;
        }
        stale = error.reloadRequired || error.accessDenied;
      });
    } catch (_) {
      if (mounted && token == generation) {
        setState(() {
          message = 'The request could not finish. Refresh and try again.';
          stale = true;
        });
      }
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  Future<void> refresh({bool more = false}) => run((token) async {
    if (widget.jobId != null) {
      final page = await repository.resumes(cursor: more ? cursor : null);
      if (!mounted || token != generation) return;
      final all = [...(more ? resumes : <ResumeRecord>[]), ...page.items];
      if (all.map((row) => row.id).toSet().length != all.length) {
        throw const ApplicationFailure(
          'Resume list changed. Refresh again.',
          reloadRequired: true,
        );
      }
      setState(() {
        resumes = all;
        cursor = page.nextCursor;
        selected = null;
        match = null;
        stale = false;
      });
    } else {
      final page = await repository.list(
        recruiter: widget.recruiter,
        cursor: more ? cursor : null,
      );
      if (!mounted || token != generation) return;
      final all = [
        ...(more ? applications : <JobApplication>[]),
        ...page.items,
      ];
      if (all.map((row) => row.id).toSet().length != all.length) {
        throw const ApplicationFailure(
          'Application list changed. Refresh again.',
          reloadRequired: true,
        );
      }
      setState(() {
        applications = all;
        cursor = page.nextCursor;
        stale = false;
      });
    }
  });

  Future<void> preview() => run((token) async {
    final value = await repository.match(widget.jobId!, selected!);
    if (mounted && token == generation) setState(() => match = value);
  });

  Future<void> apply() async {
    final source = match;
    if (source == null || busy || stale) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit application?'),
        content: const Text(
          'Share your profile name, headline, location and confirmed skills with this recruiter. The application keeps this version of your skills and the job for tracking. Your private original file is not shared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit application'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true || source != match) return;
    await run((token) async {
      final value = await repository.apply(source);
      if (mounted && token == generation) {
        setState(() {
          match = null;
          selected = null;
          message =
              'Application ${value.status}. Open My applications to track it.';
        });
      }
    });
  }

  Future<void> change(JobApplication application, String status) async {
    if (busy || stale) return;
    var reason = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('$status application?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status == 'withdrawn'
                    ? 'Withdrawal is final. This job will remain in your application history.'
                    : 'This records your decision; matching never makes hiring decisions.',
              ),
              if (status == 'rejected')
                TextField(
                  maxLength: 500,
                  onChanged: (value) => update(() => reason = value),
                  decoration: const InputDecoration(
                    labelText: 'Reason for rejection',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: status == 'rejected' && reason.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Confirm decision'),
            ),
          ],
        ),
      ),
    );
    final text = reason.trim();
    if (!mounted || accepted != true) return;
    await run((token) async {
      final value = await repository.change(application, status, text);
      if (mounted && token == generation) {
        setState(() {
          applications = applications
              .map((row) => row.id == value.id ? value : row)
              .toList();
          message = 'Application ${value.status}.';
        });
      }
    });
  }

  Widget evidence(ApplicationMatch value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${value.jobTitle} · ${value.companyName}'),
      Text(
        value.score == null
            ? 'Unscored: this job has no required skills.'
            : '${value.score!.toStringAsFixed(2)}% required skill coverage',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const Text(
        'Skill coverage supports human review; it does not assess experience or decide hiring.',
      ),
      const SizedBox(height: 8),
      for (final row in value.required)
        Text('Matched: ${row.skill} — confirmed as ${row.confirmedSkill}'),
      Text(
        'Missing required: ${value.missingRequired.isEmpty ? 'None' : value.missingRequired.join(', ')}',
      ),
      Text(
        'Preferred matches: ${value.preferred.isEmpty ? 'None' : value.preferred.map((row) => row.skill).join(', ')}',
      ),
      Text(
        'Missing preferred: ${value.missingPreferred.isEmpty ? 'None' : value.missingPreferred.join(', ')}',
      ),
      const SizedBox(height: 8),
      Text(
        '${ApplicationMatch.algorithmVersion} · job v${value.jobVersion} · resume v${value.resumeVersion} · skills v${value.skillsVersion} · ${value.parserVersion}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              if (widget.jobId != null)
                TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.resumes),
                  child: const Text('Manage private resumes'),
                ),
              if (widget.jobId != null)
                TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.applications),
                  child: const Text('My applications'),
                ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(message!, semanticsLabel: message),
            ),
          if (stale) const Text('Refresh before another action.'),
          if (widget.jobId != null) ...[
            Text(
              'Choose a confirmed resume',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Review or correct skills in Private resumes before choosing a document here.',
            ),
            for (final resume in resumes)
              ListTile(
                selected: selected?.id == resume.id,
                leading: Icon(
                  selected?.id == resume.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                enabled:
                    !busy && !stale && resume.status == ResumeStatus.confirmed,
                onTap: busy || stale || resume.status != ResumeStatus.confirmed
                    ? null
                    : () => setState(() {
                        selected = resume;
                        match = null;
                      }),
                title: Text(
                  'Resume ${resume.id.substring(0, 8)} · ${resume.extension.toUpperCase()}',
                ),
                subtitle: Text(
                  '${resume.status.name} · skills v${resume.skillsVersion}',
                ),
              ),
            if (!busy && resumes.isEmpty)
              const Text(
                'No resumes yet. Upload and confirm a private resume first.',
              ),
            FilledButton(
              onPressed: busy || stale || selected == null ? null : preview,
              child: const Text('Review skill match'),
            ),
            if (match != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      evidence(match!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: busy || stale ? null : apply,
                        child: const Text('Apply with this resume'),
                      ),
                    ],
                  ),
                ),
              ),
          ] else ...[
            if (!busy && applications.isEmpty)
              Text(
                widget.recruiter
                    ? 'No candidate applications yet.'
                    : 'You have no applications yet.',
              ),
            for (final application in applications)
              Card(
                key: ValueKey(application.id),
                child: ExpansionTile(
                  key: PageStorageKey(application.id),
                  title: Text(application.jobTitle),
                  subtitle: Text(
                    '${application.companyName} · ${application.status}',
                  ),
                  childrenPadding: const EdgeInsets.all(16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.candidateName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Submitted skills: ${application.candidateSkills.join(', ')}',
                    ),
                    if (application.reason.isNotEmpty)
                      Text('Decision reason: ${application.reason}'),
                    evidence(application.match),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!widget.recruiter && application.active)
                          OutlinedButton(
                            onPressed: busy || stale
                                ? null
                                : () => change(application, 'withdrawn'),
                            child: const Text('Withdraw'),
                          ),
                        if (widget.recruiter &&
                            application.status == 'submitted')
                          FilledButton(
                            onPressed: busy || stale
                                ? null
                                : () => change(application, 'shortlisted'),
                            child: const Text('Shortlist'),
                          ),
                        if (widget.recruiter &&
                            application.status == 'shortlisted')
                          FilledButton(
                            onPressed: busy || stale
                                ? null
                                : () => change(application, 'hired'),
                            child: const Text('Record hire'),
                          ),
                        if (widget.recruiter && application.active)
                          OutlinedButton(
                            onPressed: busy || stale
                                ? null
                                : () => change(application, 'rejected'),
                            child: const Text('Reject with reason'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
          if (cursor != null)
            OutlinedButton(
              onPressed: busy || stale ? null : () => refresh(more: true),
              child: const Text('Load more'),
            ),
        ],
      ),
    ),
  );
}
