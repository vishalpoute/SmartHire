import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/jobs/data/demo_job_repository.dart';
import 'package:smarthire/features/jobs/domain/job.dart';
import 'package:smarthire/features/jobs/domain/job_repository.dart';
import 'package:smarthire/features/jobs/presentation/jobs_cubit.dart';

class FailingRepository implements JobRepository {
  @override
  Future<List<Job>> fetchPublishedJobs() async =>
      throw Exception('Unavailable');
}

void main() {
  test('search combines skill, location and work-mode filters', () async {
    final cubit = JobsCubit(DemoJobRepository());
    addTearDown(cubit.close);
    await cubit.load();
    cubit.search('  FLUTTER  ');
    expect(cubit.state.visibleJobs.length, 2);
    cubit.filter(WorkMode.remote);
    expect(cubit.state.visibleJobs.single.id, 'northstar-product');
    cubit.filter(null);
    cubit.search('Pune');
    expect(cubit.state.visibleJobs.single.id, 'orbit-python');
  });
  test('saved-only results update immediately on unsave', () async {
    final cubit = JobsCubit(DemoJobRepository());
    addTearDown(cubit.close);
    await cubit.load();
    cubit.toggleSaved('fern-mobile');
    cubit.showSaved(true);
    expect(cubit.state.visibleJobs.single.id, 'fern-mobile');
    cubit.toggleSaved('fern-mobile');
    expect(cubit.state.visibleJobs, isEmpty);
  });
  test(
    'sorting combines with filters and never reorders repository data',
    () async {
      final cubit = JobsCubit(DemoJobRepository());
      addTearDown(cubit.close);
      await cubit.load();
      final original = cubit.state.jobs.map((job) => job.id).toList();
      final newest = cubit.state.visibleJobs
          .map((job) => job.postedDaysAgo)
          .toList();
      expect(newest, orderedEquals([...newest]..sort()));
      cubit.sortBy(JobSort.title);
      final titles = cubit.state.visibleJobs
          .map((job) => job.title.toLowerCase())
          .toList();
      expect(titles, orderedEquals([...titles]..sort()));
      cubit.toggleSaved('fern-mobile');
      cubit.showSaved(true);
      cubit.search('missing');
      cubit.filter(WorkMode.remote);
      expect(cubit.state.visibleJobs, isEmpty);
      cubit.resetFilters();
      expect(cubit.state.visibleJobs.single.id, 'fern-mobile');
      expect(cubit.state.savedOnly, isTrue);
      expect(cubit.state.sort, JobSort.title);
      expect(cubit.state.jobs.map((job) => job.id), orderedEquals(original));
    },
  );
  test('repository failure yields recoverable failure state', () async {
    final cubit = JobsCubit(FailingRepository());
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.status, JobsStatus.failure);
  });
}
