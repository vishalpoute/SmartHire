import 'dart:async';
import 'dart:typed_data';

import 'package:smarthire/features/resumes/domain/resume.dart';

PickedResume fixtureResume() => PickedResume(
  name: 'fixture.pdf',
  extension: 'pdf',
  bytes: Uint8List.fromList([1, 2, 3, 4]),
);
Map<String, dynamic> resumeJson({
  String? id,
  String status = 'parsed',
  int revision = 4,
  int skillsVersion = 0,
  List<String>? confirmedSkills,
  String? errorCode,
}) {
  final file = fixtureResume();
  return {
    'id': id ?? resumeIdFor('one', 'a' * 32),
    'version': 1,
    'revision': revision,
    'extension': file.extension,
    'size': file.bytes.length,
    'sha256': file.digest,
    'parse_status': status,
    'extracted_skills': ['parsed', 'confirmed'].contains(status)
        ? ['Flutter', 'Python']
        : <String>[],
    'confirmed_skills': confirmedSkills,
    'skills_version': skillsVersion,
    'parser_version': 'text-v2-pypdf6.21.2-docx1.2.0',
    'taxonomy_version': 'skills-v1',
    'error_code': errorCode,
    'created_at': '2026-10-28T00:00:00Z',
    'updated_at': '2026-10-28T00:00:00Z',
  };
}

ResumeRecord fixtureRecord({
  String? id,
  String status = 'parsed',
  int revision = 4,
  int skillsVersion = 0,
  List<String>? confirmedSkills,
  String? errorCode,
}) => ResumeRecord.fromJson(
  resumeJson(
    id: id,
    status: status,
    revision: revision,
    skillsVersion: skillsVersion,
    confirmedSkills: confirmedSkills,
    errorCode: errorCode,
  ),
);

class ResumesFake implements ResumeRepository {
  List<ResumeRecord> items = [];
  final nonces = <String>[];
  int confirmations = 0, deletes = 0, reads = 0, retries = 0;
  bool failUpload = false, staleConfirm = false, deletionPending = false;
  Completer<ResumeRecord>? pendingUpload;
  void Function(int, int)? progress;
  @override
  Future<ResumesPage> list({String? cursor}) async {
    reads++;
    return ResumesPage(items, null);
  }

  @override
  Future<ResumeRecord> load(String id) async =>
      items.firstWhere((r) => r.id == id);
  @override
  Future<ResumeRecord> upload(
    PickedResume file,
    String uploadId,
    void Function(int, int) callback,
  ) async {
    nonces.add(uploadId);
    progress = callback;
    callback(2, 4);
    if (failUpload) {
      throw const ResumeFailure(
        'Private upload interrupted. Please retry the same file.',
      );
    }
    final record =
        await (pendingUpload?.future ??
            Future.value(
              fixtureRecord(
                id: resumeIdFor('one', uploadId),
                status: 'queued',
                revision: 2,
              ),
            ));
    items = [record];
    return record;
  }

  @override
  Future<ResumeRecord> confirm(ResumeRecord record, List<String> skills) async {
    confirmations++;
    if (staleConfirm) {
      throw const ResumeFailure(
        'This resume changed. Refresh before another action.',
        reloadRequired: true,
      );
    }
    final saved = fixtureRecord(
      id: record.id,
      status: 'confirmed',
      revision: record.revision + 1,
      skillsVersion: record.skillsVersion + 1,
      confirmedSkills: skills,
    );
    items = [saved];
    return saved;
  }

  @override
  Future<ResumeRecord> retry(ResumeRecord record) async {
    retries++;
    final saved = fixtureRecord(
      id: record.id,
      status: 'queued',
      revision: record.revision + 1,
    );
    items = [saved];
    return saved;
  }

  @override
  Future<bool> delete(ResumeRecord record) async {
    deletes++;
    items = deletionPending
        ? [
            fixtureRecord(
              id: record.id,
              status: 'deleting',
              revision: record.revision + 1,
            ),
          ]
        : [];
    return !deletionPending;
  }
}
