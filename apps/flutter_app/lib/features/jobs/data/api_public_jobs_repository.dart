import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../domain/public_jobs_repository.dart';

/// Anonymous discovery client: no Firebase identity, bearer tokens or role claims.
class ApiPublicJobsRepository implements PublicJobsRepository {
  ApiPublicJobsRepository({required Uri origin, HttpClientAdapter? adapter}) {
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
  static final _id = RegExp(r'^[a-f0-9]{32}$');

  @override
  Future<PublicJobsPage> page({
    int pageSize = 10,
    String? cursor,
    String search = '',
    String? workMode,
    String? employmentType,
  }) async {
    if (search.length > 80 ||
        (workMode != null &&
            !{'remote', 'hybrid', 'onsite'}.contains(workMode)) ||
        (employmentType != null &&
            !{
              'full_time',
              'part_time',
              'contract',
              'internship',
            }.contains(employmentType))) {
      throw ArgumentError('Invalid job filters.');
    }
    if (pageSize < 1 ||
        pageSize > 10 ||
        (cursor != null && !_id.hasMatch(cursor))) {
      throw ArgumentError('Invalid job pagination.');
    }
    final data = await _get(
      '/api/v1/public/jobs',
      query: {
        'page_size': pageSize,
        'cursor': ?cursor,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'work_mode': ?workMode,
        'employment_type': ?employmentType,
      },
    );
    try {
      final body = _map(data);
      final raw = body['items'];
      final next = body['next_cursor'];
      if (!body.containsKey('next_cursor') ||
          raw is! List ||
          raw.length > pageSize ||
          (next != null && (next is! String || !_id.hasMatch(next))) ||
          (cursor != null && next is String && next.compareTo(cursor) <= 0)) {
        throw const FormatException();
      }
      final items = raw.map(_job).toList(growable: false);
      String? previous = cursor;
      for (final job in items) {
        if ((previous != null && job.id.compareTo(previous) <= 0) ||
            (next is String && job.id.compareTo(next) > 0)) {
          throw const FormatException();
        }
        previous = job.id;
      }
      return PublicJobsPage(items: items, nextCursor: next as String?);
    } catch (_) {
      throw const PublicJobsFailure(
        'Jobs returned an invalid response. Please retry.',
      );
    }
  }

  @override
  Future<PublishedJob?> detail(String id) async {
    if (!_id.hasMatch(id)) throw ArgumentError('Invalid job ID.');
    final data = await _get('/api/v1/public/jobs/$id', missingAllowed: true);
    if (data == null) return null;
    try {
      final job = _job(data);
      if (job.id != id) throw const FormatException();
      return job;
    } catch (_) {
      throw const PublicJobsFailure(
        'Jobs returned an invalid response. Please retry.',
      );
    }
  }

  Future<Object?> _get(
    String path, {
    Map<String, Object>? query,
    bool missingAllowed = false,
  }) async {
    final cancel = CancelToken();
    try {
      final response = await _dio
          .get<Object?>(path, queryParameters: query, cancelToken: cancel)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              cancel.cancel();
              throw TimeoutException('Job request timed out');
            },
          );
      if (missingAllowed && response.statusCode == 404) return null;
      if (response.statusCode == 429) {
        throw const PublicJobsFailure(
          'Jobs are busy. Please wait before retrying.',
        );
      }
      if (response.statusCode != 200) {
        throw const PublicJobsFailure(
          'Jobs are temporarily unavailable. Please retry.',
        );
      }
      if (response.data == null || jsonEncode(response.data).length > 1000000) {
        throw const PublicJobsFailure(
          'Jobs returned an invalid response. Please retry.',
        );
      }
      return response.data;
    } on PublicJobsFailure {
      rethrow;
    } catch (_) {
      throw const PublicJobsFailure(
        'Could not load jobs. Check your connection and retry.',
      );
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    return value;
  }

  static String _text(Map<String, dynamic> data, String key, int min, int max) {
    final value = data[key];
    if (value is! String ||
        value.length < min ||
        value.length > max ||
        value.trim() != value) {
      throw const FormatException();
    }
    return value;
  }

  static List<String> _skills(Object? value) {
    if (value is! List || value.length > 30) throw const FormatException();
    final result = <String>[];
    final seen = <String>{};
    for (final skill in value) {
      if (skill is! String ||
          skill.isEmpty ||
          skill.length > 40 ||
          skill.trim() != skill ||
          !seen.add(skill.toLowerCase())) {
        throw const FormatException();
      }
      result.add(skill);
    }
    return result;
  }

  static PublishedJob _job(Object? value) {
    final data = _map(value);
    final id = _text(data, 'id', 32, 32);
    if (!_id.hasMatch(id)) throw const FormatException();
    final date = _text(data, 'published_at', 20, 40);
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(date)) {
      throw const FormatException();
    }
    final published = DateTime.tryParse(date);
    if (published == null) throw const FormatException();
    return PublishedJob(
      id: id,
      title: _text(data, 'title', 2, 120),
      company: _text(data, 'company_name', 2, 120),
      description: _text(data, 'description', 0, 12000),
      location: _text(data, 'location', 0, 80),
      workMode: switch (data['work_mode']) {
        'remote' => PublishedWorkMode.remote,
        'hybrid' => PublishedWorkMode.hybrid,
        'onsite' => PublishedWorkMode.onsite,
        _ => throw const FormatException(),
      },
      employmentType: switch (data['employment_type']) {
        'full_time' => EmploymentType.fullTime,
        'part_time' => EmploymentType.partTime,
        'contract' => EmploymentType.contract,
        'internship' => EmploymentType.internship,
        _ => throw const FormatException(),
      },
      requiredSkills: _skills(data['required_skills']),
      preferredSkills: _skills(data['preferred_skills']),
      publishedAt: published.toUtc(),
    );
  }

  void close() => _dio.close(force: true);
}
