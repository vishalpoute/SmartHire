import '../../applications/domain/application.dart';
import '../../resumes/domain/resume.dart';

class ModerationJob {
  ModerationJob(Map<String, dynamic> json)
    : id = applicationText(json, 'id', 32),
      title = applicationText(json, 'title', 120),
      description = applicationText(json, 'description', 12000, empty: true),
      status = applicationText(json, 'status', 20),
      version = applicationNumber(json, 'version') {
    if (!resumeHex(id, 32) || !{'published', 'suspended'}.contains(status)) {
      throw const FormatException('Invalid moderation job');
    }
  }
  final String id, title, description, status;
  final int version;
}

class ModerationAudit {
  ModerationAudit(Map<String, dynamic> json)
    : id = applicationText(json, 'id', 32),
      action = applicationText(json, 'action', 80),
      actor = applicationText(json, 'actor_uid', 128),
      reason = applicationText(json, 'reason', 500, empty: true),
      createdAt = applicationText(json, 'created_at', 40) {
    if (!resumeHex(id, 32) || DateTime.tryParse(createdAt) == null) {
      throw const FormatException('Invalid audit');
    }
    final raw = json['job_id'] ?? json['target_uid'] ?? json['target_id'];
    if (raw != null && (raw is! String || raw.length > 128)) {
      throw const FormatException('Invalid target');
    }
    target = raw as String?;
  }
  final String id, action, actor, reason, createdAt;
  late final String? target;
}

class ModerationPageData<T> {
  ModerationPageData(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

abstract interface class ModerationRepository {
  Future<ModerationPageData<ModerationJob>> jobs(
    String status, {
    String? cursor,
  });
  Future<ModerationPageData<ModerationAudit>> audits({String? cursor});
  Future<void> moderate(ModerationJob job, String reason);
  void close();
}
