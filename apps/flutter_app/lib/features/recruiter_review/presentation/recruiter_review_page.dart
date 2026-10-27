import 'package:flutter/material.dart';

import '../../../core/routing/session_gate.dart';
import '../data/api_recruiter_review_repository.dart';
import '../domain/recruiter_review.dart';

class RecruiterReviewPage extends StatelessWidget {
  const RecruiterReviewPage({super.key, this.repositoryFactory});
  final RecruiterReviewRepository Function(String uid)? repositoryFactory;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recruiter reviews')),
    body: SessionGate(
      builder: (context, user) {
        if (!user.emailVerified) {
          return const Center(
            child: Text('Verify your email before reviewing.'),
          );
        }
        if (repositoryFactory == null) {
          return const Center(
            child: Text('Recruiter reviews are not available yet.'),
          );
        }
        return _Queue(
          key: ValueKey(user.uid),
          create: () => repositoryFactory!(user.uid),
        );
      },
    ),
  );
}

class _Queue extends StatefulWidget {
  const _Queue({super.key, required this.create});
  final RecruiterReviewRepository Function() create;
  @override
  State<_Queue> createState() => _QueueState();
}

class _QueueState extends State<_Queue> {
  late final RecruiterReviewRepository repository;
  final reason = TextEditingController();
  List<ReviewSubmission> items = [];
  String? cursor;
  String? message;
  ReviewSubmission? selected;
  bool busy = false;
  bool reloadRequired = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    repository = widget.create();
    load();
  }

  @override
  void dispose() {
    generation++;
    reason.dispose();
    if (repository case final ApiRecruiterReviewRepository api) api.close();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (busy || (more && cursor == null)) return;
    final run = ++generation;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final page = await repository.load(cursor: more ? cursor : null);
      if (!mounted || run != generation) return;
      final merged = [if (more) ...items, ...page.items];
      if (merged.map((item) => item.company.ownerUid).toSet().length !=
          merged.length) {
        throw const ReviewFailure(
          'The queue changed. Reload before reviewing.',
          reloadRequired: true,
        );
      }
      setState(() {
        items = merged;
        cursor = page.nextCursor;
        selected = null;
        reason.clear();
        reloadRequired = false;
      });
    } catch (error) {
      if (!mounted || run != generation) return;
      setState(() {
        // Never continue displaying private records after authorization fails.
        items = [];
        cursor = null;
        selected = null;
        reason.clear();
        reloadRequired = true;
        message = error is ReviewFailure
            ? error.message
            : 'Unable to load reviews. Please retry.';
      });
    } finally {
      if (mounted && run == generation) setState(() => busy = false);
    }
  }

  Future<void> submit(ReviewDecision decision) async {
    final submission = selected;
    if (busy || reloadRequired || submission == null) return;
    try {
      submission.command(decision, reason.text);
    } on ReviewFailure catch (error) {
      setState(() => message = error.message);
      return;
    }
    final run = ++generation;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await repository.review(submission, decision, reason.text);
      if (!mounted || run != generation) return;
      setState(() {
        items = items.where((item) => item != submission).toList();
        selected = null;
        reason.clear();
        message = decision == ReviewDecision.approved
            ? 'Recruiter approved.'
            : 'Submission rejected.';
      });
    } catch (error) {
      if (!mounted || run != generation) return;
      setState(() {
        // A failed write may have committed. Require a fresh queue before any retry.
        reloadRequired = true;
        items = [];
        cursor = null;
        selected = null;
        reason.clear();
        message = error is ReviewFailure
            ? error.message
            : 'Unable to review. Reload the queue.';
      });
    } finally {
      if (mounted && run == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pending company submissions',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Administrator access is checked by the service for every action. '
              'Review the company details and explain your decision.',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: busy ? null : () => load(),
              child: const Text('Reload queue'),
            ),
            if (busy) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(message!)),
              ),
            if (!busy && message == null && items.isEmpty)
              const Text('No pending submissions.'),
            for (final item in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.company.draft.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (item.company.draft.description.isNotEmpty)
                        Text(item.company.draft.description),
                      if (item.company.draft.location.isNotEmpty)
                        Text(item.company.draft.location),
                      if (item.company.draft.website.isNotEmpty)
                        Text(item.company.draft.website),
                      Text('Submitted ${item.company.updatedAt.toLocal()}'),
                      TextButton(
                        onPressed: busy || reloadRequired
                            ? null
                            : () => setState(() {
                                selected = item;
                                reason.clear();
                                message = null;
                              }),
                        child: const Text('Review submission'),
                      ),
                    ],
                  ),
                ),
              ),
            if (selected != null) ...[
              const SizedBox(height: 16),
              Text(
                'Review ${selected!.company.draft.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextField(
                controller: reason,
                enabled: !busy,
                minLines: 2,
                maxLines: 5,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Review reason'),
              ),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    onPressed: busy || reloadRequired
                        ? null
                        : () => submit(ReviewDecision.approved),
                    child: const Text('Approve recruiter'),
                  ),
                  OutlinedButton(
                    onPressed: busy || reloadRequired
                        ? null
                        : () => submit(ReviewDecision.rejected),
                    child: const Text('Reject submission'),
                  ),
                ],
              ),
            ],
            if (cursor != null)
              OutlinedButton(
                onPressed: busy || reloadRequired
                    ? null
                    : () => load(more: true),
                child: const Text('Load more'),
              ),
          ],
        ),
      ),
    ),
  );
}
