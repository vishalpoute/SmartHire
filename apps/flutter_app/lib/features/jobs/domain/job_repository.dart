import 'job.dart';

abstract interface class JobRepository {
  Future<List<Job>> fetchPublishedJobs();
}
