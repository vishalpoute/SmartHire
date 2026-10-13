import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/routing/app_routes.dart';
import '../domain/job.dart';
import 'jobs_cubit.dart';
import 'widgets/job_card.dart';

class JobDiscoveryPage extends StatelessWidget {
  const JobDiscoveryPage({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1000;
      return Scaffold(
        bottomNavigationBar: desktop
            ? null
            : BlocBuilder<JobsCubit, JobsState>(
                builder: (context, state) => NavigationBar(
                  selectedIndex: state.savedOnly ? 1 : 0,
                  onDestinationSelected: (index) =>
                      context.read<JobsCubit>().showSaved(index == 1),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.work_outline),
                      label: 'Discover',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.bookmark_border),
                      label: 'Saved',
                    ),
                  ],
                ),
              ),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (desktop) const _Sidebar(),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 40 : 20,
                          28,
                          desktop ? 40 : 20,
                          0,
                        ),
                        child: const _Header(),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.all(desktop ? 40 : 20),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _Introduction(),
                                const SizedBox(height: 28),
                                TextField(
                                  key: const Key('job-search'),
                                  onChanged: context.read<JobsCubit>().search,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Job title, skill, company or city',
                                    prefixIcon: Icon(Icons.search),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const _Filters(),
                                const SizedBox(height: 26),
                                const _Results(),
                                const SizedBox(height: 30),
                                const Text(
                                  'Development preview · Fictional jobs · Saved jobs reset when you restart',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();
  @override
  Widget build(BuildContext context) => Container(
    width: 238,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: AppTheme.line)),
    ),
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Brand(),
        const SizedBox(height: 56),
        const Text(
          'YOUR WORKSPACE',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        BlocBuilder<JobsCubit, JobsState>(
          builder: (context, state) => Column(
            children: [
              _NavItem(
                icon: Icons.explore_outlined,
                label: 'Discover jobs',
                selected: !state.savedOnly,
                onTap: () => context.read<JobsCubit>().showSaved(false),
              ),
              const SizedBox(height: 8),
              _NavItem(
                icon: Icons.bookmark_border,
                label: 'Saved jobs',
                selected: state.savedOnly,
                onTap: () => context.read<JobsCubit>().showSaved(true),
              ),
            ],
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.canvas,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_outlined, color: AppTheme.ink),
              SizedBox(height: 12),
              Text(
                'A clearer next step',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              SizedBox(height: 6),
              Text('Resume insights and skill matching are coming next.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'SmartHire  /  Early preview',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selected: selected,
      selectedTileColor: const Color(0xFFE9F0E9),
      leading: Icon(icon, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: onTap,
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.bubble_chart, color: AppTheme.ink, size: 28),
      SizedBox(width: 8),
      Flexible(
        child: Text(
          'smarthire',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -.8,
            color: AppTheme.ink,
          ),
        ),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (MediaQuery.sizeOf(context).width < 1000)
        const Expanded(
          child: Align(alignment: Alignment.centerLeft, child: _Brand()),
        )
      else
        const Text(
          'WORKSPACE  /  JOB DISCOVERY',
          style: TextStyle(fontSize: 11, letterSpacing: 1.3),
        ),
      if (MediaQuery.sizeOf(context).width >= 1000) const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EBD9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Preview',
          style: TextStyle(fontSize: 12, color: Color(0xFF756336)),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Sign in',
        onPressed: () => Navigator.pushNamed(context, AppRoutes.signIn),
        icon: const Icon(Icons.person_outline),
      ),
    ],
  );
}

class _Introduction extends StatelessWidget {
  const _Introduction();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF0E7),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MAKE YOUR NEXT MOVE',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Good work starts\nwith the right fit.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Explore opportunities that put your skills to work.\nA little less searching. A little more possibility.',
        ),
      ],
    ),
  );
}

class _Filters extends StatelessWidget {
  const _Filters();
  @override
  Widget build(BuildContext context) => BlocBuilder<JobsCubit, JobsState>(
    builder: (context, state) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('All work modes'),
          selected: state.mode == null,
          onSelected: (_) => context.read<JobsCubit>().filter(null),
        ),
        for (final mode in WorkMode.values)
          ChoiceChip(
            label: Text(mode.label),
            selected: state.mode == mode,
            onSelected: (selected) =>
                context.read<JobsCubit>().filter(selected ? mode : null),
          ),
      ],
    ),
  );
}

class _Results extends StatelessWidget {
  const _Results();
  @override
  Widget build(BuildContext context) => BlocBuilder<JobsCubit, JobsState>(
    builder: (context, state) {
      if (state.status == JobsStatus.initial ||
          state.status == JobsStatus.loading) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ),
        );
      }
      if (state.status == JobsStatus.failure) {
        return Column(
          children: [
            const Text('We couldn’t load jobs. Please try again.'),
            TextButton(
              onPressed: context.read<JobsCubit>().load,
              child: const Text('Retry'),
            ),
          ],
        );
      }
      final jobs = state.visibleJobs;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.savedOnly
                ? 'Your saved opportunities'
                : 'Discover opportunities',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            '${jobs.length} ${jobs.length == 1 ? 'role' : 'roles'} · Sample listings',
          ),
          const SizedBox(height: 20),
          if (jobs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                state.savedOnly
                    ? 'No saved jobs match these filters. Save a role from Discover.'
                    : 'No roles found. Try another skill or work mode.',
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 740 ? 2 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final job in jobs)
                    SizedBox(
                      width: width,
                      child: JobCard(
                        job: job,
                        saved: state.savedIds.contains(job.id),
                        onSave: () =>
                            context.read<JobsCubit>().toggleSaved(job.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
    },
  );
}
