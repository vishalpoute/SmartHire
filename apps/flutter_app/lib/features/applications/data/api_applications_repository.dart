import 'dart:async';

import 'package:dio/dio.dart';

import '../../profile/data/api_profile_repository.dart';
import '../../resumes/domain/resume.dart';
import '../domain/application.dart';

class ApiApplicationsRepository implements ApplicationsRepository {
  ApiApplicationsRepository({
    required Uri origin,
    required this.ownerUid,
    required this.session,
    required this.currentUid,
    HttpClientAdapter? adapter,
  }) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        ownerUid.isEmpty) {
      throw ArgumentError('A secure application origin is required');
    }
    client = Dio(
      BaseOptions(
        baseUrl: origin.origin,
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    if (adapter != null) client.httpClientAdapter = adapter;
  }
  late final Dio client;
  final String ownerUid;
  final Future<ProfileSession?> Function() session;
  final String? Function() currentUid;
  final requests = <CancelToken>{};
  bool closed = false;
  void check() {
    if (closed || ownerUid != currentUid()) {
      throw const ApplicationFailure(
        'Your session changed. Sign in again.',
        accessDenied: true,
      );
    }
  }

  void id(String value) {
    if (!resumeHex(value, 32)) {
      throw const ApplicationFailure(
        'This record is unavailable. Refresh and try again.',
      );
    }
  }

  Future<T> request<T>(
    String method,
    String path,
    T Function(Map<String, dynamic>) decode, {
    Map<String, Object>? body,
    Map<String, Object>? query,
    int expected = 200,
  }) async {
    final cancel = CancelToken();
    requests.add(cancel);
    try {
      check();
      final actor = await session().timeout(const Duration(seconds: 10));
      check();
      if (actor == null ||
          actor.uid != ownerUid ||
          !actor.verified ||
          actor.token.isEmpty) {
        throw const ApplicationFailure(
          'Sign in with your verified account.',
          accessDenied: true,
        );
      }
      final response = await client
          .request<Object?>(
            path,
            data: body,
            queryParameters: query,
            cancelToken: cancel,
            options: Options(
              method: method,
              contentType: Headers.jsonContentType,
              headers: {'Authorization': 'Bearer ${actor.token}'},
            ),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              cancel.cancel();
              throw TimeoutException('Application request timed out');
            },
          );
      check();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ApplicationFailure(
          'Check your account permissions and sign in again.',
          accessDenied: true,
        );
      }
      if (response.statusCode == 404 || response.statusCode == 409) {
        final code = response.data is Map
            ? (response.data as Map)['code']
            : null;
        throw ApplicationFailure(switch (code) {
          'already_applied' =>
            'You already applied to this job. Open your applications.',
          'saved_limit' => 'Remove a saved role before saving another.',
          'profile_required' => 'Complete your profile before applying.',
          'skills_confirmation_required' =>
            'Confirm your resume skills before matching.',
          _ => 'This record changed or is unavailable. Refresh before another action.',
        }, reloadRequired: true);
      }
      if (response.statusCode == 429) {
        throw const ApplicationFailure(
          'Too many requests. Wait a minute and retry.',
        );
      }
      if (response.statusCode != expected) {
        throw const ApplicationFailure(
          'Applications are temporarily unavailable. Try again.',
        );
      }
      return decode(applicationMap(response.data));
    } on ApplicationFailure {
      rethrow;
    } catch (_) {
      throw const ApplicationFailure(
        'The request could not finish safely. Refresh and try again.',
      );
    } finally {
      requests.remove(cancel);
    }
  }

  @override
  Future<ResumesPage> resumes({String? cursor}) {
    if (cursor != null) id(cursor);
    return request('GET', '/api/v1/resumes', (json) {
      final page = ResumesPage.fromJson(json);
      if (cursor != null && page.nextCursor == cursor) {
        throw const FormatException('Cursor did not advance');
      }
      return page;
    }, query: {'cursor': ?cursor});
  }

  @override
  Future<ApplicationMatch> match(String jobId, ResumeRecord resume) {
    id(jobId);
    if (resume.status != ResumeStatus.confirmed) {
      throw const ApplicationFailure('Confirm resume skills before matching.');
    }
    return request(
      'POST',
      '/api/v1/jobs/$jobId/match',
      (json) {
        final value = ApplicationMatch(json);
        if (value.jobId != jobId || !value.uses(resume)) {
          throw const FormatException('Mismatched source');
        }
        return value;
      },
      body: {
        'resume_id': resume.id,
        'expected_resume_revision': resume.revision,
      },
    );
  }

  @override
  Future<JobApplication> apply(ApplicationMatch match) {
    id(match.jobId);
    return request(
      'POST',
      '/api/v1/jobs/${match.jobId}/applications',
      (json) {
        final value = JobApplication(json);
        if (value.match.jobId != match.jobId ||
            value.match.resumeId != match.resumeId ||
            value.match.resumeRevision != match.resumeRevision ||
            value.match.jobVersion != match.jobVersion ||
            value.match.digest != match.digest ||
            value.match.skillsVersion != match.skillsVersion) {
          throw const FormatException('Mismatched application');
        }
        return value;
      },
      body: match.command,
      expected: 201,
    );
  }

  @override
  Future<ApplicationsPageData> list({required bool recruiter, String? cursor}) {
    if (cursor != null) id(cursor);
    return request('GET', '/api/v1/applications', (json) {
      final raw = json['items'], next = json['next_cursor'];
      if (raw is! List ||
          raw.length > 10 ||
          (next != null &&
              (next is! String || !resumeHex(next, 32) || next == cursor))) {
        throw const FormatException('Invalid page');
      }
      final items = raw
          .map((row) => JobApplication(applicationMap(row)))
          .toList();
      if (items.map((row) => row.id).toSet().length != items.length) {
        throw const FormatException('Duplicate records');
      }
      return ApplicationsPageData(List.unmodifiable(items), next as String?);
    }, query: {'scope': recruiter ? 'recruiter' : 'seeker', 'cursor': ?cursor});
  }

  @override
  Future<JobApplication> change(
    JobApplication application,
    String status,
    String reason,
  ) {
    id(application.id);
    if (!{'shortlisted', 'rejected', 'hired', 'withdrawn'}.contains(status) ||
        reason.length > 500) {
      throw const ApplicationFailure('Check the action and reason.');
    }
    return request(
      'POST',
      '/api/v1/applications/${application.id}/status',
      (json) {
        final value = JobApplication(json);
        if (value.id != application.id ||
            value.revision != application.revision + 1 ||
            value.status != status ||
            value.match.jobId != application.match.jobId ||
            value.match.resumeId != application.match.resumeId ||
            value.match.digest != application.match.digest ||
            value.match.skillsVersion != application.match.skillsVersion ||
            value.match.jobVersion != application.match.jobVersion) {
          throw const FormatException('Invalid transition');
        }
        return value;
      },
      body: {
        'expected_revision': application.revision,
        'status': status,
        'reason': reason,
      },
    );
  }

  @override
  void close() {
    closed = true;
    for (final request in requests.toList()) {
      request.cancel();
    }
    client.close(force: true);
  }
}
