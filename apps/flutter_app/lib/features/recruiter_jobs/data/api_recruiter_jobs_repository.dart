import 'dart:async';

import 'package:dio/dio.dart';

import '../../profile/data/api_profile_repository.dart';
import '../domain/recruiter_job.dart';

class ApiRecruiterJobsRepository implements RecruiterJobsRepository {
  ApiRecruiterJobsRepository({
    required Uri origin,
    required this.session,
    required this.currentUid,
    HttpClientAdapter? adapter,
  }) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError('Jobs API requires an HTTPS origin.');
    }
    _dio = Dio(
      BaseOptions(
        baseUrl: origin.origin,
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }
  late final Dio _dio;
  final Future<ProfileSession?> Function() session;
  final String? Function() currentUid;

  @override
  Future<OwnedJobsPage> list({String? cursor}) async {
    if (cursor != null) _id(cursor);
    final (json, owner) = await _request(
      'GET',
      '',
      query: {'page_size': 10, 'cursor': ?cursor},
    );
    final page = OwnedJobsPage.fromJson(json, owner);
    if (cursor != null && page.nextCursor == cursor) {
      throw const RecruiterJobFailure('Unable to advance. Reload your jobs.');
    }
    return page;
  }

  @override
  Future<RecruiterJob> load(String id) async {
    _id(id);
    final (json, owner) = await _request('GET', '/$id');
    return RecruiterJob.fromJson(json, owner, expectedId: id);
  }

  @override
  Future<RecruiterJob> save(
    RecruiterJobFields fields, {
    RecruiterJob? previous,
  }) async {
    final error = fields.validate();
    if (error != null) throw RecruiterJobFailure(error);
    if (previous != null) {
      _id(previous.id);
      _version(previous.version);
      if (previous.status != 'draft') {
        throw const RecruiterJobFailure('Only drafts can be edited.');
      }
    }
    final (json, owner) = await _request(
      previous == null ? 'POST' : 'PUT',
      previous == null ? '' : '/${previous.id}',
      body: {
        ...fields.toJson(),
        if (previous != null) 'expected_version': previous.version,
      },
    );
    final saved = RecruiterJob.fromJson(json, owner, expectedId: previous?.id);
    if (saved.status != 'draft' ||
        saved.version != (previous == null ? 1 : previous.version + 1)) {
      throw const RecruiterJobFailure(
        'Unexpected save response. Reload the job.',
      );
    }
    return saved;
  }

  @override
  Future<void> transition(RecruiterJob job, {required bool publish}) async {
    _id(job.id);
    _version(job.version);
    if (job.status != (publish ? 'draft' : 'published')) {
      throw const RecruiterJobFailure(
        'Reload the current job before changing its status.',
      );
    }
    final error = publish ? job.fields.validate(publish: true) : null;
    if (error != null) throw RecruiterJobFailure(error);
    final (json, _) = await _request(
      'POST',
      '/${job.id}/${publish ? 'publish' : 'close'}',
      body: {'expected_version': job.version},
    );
    if (json['id'] != job.id ||
        json['status'] != (publish ? 'published' : 'closed') ||
        json['version'] is! int ||
        json['version'] != job.version + 1) {
      throw const RecruiterJobFailure(
        'Unexpected status response. Reload the job.',
      );
    }
  }

  void _id(String id) {
    if (!validJobId(id)) {
      throw const RecruiterJobFailure('Enter a valid 32-character job ID.');
    }
  }

  void _version(int version) {
    if (version < 1 || version >= 2147483647) {
      throw const RecruiterJobFailure(
        'Reload the current job version before writing.',
      );
    }
  }

  Future<(Map<String, dynamic>, String)> _request(
    String method,
    String path, {
    Map<String, Object>? body,
    Map<String, Object>? query,
  }) async {
    final cancel = CancelToken();
    try {
      final identity = await session().timeout(const Duration(seconds: 10));
      if (identity == null ||
          identity.uid.isEmpty ||
          identity.token.isEmpty ||
          !identity.verified ||
          identity.uid != currentUid()) {
        throw const RecruiterJobFailure(
          'Sign in with your verified account.',
          accessDenied: true,
        );
      }
      final response = await _dio
          .request<Object?>(
            '/api/v1/jobs$path',
            data: body,
            queryParameters: query,
            cancelToken: cancel,
            options: Options(
              method: method,
              contentType: Headers.jsonContentType,
              headers: {'Authorization': 'Bearer ${identity.token}'},
            ),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              cancel.cancel();
              throw TimeoutException('Job request timed out');
            },
          );
      if (identity.uid != currentUid()) {
        throw const RecruiterJobFailure(
          'Your session changed. Please sign in again.',
          accessDenied: true,
        );
      }
      final error = switch (response.statusCode) {
        401 => 'Please sign in again.',
        403 =>
          'Your account or company does not have permission for this action.',
        404 => 'Job unavailable. Check the ID and signed-in account.',
        409 => 'This job changed. Reload it before making another change.',
        422 => 'Check the job fields and publishing requirements.',
        429 => 'Too many requests. Please wait and retry.',
        _ => null,
      };
      if (error != null) {
        throw RecruiterJobFailure(
          error,
          accessDenied:
              response.statusCode == 401 || response.statusCode == 403,
        );
      }
      final expected = method == 'POST' && path.isEmpty ? 201 : 200;
      if (response.statusCode != expected ||
          response.data is! Map<String, dynamic>) {
        throw const RecruiterJobFailure(
          'Job service is unavailable. Reload before retrying.',
        );
      }
      return (response.data! as Map<String, dynamic>, identity.uid);
    } on RecruiterJobFailure {
      rethrow;
    } catch (_) {
      throw const RecruiterJobFailure(
        'Job service is unavailable. Reload before retrying.',
      );
    }
  }

  void close() => _dio.close(force: true);
}
