import '../../applications/data/api_applications_repository.dart';
import '../../applications/domain/application.dart';
import '../../resumes/domain/resume.dart';
import '../domain/saved_job.dart';

class ApiSavedJobsRepository extends ApiApplicationsRepository
    implements SavedJobsRepository {
  ApiSavedJobsRepository({
    required super.origin,
    required super.ownerUid,
    required super.session,
    required super.currentUid,
    super.adapter,
  });
  @override
  Future<SavedJobsData> saved({String? cursor}) {
    if (cursor != null) id(cursor);
    return request('GET', '/api/v1/saved-jobs', (json) {
      final raw = json['items'], next = json['next_cursor'];
      if (raw is! List ||
          raw.length > 10 ||
          (next != null &&
              (next is! String || !resumeHex(next, 32) || next == cursor))) {
        throw const FormatException('Invalid bookmarks');
      }
      final items = raw.map((row) => SavedJob(applicationMap(row))).toList();
      if (items.map((row) => row.jobId).toSet().length != items.length ||
          items.map((row) => row.id).toSet().length != items.length) {
        throw const FormatException('Duplicate bookmark');
      }
      return SavedJobsData(List.unmodifiable(items), next as String?);
    }, query: {'cursor': ?cursor});
  }

  @override
  Future<SavedJob> save(String jobId) {
    id(jobId);
    return request('POST', '/api/v1/saved-jobs/$jobId', (json) {
      final value = SavedJob(json);
      if (value.jobId != jobId) {
        throw const FormatException('Mismatched bookmark');
      }
      return value;
    }, expected: 201);
  }

  @override
  Future<void> remove(String jobId) async {
    id(jobId);
    await request('DELETE', '/api/v1/saved-jobs/$jobId', (json) {
      if (json['job_id'] != jobId || json['status'] != 'removed') {
        throw const FormatException('Invalid removal');
      }
      return true;
    });
  }
}
