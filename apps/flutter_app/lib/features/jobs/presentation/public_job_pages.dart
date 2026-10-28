import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/routing/app_routes.dart';
import '../domain/public_jobs_repository.dart';
import 'public_jobs_cubit.dart';

class PublicJobDiscoveryPage extends StatelessWidget {
  const PublicJobDiscoveryPage({super.key, required this.repository});
  final PublicJobsRepository repository;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PublicJobsCubit(repository)..refresh(),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('SmartHire'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.signIn),
            child: const Text('Your account'),
          ),
        ],
      ),
      body: BlocBuilder<PublicJobsCubit, PublicJobsState>(
        builder: (context, state) {
          final cubit = context.read<PublicJobsCubit>();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Find your next opportunity',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Published roles from approved companies. Search by role, company, location or skills.',
                  ),
                  const SizedBox(height: 24),
                  _PublicJobFilters(cubit: cubit, busy: state.loading),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text('${state.items.length} roles loaded'),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.loading ? null : cubit.refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.loading)
                    const Center(child: CircularProgressIndicator()),
                  if (!state.loading &&
                      state.items.isEmpty &&
                      state.error == null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          state.nextCursor == null
                              ? (cubit.search.isNotEmpty ||
                                        cubit.workMode != null ||
                                        cubit.employmentType != null
                                    ? 'No matching published roles. Try another search or reset filters.'
                                    : 'No published roles yet. Check back as companies publish opportunities.')
                              : 'No available roles in this page. Continue to check the next page.',
                        ),
                      ),
                    ),
                  for (final job in state.items)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              job.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(job.company),
                            const SizedBox(height: 8),
                            Text(
                              '${_modeLabel(job.workMode)} · ${job.location.isEmpty ? "Location not specified" : job.location}',
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final skill in job.requiredSkills)
                                  Chip(label: Text(skill)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => Navigator.pushNamed(
                                context,
                                AppRoutes.jobDetails(job.id),
                              ),
                              child: const Text('View role'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        state.error!,
                        key: const Key('public-jobs-error'),
                      ),
                    ),
                  if (state.nextCursor != null)
                    OutlinedButton(
                      onPressed: state.loadingMore ? null : cubit.loadMore,
                      child: Text(
                        state.loadingMore ? 'Loading more…' : 'Load more roles',
                      ),
                    ),
                  if (state.error != null && state.nextCursor == null)
                    FilledButton(
                      onPressed: cubit.refresh,
                      child: const Text('Retry'),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Early preview · Listings may change after moderation.',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class PublicJobDetailsPage extends StatefulWidget {
  const PublicJobDetailsPage({
    super.key,
    required this.repository,
    required this.jobId,
    this.applicationsAvailable = false,
    this.savingAvailable = false,
  });
  final PublicJobsRepository repository;
  final String jobId;
  final bool applicationsAvailable;
  final bool savingAvailable;
  @override
  State<PublicJobDetailsPage> createState() => _PublicJobDetailsPageState();
}

class _PublicJobDetailsPageState extends State<PublicJobDetailsPage> {
  late Future<PublishedJob?> _job;
  @override
  void initState() {
    super.initState();
    _job = _load();
  }

  Future<PublishedJob?> _load() async => widget.repository.detail(widget.jobId);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Role details'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.discover),
          child: const Text('Discover'),
        ),
      ],
    ),
    body: FutureBuilder<PublishedJob?>(
      future: _job,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load this role. Please retry.'),
                FilledButton(
                  onPressed: () => setState(() => _job = _load()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final job = snapshot.data;
        if (job == null) {
          return const Center(child: Text('This role is no longer available.'));
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  job.title,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(job.company),
                const SizedBox(height: 12),
                Text(_modeLabel(job.workMode)),
                if (job.location.isNotEmpty) Text(job.location),
                const SizedBox(height: 28),
                Text(
                  'About the role',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(job.description),
                const SizedBox(height: 24),
                Text(
                  'Required skills',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final skill in job.requiredSkills)
                      Chip(label: Text(skill)),
                  ],
                ),
                if (job.preferredSkills.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Preferred skills',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final skill in job.preferredSkills)
                        Chip(label: Text(skill)),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                if (widget.applicationsAvailable)
                  FilledButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/apply/${job.id}'),
                    child: const Text('Review match and apply'),
                  )
                else
                  const Text('Applications are not available in this preview.'),
                if (widget.savingAvailable)
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/save/${job.id}'),
                    child: const Text('Save role to account'),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

String _modeLabel(PublishedWorkMode mode) => switch (mode) {
  PublishedWorkMode.remote => 'Remote',
  PublishedWorkMode.hybrid => 'Hybrid',
  PublishedWorkMode.onsite => 'On-site',
};

class _PublicJobFilters extends StatefulWidget {
  const _PublicJobFilters({required this.cubit, required this.busy});
  final PublicJobsCubit cubit;
  final bool busy;
  @override
  State<_PublicJobFilters> createState() => _PublicJobFiltersState();
}

class _PublicJobFiltersState extends State<_PublicJobFilters> {
  final query = TextEditingController();
  String? mode, employment;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void apply() {
    widget.cubit.filter(query: query.text, mode: mode, employment: employment);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: query,
        maxLength: 80,
        enabled: !widget.busy,
        decoration: const InputDecoration(
          labelText: 'Search published roles',
          hintText: 'Role, company, city or skill',
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => apply(),
      ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 190,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Work mode'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: mode,
                  hint: const Text('Any work mode'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Any work mode'),
                    ),
                    for (final value in ['remote', 'hybrid', 'onsite'])
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: widget.busy
                      ? null
                      : (value) => setState(() => mode = value),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 190,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Employment'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: employment,
                  hint: const Text('Any employment'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Any employment'),
                    ),
                    for (final value in [
                      'full_time',
                      'part_time',
                      'contract',
                      'internship',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text(value.replaceAll('_', ' ')),
                      ),
                  ],
                  onChanged: widget.busy
                      ? null
                      : (value) => setState(() => employment = value),
                ),
              ),
            ),
          ),
          FilledButton(
            onPressed: widget.busy ? null : apply,
            child: const Text('Search roles'),
          ),
          TextButton(
            onPressed: widget.busy
                ? null
                : () {
                    setState(() {
                      query.clear();
                      mode = null;
                      employment = null;
                    });
                    apply();
                  },
            child: const Text('Reset filters'),
          ),
        ],
      ),
    ],
  );
}
