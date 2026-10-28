import 'dart:async';

import 'package:dio/dio.dart';

import '../../profile/data/api_profile_repository.dart';
import '../domain/resume.dart';

class ApiResumeRepository implements ResumeRepository {
  ApiResumeRepository({
    required Uri origin,
    required this.storageOrigin,
    required this.ownerUid,
    required this.session,
    required this.currentUid,
    HttpClientAdapter? apiAdapter,
    HttpClientAdapter? uploadAdapter,
  }) {
    for (final uri in [origin, storageOrigin]) {
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/')) {
        throw ArgumentError('Resume services require HTTPS origins.');
      }
    }
    if (ownerUid.isEmpty) throw ArgumentError('Missing resume owner.');
    _apiClient = Dio(
      BaseOptions(
        baseUrl: origin.origin,
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    _uploadClient = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    if (apiAdapter != null) _apiClient.httpClientAdapter = apiAdapter;
    if (uploadAdapter != null) _uploadClient.httpClientAdapter = uploadAdapter;
  }
  late final Dio _apiClient, _uploadClient;
  final Uri storageOrigin;
  final String ownerUid;
  final Future<ProfileSession?> Function() session;
  final String? Function() currentUid;
  final _requests = <CancelToken>{};
  bool _closed = false;

  void _check() {
    if (_closed || ownerUid != currentUid()) {
      throw const ResumeFailure(
        'Your session changed. Please sign in again.',
        accessDenied: true,
      );
    }
  }

  void _id(String id) {
    if (!resumeHex(id, 32)) {
      throw const ResumeFailure('Invalid resume. Refresh your resumes.');
    }
  }

  @override
  Future<ResumesPage> list({String? cursor}) async {
    if (cursor != null) _id(cursor);
    final page = ResumesPage.fromJson(
      await _request('GET', '', query: {'cursor': ?cursor}),
    );
    if (cursor != null && page.nextCursor == cursor) {
      throw const ResumeFailure('Unable to advance. Refresh your resumes.');
    }
    return page;
  }

  @override
  Future<ResumeRecord> load(String id) async {
    _id(id);
    return ResumeRecord.fromJson(await _request('GET', '/$id'), expectedId: id);
  }

  @override
  Future<ResumeRecord> upload(
    PickedResume file,
    String uploadId,
    void Function(int, int) progress,
  ) async {
    if (!resumeHex(uploadId, 32)) {
      throw const ResumeFailure('Choose the file again to start a new upload.');
    }
    final expectedId = resumeIdFor(ownerUid, uploadId);
    final receipt = await _request(
      'POST',
      '',
      expectedStatus: 201,
      body: {
        'upload_id': uploadId,
        'extension': file.extension,
        'size': file.bytes.length,
        'sha256': file.digest,
      },
    );
    if (receipt['resume'] is! Map<String, dynamic>) {
      throw const ResumeFailure(
        'Unexpected upload response. Refresh your resumes.',
      );
    }
    final record = ResumeRecord.fromJson(
      receipt['resume'] as Map<String, dynamic>,
      expectedId: expectedId,
    );
    if (record.digest != file.digest ||
        record.size != file.bytes.length ||
        record.extension != file.extension) {
      throw const ResumeFailure(
        'The upload response did not match this file. Refresh your resumes.',
      );
    }
    if (record.status != ResumeStatus.uploading) return record;
    final rawUrl = receipt['upload_url'],
        rawHeaders = receipt['upload_headers'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    final headers = <String, String>{};
    if (rawHeaders is Map<String, dynamic>) {
      for (final entry in rawHeaders.entries) {
        if (entry.value is! String) {
          throw const ResumeFailure(
            'Unexpected upload instructions. Please refresh.',
          );
        }
        headers[entry.key.toLowerCase()] = entry.value as String;
      }
    }
    final mime = file.extension == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    final signedHeaders =
        url?.queryParameters['X-Amz-SignedHeaders']?.split(';').toSet() ?? {};
    if (url == null ||
        url.scheme != 'https' ||
        url.origin != storageOrigin.origin ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        !url.path.endsWith(
          '/${resumeOwnerHash(ownerUid)}/$expectedId/source.${file.extension}',
        ) ||
        receipt['expires_in'] is! int ||
        receipt['expires_in'] != 60 ||
        url.queryParameters['X-Amz-Expires'] != '60' ||
        !signedHeaders.containsAll({
          'content-length',
          'content-type',
          'host',
          'if-none-match',
          'x-amz-meta-sha256',
        }) ||
        headers.keys.toSet().difference({
          'content-type',
          'if-none-match',
          'x-amz-meta-sha256',
        }).isNotEmpty ||
        headers['content-type'] != mime ||
        headers['if-none-match'] != '*' ||
        headers['x-amz-meta-sha256'] != file.digest) {
      throw const ResumeFailure(
        'Private upload instructions are invalid. Please refresh your resumes.',
      );
    }
    final cancel = CancelToken();
    _requests.add(cancel);
    try {
      _check();
      final response = await _uploadClient
          .put<Object?>(
            url.toString(),
            data: file.bytes,
            cancelToken: cancel,
            onSendProgress: progress,
            options: Options(
              headers: headers,
              responseType: ResponseType.bytes,
            ),
          )
          .timeout(
            const Duration(seconds: 90),
            onTimeout: () {
              cancel.cancel();
              throw TimeoutException('Private upload timed out');
            },
          );
      _check();
      if (![200, 201, 204, 412].contains(response.statusCode)) {
        throw const ResumeFailure(
          'The private upload did not finish. Retry the same file or choose it again.',
        );
      }
    } on ResumeFailure {
      rethrow;
    } catch (_) {
      throw const ResumeFailure(
        'The private upload did not finish. Retry the same file.',
      );
    } finally {
      _requests.remove(cancel);
    }
    return ResumeRecord.fromJson(
      await _request(
        'POST',
        '/$expectedId/finalize',
        body: {'expected_revision': record.revision},
      ),
      expectedId: expectedId,
    );
  }

  @override
  Future<ResumeRecord> confirm(ResumeRecord record, List<String> skills) async {
    _id(record.id);
    if (![
          ResumeStatus.parsed,
          ResumeStatus.confirmed,
        ].contains(record.status) ||
        skills.length > 30 ||
        skills.any(
          (s) =>
              s.trim().isEmpty ||
              s.trim().length > 40 ||
              s.runes.any((r) => r < 32 || r == 127),
        )) {
      throw const ResumeFailure(
        'Use up to 30 skills, each 1–40 characters, after text extraction succeeds.',
      );
    }
    final saved = ResumeRecord.fromJson(
      await _request(
        'PUT',
        '/${record.id}/skills',
        body: {
          'expected_revision': record.revision,
          'skills': skills.map((s) => s.trim()).toList(),
        },
      ),
      expectedId: record.id,
    );
    _sameSource(record, saved);
    if (saved.status != ResumeStatus.confirmed ||
        saved.skillsVersion != record.skillsVersion + 1 ||
        saved.revision != record.revision + 1) {
      throw const ResumeFailure(
        'Unexpected skill response. Refresh your resumes.',
      );
    }
    return saved;
  }

  @override
  Future<ResumeRecord> retry(ResumeRecord record) async {
    _id(record.id);
    final saved = ResumeRecord.fromJson(
      await _request(
        'POST',
        '/${record.id}/retry',
        body: {'expected_revision': record.revision},
      ),
      expectedId: record.id,
    );
    _sameSource(record, saved);
    if (saved.status != ResumeStatus.queued ||
        saved.revision != record.revision + 1) {
      throw const ResumeFailure(
        'Unexpected processing response. Refresh your resumes.',
        reloadRequired: true,
      );
    }
    return saved;
  }

  void _sameSource(ResumeRecord before, ResumeRecord after) {
    if (before.id != after.id ||
        before.version != after.version ||
        before.digest != after.digest ||
        before.size != after.size ||
        before.extension != after.extension) {
      throw const ResumeFailure(
        'The resume source changed. Refresh before another action.',
        reloadRequired: true,
      );
    }
  }

  @override
  Future<bool> delete(ResumeRecord record) async {
    _id(record.id);
    final json = await _request(
      'POST',
      '/${record.id}/delete',
      body: {'expected_revision': record.revision},
    );
    if (json['id'] != record.id ||
        !['deleted', 'deleting'].contains(json['status'])) {
      throw const ResumeFailure(
        'Unexpected deletion response. Refresh before retrying.',
      );
    }
    return json['status'] == 'deleted';
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object>? body,
    Map<String, Object>? query,
    int expectedStatus = 200,
  }) async {
    final cancel = CancelToken();
    _requests.add(cancel);
    try {
      _check();
      final identity = await session().timeout(const Duration(seconds: 10));
      _check();
      if (identity == null ||
          identity.uid != ownerUid ||
          identity.token.isEmpty ||
          !identity.verified) {
        throw const ResumeFailure(
          'Please sign in with your verified account.',
          accessDenied: true,
        );
      }
      final response = await _apiClient
          .request<Object?>(
            '/api/v1/resumes$path',
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
              throw TimeoutException('Resume request timed out');
            },
          );
      _check();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ResumeFailure(
          'Please check your account and sign in again.',
          accessDenied: true,
        );
      }
      if (response.statusCode == 404) {
        throw const ResumeFailure(
          'Resume unavailable. Refresh your resumes.',
          reloadRequired: true,
        );
      }
      if (response.statusCode == 409) {
        final code = response.data is Map
            ? (response.data as Map)['code']
            : null;
        final message = switch (code) {
          'retry_unavailable' =>
            'Processing cannot be retried. Upload a new text PDF or DOCX.',
          'upload_expired' => 'This upload is no longer available. Choose the file again to start a new one.',
          'resume_unscored' =>
            'Successful text extraction is required before confirming skills.',
          _ => 'This resume changed. Refresh before another action.',
        };
        throw ResumeFailure(message, reloadRequired: true);
      }
      if (response.statusCode == 429) {
        throw const ResumeFailure(
          'The request or upload budget is reached. Please try again later.',
        );
      }
      if (response.statusCode == 422) {
        throw const ResumeFailure('Check your resume fields and file limits.');
      }
      if (response.statusCode != expectedStatus ||
          response.data is! Map<String, dynamic>) {
        throw const ResumeFailure(
          'Resume service is unavailable. Please retry.',
        );
      }
      return response.data! as Map<String, dynamic>;
    } on ResumeFailure {
      rethrow;
    } catch (_) {
      throw const ResumeFailure('Resume service is unavailable. Please retry.');
    } finally {
      _requests.remove(cancel);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final token in _requests.toList()) {
      token.cancel();
    }
    _apiClient.close(force: true);
    _uploadClient.close(force: true);
  }
}
