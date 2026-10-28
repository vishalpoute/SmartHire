import '../../applications/domain/application.dart';
import '../../resumes/domain/resume.dart';

class SavedJob {
  SavedJob(Map<String, dynamic> json)
    : id = applicationText(json, 'id', 32),
      jobId = applicationText(json, 'job_id', 32) {
    if (!resumeHex(id, 32) || !resumeHex(jobId, 32)) {
      throw const FormatException('Invalid bookmark');
    }
    final date = applicationText(json, 'saved_at', 40);
    if (DateTime.tryParse(date) == null ||
        !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(date)) {
      throw const FormatException('Invalid saved date');
    }
    if (json['job'] != null) {
      final job = applicationMap(json['job']);
      if (job['id'] != jobId) {
        throw const FormatException('Mismatched bookmark');
      }
      title = applicationText(job, 'title', 120);
      company = applicationText(job, 'company_name', 120);
    }
  }
  final String id, jobId;
  String? title, company;
}

class SavedJobsData {
  SavedJobsData(this.items, this.nextCursor);
  final List<SavedJob> items;
  final String? nextCursor;
}

abstract interface class SavedJobsRepository {
  Future<SavedJobsData> saved({String? cursor});
  Future<SavedJob> save(String jobId);
  Future<void> remove(String jobId);
  void close();
}
