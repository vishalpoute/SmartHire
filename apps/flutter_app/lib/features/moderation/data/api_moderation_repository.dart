import '../../applications/data/api_applications_repository.dart';
import '../../applications/domain/application.dart';
import '../../resumes/domain/resume.dart';
import '../domain/moderation.dart';

class ApiModerationRepository extends ApiApplicationsRepository
    implements ModerationRepository {
  ApiModerationRepository({
    required super.origin,
    required super.ownerUid,
    required super.session,
    required super.currentUid,
    super.adapter,
  });
  ModerationPageData<T> page<T>(
    Map<String, dynamic> json,
    int limit,
    String? cursor,
    T Function(Map<String, dynamic>) decode,
  ) {
    final raw = json['items'], next = json['next_cursor'];
    if (raw is! List ||
        raw.length > limit ||
        (next != null &&
            (next is! String ||
                !resumeHex(next, 32) ||
                (cursor != null && next.compareTo(cursor) <= 0)))) {
      throw const FormatException('Invalid admin page');
    }
    final ids = raw.map((row) => applicationMap(row)['id']).toSet();
    if (ids.length != raw.length) {
      throw const FormatException('Duplicate admin records');
    }
    return ModerationPageData(
      List.unmodifiable(raw.map((row) => decode(applicationMap(row)))),
      next as String?,
    );
  }

  @override
  Future<ModerationPageData<ModerationJob>> jobs(
    String status, {
    String? cursor,
  }) {
    if (!{'published', 'suspended'}.contains(status)) {
      throw const ApplicationFailure('Choose a moderation view.');
    }
    if (cursor != null) id(cursor);
    return request('GET', '/api/v1/admin/jobs', (json) {
      final value = page(json, 10, cursor, ModerationJob.new);
      if (value.items.any((row) => row.status != status)) {
        throw const FormatException('Mismatched job state');
      }
      return value;
    }, query: {'status': status, 'cursor': ?cursor});
  }

  @override
  Future<ModerationPageData<ModerationAudit>> audits({String? cursor}) {
    if (cursor != null) id(cursor);
    return request(
      'GET',
      '/api/v1/admin/audit-events',
      (json) => page(json, 20, cursor, ModerationAudit.new),
      query: {'cursor': ?cursor},
    );
  }

  @override
  Future<void> moderate(ModerationJob job, String reason) async {
    id(job.id);
    if (reason.trim().length < 3 || reason.length > 500) {
      throw const ApplicationFailure(
        'Enter a reason between 3 and 500 characters.',
      );
    }
    final suspended = job.status == 'published';
    await request(
      'POST',
      '/api/v1/admin/jobs/${job.id}/moderation',
      (json) {
        if (json['id'] != job.id ||
            json['version'] != job.version + 1 ||
            json['status'] != (suspended ? 'suspended' : 'draft')) {
          throw const FormatException('Invalid moderation receipt');
        }
        return true;
      },
      body: {
        'expected_version': job.version,
        'action': suspended ? 'suspend' : 'restore_draft',
        'reason': reason.trim(),
      },
    );
  }
}
