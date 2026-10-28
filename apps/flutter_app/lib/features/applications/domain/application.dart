import '../../resumes/domain/resume.dart';

class ApplicationFailure implements Exception {
  const ApplicationFailure(
    this.message, {
    this.accessDenied = false,
    this.reloadRequired = false,
  });
  final String message;
  final bool accessDenied, reloadRequired;
}

Map<String, dynamic> applicationMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid record');
  }
  return value;
}

String applicationText(
  Map<String, dynamic> json,
  String key,
  int maximum, {
  bool empty = false,
}) {
  final value = json[key];
  if (value is! String || value.length > maximum || (!empty && value.isEmpty)) {
    throw const FormatException('Invalid text');
  }
  return value;
}

int applicationNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 1 || value > 2147483647) {
    throw const FormatException('Invalid version');
  }
  return value;
}

List<String> applicationSkills(Object? value) {
  if (value is! List || value.length > 30) {
    throw const FormatException('Invalid skills');
  }
  return List.unmodifiable(
    value.map((item) {
      if (item is! String || item.isEmpty || item.length > 40) {
        throw const FormatException('Invalid skill');
      }
      return item;
    }),
  );
}

class MatchEvidence {
  const MatchEvidence(this.skill, this.confirmedSkill);
  final String skill, confirmedSkill;
}

class ApplicationMatch {
  ApplicationMatch(Map<String, dynamic> json)
    : jobId = applicationText(json, 'job_id', 32),
      jobTitle = applicationText(json, 'job_title', 120),
      companyName = applicationText(json, 'company_name', 120),
      jobVersion = applicationNumber(json, 'job_version'),
      resumeId = applicationText(json, 'resume_id', 32),
      resumeVersion = applicationNumber(json, 'resume_version'),
      resumeRevision = applicationNumber(json, 'resume_revision'),
      skillsVersion = applicationNumber(json, 'skills_version'),
      digest = applicationText(json, 'resume_sha256', 64),
      parserVersion = applicationText(json, 'parser_version', 120),
      required = _evidence(json['required_evidence']),
      preferred = _evidence(json['preferred_evidence']),
      missingRequired = applicationSkills(json['missing_required']),
      missingPreferred = applicationSkills(json['missing_preferred']) {
    if (!resumeHex(jobId, 32) ||
        !resumeHex(resumeId, 32) ||
        !resumeHex(digest, 64) ||
        json['algorithm_version'] != algorithmVersion ||
        json['taxonomy_version'] != 'skills-v1') {
      throw const FormatException('Unsupported match');
    }
    final count = required.length + missingRequired.length;
    final expected = count == 0
        ? null
        : ((required.length * 10000 + count ~/ 2) ~/ count) / 100;
    final raw = json['score'];
    if (count > 30 ||
        preferred.length + missingPreferred.length > 30 ||
        (expected == null
            ? (json['status'] != 'unscored' ||
                  raw != null ||
                  json['unscored_reason'] != 'no_required_skills')
            : (json['status'] != 'scored' ||
                  raw is! num ||
                  !raw.isFinite ||
                  raw != expected ||
                  json['unscored_reason'] != null))) {
      throw const FormatException('Invalid score');
    }
    score = expected;
  }
  static const algorithmVersion = 'skill-coverage-v1';
  final String jobId, jobTitle, companyName, resumeId, digest, parserVersion;
  final int jobVersion, resumeVersion, resumeRevision, skillsVersion;
  final List<MatchEvidence> required, preferred;
  final List<String> missingRequired, missingPreferred;
  late final double? score;
  static List<MatchEvidence> _evidence(Object? value) {
    if (value is! List || value.length > 30) {
      throw const FormatException('Invalid evidence');
    }
    return List.unmodifiable(
      value.map((item) {
        final row = applicationMap(item);
        return MatchEvidence(
          applicationText(row, 'skill', 40),
          applicationText(row, 'confirmed_skill', 40),
        );
      }),
    );
  }

  bool uses(ResumeRecord resume) =>
      resumeId == resume.id &&
      resumeRevision == resume.revision &&
      resumeVersion == resume.version &&
      digest == resume.digest &&
      skillsVersion == resume.skillsVersion &&
      parserVersion == resume.parserVersion;
  Map<String, Object> get command => {
    'resume_id': resumeId,
    'expected_resume_revision': resumeRevision,
    'expected_job_version': jobVersion,
  };
}

class JobApplication {
  JobApplication(Map<String, dynamic> json)
    : id = applicationText(json, 'id', 32),
      revision = applicationNumber(json, 'revision'),
      status = applicationText(json, 'status', 20),
      reason = applicationText(json, 'reason', 500, empty: true),
      match = ApplicationMatch(applicationMap(json['match'])),
      jobTitle = applicationText(applicationMap(json['job']), 'title', 120),
      companyName = applicationText(
        applicationMap(json['job']),
        'company_name',
        120,
      ),
      candidateName = applicationText(
        applicationMap(json['candidate']),
        'display_name',
        80,
      ),
      candidateSkills = applicationSkills(
        applicationMap(json['candidate'])['skills'],
      ) {
    final job = applicationMap(json['job']);
    if (!resumeHex(id, 32) ||
        !{
          'submitted',
          'shortlisted',
          'rejected',
          'hired',
          'withdrawn',
        }.contains(status) ||
        job['id'] != match.jobId ||
        job['version'] != match.jobVersion) {
      throw const FormatException('Invalid application');
    }
    for (final key in ['submitted_at', 'updated_at']) {
      final raw = applicationText(json, key, 40);
      if (DateTime.tryParse(raw) == null ||
          !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(raw)) {
        throw const FormatException('Invalid date');
      }
    }
  }
  final String id, status, reason, jobTitle, companyName, candidateName;
  final int revision;
  final ApplicationMatch match;
  final List<String> candidateSkills;
  bool get active => status == 'submitted' || status == 'shortlisted';
}

class ApplicationsPageData {
  ApplicationsPageData(this.items, this.nextCursor);
  final List<JobApplication> items;
  final String? nextCursor;
}

abstract interface class ApplicationsRepository {
  Future<ResumesPage> resumes({String? cursor});
  Future<ApplicationMatch> match(String jobId, ResumeRecord resume);
  Future<JobApplication> apply(ApplicationMatch match);
  Future<ApplicationsPageData> list({required bool recruiter, String? cursor});
  Future<JobApplication> change(
    JobApplication application,
    String status,
    String reason,
  );
  Future<void> delete(JobApplication application);
  void close();
}
