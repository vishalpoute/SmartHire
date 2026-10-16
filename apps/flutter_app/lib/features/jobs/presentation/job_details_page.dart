import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/routing/app_routes.dart';
import '../domain/job.dart';
import 'jobs_cubit.dart';

class JobDetailsPage extends StatelessWidget {
  const JobDetailsPage({super.key, required this.jobId});
  final String jobId;

  void _back(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (route) => route.isFirst);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.discover);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Role details'),
      leading: IconButton(
        tooltip: 'Back to jobs',
        onPressed: () => _back(context),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: BlocBuilder<JobsCubit, JobsState>(
      builder: (context, state) {
        if (state.status == JobsStatus.initial ||
            state.status == JobsStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == JobsStatus.failure) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('We could not load this role.'),
                TextButton(
                  onPressed: context.read<JobsCubit>().load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        Job? found;
        for (final job in state.jobs) {
          if (job.id == jobId) found = job;
        }
        if (found == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Role unavailable',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This listing could not be found. Explore the available sample jobs.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _back(context),
                    child: const Text('Explore jobs'),
                  ),
                ],
              ),
            ),
          );
        }
        final job = found;
        final saved = state.savedIds.contains(job.id);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.company),
                      const SizedBox(height: 8),
                      Text(
                        job.title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      Text('${job.location} / ${job.mode.label} / Full-time'),
                      const SizedBox(height: 8),
                      Text(
                        job.salary,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () =>
                                context.read<JobsCubit>().toggleSaved(job.id),
                            icon: Icon(
                              saved ? Icons.bookmark : Icons.bookmark_border,
                            ),
                            label: Text(saved ? 'Saved role' : 'Save role'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              // Hash links work on static hosts without server-side route rewrites.
                              final webBase =
                                  Uri.base.scheme == 'http' ||
                                      Uri.base.scheme == 'https'
                                  ? Uri.base
                                  : Uri.parse(
                                      'https://smarthire-vishalpoute.antideploy.app/',
                                    );
                              final link = webBase
                                  .replace(
                                    fragment: AppRoutes.jobDetails(job.id),
                                  )
                                  .toString();
                              try {
                                await Clipboard.setData(
                                  ClipboardData(text: link),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Role link copied'),
                                  ),
                                );
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not copy the link. Please try again.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.link),
                            label: const Text('Copy link'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'About the role',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(job.description),
                      const SizedBox(height: 24),
                      Text(
                        'Skills',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final skill in job.skills)
                            Chip(label: Text(skill)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Fictional sample listing. Applications are not available in this preview. Saved roles reset when you restart.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
