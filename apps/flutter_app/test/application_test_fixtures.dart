import 'dart:async';

import 'package:smarthire/features/applications/domain/application.dart';
import 'package:smarthire/features/resumes/domain/resume.dart';

import 'resume_test_fixtures.dart';

const applicationJobId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
ResumeRecord confirmedResume() => fixtureRecord(
  status: 'confirmed',
  skillsVersion: 1,
  confirmedSkills: ['Flutter'],
);
Map<String, dynamic> matchJson() {
  final resume = confirmedResume();
  return {
    'algorithm_version': 'skill-coverage-v1',
    'taxonomy_version': 'skills-v1',
    'job_id': applicationJobId,
    'job_title': 'Fixture role',
    'company_name': 'Fixture company',
    'job_version': 2,
    'resume_id': resume.id,
    'resume_version': resume.version,
    'resume_revision': resume.revision,
    'resume_sha256': resume.digest,
    'skills_version': 1,
    'parser_version': resume.parserVersion,
    'status': 'scored',
    'score': 50.0,
    'unscored_reason': null,
    'required_evidence': [
      {'skill': 'Flutter', 'confirmed_skill': 'Flutter'},
    ],
    'preferred_evidence': <Object>[],
    'missing_required': ['SQL'],
    'missing_preferred': <String>[],
  };
}

Map<String, dynamic> applicationJson({
  String status = 'submitted',
  int revision = 1,
}) => {
  'id': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'revision': revision,
  'status': status,
  'reason': '',
  'job': {
    'id': applicationJobId,
    'version': 2,
    'title': 'Fixture role',
    'company_name': 'Fixture company',
  },
  'candidate': {
    'display_name': 'Fixture candidate',
    'skills': ['Flutter'],
  },
  'match': matchJson(),
  'submitted_at': '2026-10-28T00:00:00Z',
  'updated_at': '2026-10-28T00:00:00Z',
};

class ApplicationsFake implements ApplicationsRepository {
  int matches = 0, submissions = 0, changes = 0;
  bool closed = false, stale = false;
  List<JobApplication> items = [];
  Completer<ApplicationMatch>? pending;
  @override
  Future<ResumesPage> resumes({String? cursor}) async =>
      ResumesPage([confirmedResume(), fixtureRecord(id: 'c' * 32)], null);
  @override
  Future<ApplicationMatch> match(String jobId, ResumeRecord resume) async {
    matches++;
    return await (pending?.future ??
        Future.value(ApplicationMatch(matchJson())));
  }

  @override
  Future<JobApplication> apply(ApplicationMatch match) async {
    submissions++;
    return JobApplication(applicationJson());
  }

  @override
  Future<ApplicationsPageData> list({
    required bool recruiter,
    String? cursor,
  }) async => ApplicationsPageData(items, null);
  @override
  Future<JobApplication> change(
    JobApplication application,
    String status,
    String reason,
  ) async {
    changes++;
    if (stale) {
      throw const ApplicationFailure(
        'Application changed. Refresh before retrying.',
        reloadRequired: true,
      );
    }
    final json = applicationJson(
      status: status,
      revision: application.revision + 1,
    )..['reason'] = reason;
    final value = JobApplication(json);
    items = [value];
    return value;
  }

  @override
  void close() {
    closed = true;
  }
}
