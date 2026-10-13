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
  test('repository failure yields recoverable failure state', () async {
    final cubit = JobsCubit(FailingRepository());
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.status, JobsStatus.failure);
  });
}
